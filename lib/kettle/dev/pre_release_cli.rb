# frozen_string_literal: true

require "optparse"
require "English"
require "json"
require "fileutils"
require "open3"
require "yaml"
require "uri"
require "net/http"
require "openssl"
require "time"
require_relative "cache_progress"
require_relative "markdown_reference_validator"
require "kettle/ndjson"
begin
  require "addressable/uri"
rescue LoadError
  # addressable is optional; code will fallback to URI
end

module Kettle
  module Dev
    # PreReleaseCLI: run pre-release checks before invoking full release workflow.
    # Checks:
    #   1) Ensure GitHub Actions workflow actions are pinned to current SHAs.
    #   2) Normalize Markdown image URLs using Addressable normalization.
    #   3) Validate Markdown references and local heading targets.
    #   4) Validate Markdown image links resolve via cached HTTP(S) HEAD/GET.
    #
    # Usage: Kettle::Dev::PreReleaseCLI.new(check_num: 1).run
    class PreReleaseCLI
      IMAGE_URL_CACHE_TTL_SECONDS = 7 * 24 * 60 * 60
      DEFAULT_IMAGE_URL_SKIP_PATTERNS = [
        "https://api.star-history.com/svg*",
        "https://star-history.dera.page/svg*"
      ].freeze
      FAMILY_CONFIG_PATHS = [".kettle-family.yml", ".structuredmerge/kettle-family.yml"].freeze

      # Simple HTTP helpers for link validation
      module HTTP
        module_function

        # Unicode-friendly HTTP URI parser with Addressable fallback.
        # @param url_str [String]
        # @return [URI]
        def parse_http_uri(url_str)
          if defined?(Addressable::URI)
            addr = Addressable::URI.parse(url_str)
            # Build a standard URI with properly encoded host/path/query for Net::HTTP
            # Addressable handles unicode and punycode automatically via normalization
            addr = addr.normalize
            # Net::HTTP expects a ::URI; convert via to_s then URI.parse
            URI.parse(addr.to_s)
          else
            # Fallback: try URI.parse directly; users can add addressable to unlock unicode support
            URI.parse(url_str)
          end
        end

        # Perform HTTP HEAD against the given url.
        # Falls back to GET when HEAD is not allowed.
        # @param url_str [String]
        # @param limit [Integer] max redirects
        # @param timeout [Integer] per-request timeout seconds
        # @return [Boolean] true when successful (2xx) after following redirects
        def head_ok?(url_str, limit: 5, timeout: 10)
          uri = parse_http_uri(url_str)
          raise ArgumentError, "unsupported URI scheme: #{uri.scheme.inspect}" unless %w[http https].include?(uri.scheme)

          request = Net::HTTP::Head.new(uri)
          perform(uri, request, limit: limit, timeout: timeout)
        end

        # @api private
        def perform(uri, request, limit:, timeout:)
          raise ArgumentError, "too many redirects" if limit <= 0

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.read_timeout = timeout
          http.open_timeout = timeout
          http.ssl_timeout = timeout if http.respond_to?(:ssl_timeout=)
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?

          response = http.start { |h| h.request(request) }

          case response
          when Net::HTTPRedirection
            location = response["location"]
            return false unless location

            new_uri = parse_http_uri(location)
            new_uri = uri + location if new_uri.relative?
            head_ok?(new_uri.to_s, limit: limit - 1, timeout: timeout)
          when Net::HTTPSuccess
            true
          else
            if response.is_a?(Net::HTTPMethodNotAllowed)
              get_req = Net::HTTP::Get.new(uri)
              get_resp = http.start { |h| h.request(get_req) }
              return get_resp.is_a?(Net::HTTPSuccess)
            end
            false
          end
        rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, OpenSSL::SSL::SSLError => e
          warn("[kettle-pre-release] HTTP error for #{uri}: #{e.class}: #{e.message}")
          false
        end
      end

      # Persistent cache of successfully validated Markdown image URLs.
      class ImageUrlCache
        VERSION = 1

        def self.default_path
          state_home = ENV["XDG_STATE_HOME"]
          state_home = File.join(Dir.home, ".local", "state") if state_home.to_s.empty?
          File.join(state_home, "kettle-dev", "image-url-cache.json")
        rescue ArgumentError
          nil
        end

        def initialize(path:, ttl_seconds: IMAGE_URL_CACHE_TTL_SECONDS, clock: -> { Time.now })
          @path = path
          @ttl_seconds = ttl_seconds
          @clock = clock
          @data = nil
        end

        def fresh_success?(url)
          entry = data.fetch("images")[url.to_s]
          return false unless entry.is_a?(Hash)
          return false unless entry["ok"] == true

          fresh_entry?(entry)
        end

        def write_success(url)
          return if @path.to_s.empty?
          return if url.to_s.empty?

          data.fetch("images")[url.to_s] = {
            "ok" => true,
            "cached_at" => @clock.call.utc.iso8601
          }
          save!
        end

        def to_h
          data
        end

        private

        def data
          @data ||= load_data
        end

        def load_data
          parsed = if @path && File.file?(@path)
            JSON.parse(File.read(@path))
          end
          return empty_data unless parsed.is_a?(Hash)
          return empty_data unless parsed["version"].to_i == VERSION

          parsed["version"] ||= VERSION
          parsed["images"] = {} unless parsed["images"].is_a?(Hash)
          parsed
        rescue JSON::ParserError, Errno::EACCES
          empty_data
        end

        def empty_data
          {"version" => VERSION, "images" => {}}
        end

        def save!
          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, JSON.pretty_generate(data) + "\n")
        end

        def fresh_entry?(entry)
          cached_at = Time.iso8601(entry["cached_at"].to_s)
          cached_at >= @clock.call - @ttl_seconds
        rescue ArgumentError
          false
        end
      end

      # Markdown parsing helpers
      module Markdown
        module_function

        SCRATCH_PATH_PREFIXES = %w[
          tmp/
          .git/
          spec/fixtures/
        ].freeze

        # Extract unique remote HTTP(S) image URLs from markdown or HTML images.
        # @param text [String]
        # @return [Array<String>]
        def extract_image_urls_from_text(text)
          urls = []

          # Inline image syntax
          text.scan(/!\[[^\]]*\]\(([^\s)]+)(?:\s+"[^"]*")?\)/) { |m| urls << m[0] }

          # Reference definitions
          ref_defs = {}
          text.scan(/^\s*\[([^\]]+)\]:\s*(\S+)/) { |m| ref_defs[m[0]] = m[1] }

          # Reference image usage
          text.scan(/!\[[^\]]*\]\[([^\]]+)\]/) do |m|
            id = m[0]
            url = ref_defs[id]
            urls << url if url
          end

          # HTML <img src="...">
          text.scan(/<img\b[^>]*\bsrc\s*=\s*"([^"]+)"[^>]*>/i) { |m| urls << m[0] }
          text.scan(/<img\b[^>]*\bsrc\s*=\s*'([^']+)'[^>]*>/i) { |m| urls << m[0] }

          urls.reject! { |u| u.nil? || u.strip.empty? }
          urls.select! { |u| u =~ %r{^https?://}i }
          urls.uniq
        end

        # Find Markdown files that are part of the releasable project.
        # @return [Array<String>]
        def project_markdown_files
          files = tracked_markdown_files
          return files unless files.empty?

          Dir.glob(["**/*.md", "**/*.md.example"], File::FNM_DOTMATCH).reject { |path| scratch_path?(path) }.sort
        end

        # @return [Array<String>]
        def tracked_markdown_files
          output = IO.popen(["git", "ls-files", "-z", "--", "*.md", "*.md.example"], err: File::NULL, &:read)
          return [] unless $CHILD_STATUS.success?

          output.split("\0").reject { |path| scratch_path?(path) }.sort
        rescue Errno::ENOENT
          []
        end

        # @param path [String]
        # @return [Boolean]
        def scratch_path?(path)
          SCRATCH_PATH_PREFIXES.any? { |prefix| path.start_with?(prefix) }
        end

        # Extract from files matching glob.
        # @param glob_pattern [String, Array<String>]
        # @return [Array<String>]
        def extract_image_urls_from_files(glob_pattern = nil)
          files =
            if glob_pattern.nil?
              project_markdown_files
            elsif glob_pattern.is_a?(String)
              Dir.glob(glob_pattern)
            else
              Array(glob_pattern)
            end
          urls = files.flat_map do |f|
            begin
              extract_image_urls_from_text(File.read(f))
            rescue => e
              warn("[kettle-pre-release] Could not read #{Kettle::Dev.display_path(f)}: #{e.class}: #{e.message}")
              []
            end
          end
          urls.uniq
        end
      end

      # @param check_num [Integer] 1-based index to resume from
      def initialize(check_num: 1, event_recorder: nil)
        @check_num = (check_num || 1).to_i
        @check_num = 1 if @check_num < 1
        @event_recorder = event_recorder
        @image_url_cache_path = configured_image_url_cache_path
        @refresh_image_url_cache = env_truthy?(ENV["KETTLE_IMAGE_URL_CACHE_REFRESH"])
        @image_url_skip_patterns = configured_image_url_skip_patterns
      end

      # Execute configured checks starting from @check_num.
      # @return [void]
      def run
        checks = []
        checks << method(:check_github_actions_sha_pins!)
        checks << method(:check_markdown_uri_normalization!)
        checks << method(:check_markdown_references!)
        checks << method(:check_markdown_images_http!)

        start = @check_num
        raise ArgumentError, "check_num must be >= 1" if start < 1

        begin_idx = start - 1
        checks[begin_idx..-1].each_with_index do |check, i|
          idx = begin_idx + i + 1
          puts "[kettle-pre-release] Running check ##{idx} of #{checks.size}"
          emit_pre_release_event(action: "check", status: "started", check: check_name(check), index: idx, total: checks.size)
          begin
            check.call
            emit_pre_release_event(action: "check", status: "ok", check: check_name(check), index: idx, total: checks.size)
          rescue => error
            emit_pre_release_event(action: "check", status: "failed", check: check_name(check), index: idx, total: checks.size, reason: "#{error.class}: #{error.message}")
            raise
          end
        end
        nil
      end

      # Check 1: Ensure GitHub Actions workflow action refs are current SHA pins.
      # @return [void]
      def check_github_actions_sha_pins!
        offline = env_truthy?(ENV["KETTLE_PRE_RELEASE_GHA_SHA_PINS_OFFLINE"])
        mode = offline ? "offline cache" : "live cache validation"
        puts "[kettle-pre-release] Check 1: Validate GitHub Actions SHA pins (#{mode})"
        args = ["--root", Dir.pwd, "--check", "--upgrade", "major"]
        args << "--offline" if offline
        status = Kettle::Dev::GhaShaPinsCLI.new(args).run!
        return nil if status.zero?

        Kettle::Dev::ExitAdapter.abort("GitHub Actions SHA pin validation failed")
      end

      # Check 2: Normalize Markdown image URLs
      #   Compares URLs to Addressable-normalized form and rewrites Markdown when needed.
      # @return [void]
      def check_markdown_uri_normalization!
        puts "[kettle-pre-release] Check 2: Normalize Markdown image URLs"
        files = Markdown.project_markdown_files
        changed = []
        total_candidates = 0

        files.each do |file|
          begin
            original = File.read(file)
          rescue => e
            warn("[kettle-pre-release] Could not read #{Kettle::Dev.display_path(file)}: #{e.class}: #{e.message}")
            next
          end

          text = original.dup
          urls = Markdown.extract_image_urls_from_text(text)
          next if urls.empty?

          total_candidates += urls.size
          updated = text.dup
          modified = false

          urls.each do |url_str|
            normalized = normalized_markdown_image_url(url_str)
            next if normalized == url_str

            # Replace exact occurrences of the URL in the markdown content
            updated.gsub!(url_str, normalized)
            modified = true
            puts "  -> #{Kettle::Dev.display_path(file)}: normalized #{url_str} -> #{normalized}"
          end

          if modified && updated != original
            begin
              File.write(file, updated)
              changed << file
            rescue => e
              warn("[kettle-pre-release] Could not write #{Kettle::Dev.display_path(file)}: #{e.class}: #{e.message}")
            end
          end
        end

        puts "[kettle-pre-release] Normalization candidates: #{total_candidates}. Files changed: #{changed.uniq.size}."
        emit_pre_release_event(action: "markdown_urls", status: "ok", candidates: total_candidates, changed_files: changed.uniq.size)
        nil
      end

      def normalized_markdown_image_url(url_str)
        # Kettle-Jem template tokens are intentionally not URI components yet;
        # encoding them here prevents the templater from recognizing them.
        return url_str if url_str.include?("{KJ|")

        addr = Addressable::URI.parse(url_str)
        normalized = addr.normalize
        normalized.query = addr.query if addr.query && normalized.query != addr.query
        normalized.to_s
      end

      # Check 3: Validate Markdown references and local heading targets.
      # @return [void]
      def check_markdown_references!
        puts "[kettle-pre-release] Check 3: Validate Markdown references and local heading targets"
        report = MarkdownReferenceValidator.new(
          root: Dir.pwd,
          files: Markdown.project_markdown_files
        ).validate!
        puts "[kettle-pre-release] Markdown references: #{report.reference_count} references, #{report.local_target_count} local targets, #{report.file_count} files."
        emit_pre_release_event(
          action: "markdown_references",
          status: "ok",
          files: report.file_count,
          references: report.reference_count,
          local_targets: report.local_target_count,
          failures: 0
        )
        nil
      end

      # Check 4: Validate Markdown image links by cached HTTP HEAD/GET.
      # @return [void]
      def check_markdown_images_http!
        puts "[kettle-pre-release] Check 4: Validate Markdown image links (cached HTTP HEAD, with GET fallback)"
        urls = Markdown.extract_image_urls_from_files
        puts "[kettle-pre-release] Found #{urls.size} unique image URL(s)."
        skipped = []
        cache = image_url_cache
        progress = CacheProgress.new(
          total: urls.size,
          cached_title: "Images cached",
          live_title: "Images live",
          skipped_title: "Images skipped",
          output: $stdout
        )
        failures = []
        begin
          urls.each do |url|
            if image_url_skipped?(url)
              skipped << url
              progress.skipped
              next
            end

            if cache && !@refresh_image_url_cache && cache.fresh_success?(url)
              progress.cached
              next
            end

            ok = HTTP.head_ok?(url)
            progress.live
            if ok
              cache&.write_success(url)
            else
              failures << url
            end
          end
        ensure
          progress.stop
        end
        puts "[kettle-pre-release] Image URL checks: #{progress.cached_count} cached, #{progress.live_count} live."
        puts "[kettle-pre-release] Skipped #{progress.skipped_count} image URL check(s)." if skipped.any?
        if failures.any?
          emit_pre_release_event(action: "image_links", status: "failed", urls: urls.size, cached: progress.cached_count, live: progress.live_count, skipped: progress.skipped_count, failures: failures.size)
          warn("[kettle-pre-release] #{failures.size} image URL(s) failed validation:")
          failures.each { |u| warn("  - #{u}") }
          Kettle::Dev::ExitAdapter.abort("Image link validation failed")
        else
          emit_pre_release_event(action: "image_links", status: "ok", urls: urls.size, cached: progress.cached_count, live: progress.live_count, skipped: progress.skipped_count, failures: 0)
          puts "[kettle-pre-release] All image links validated."
        end
        nil
      end

      private

      def check_name(check)
        check.name.to_s.sub(/\Acheck_/, "").sub(/!\z/, "")
      end

      def emit_pre_release_event(action:, status:, **payload)
        mark = case status.to_s
        when "started"
          ">"
        when "ok", "skipped"
          "."
        when "failed"
          "!"
        else
          "?"
        end
        Kettle::Ndjson.emit_event(
          @event_recorder,
          "pre_release",
          payload.merge(
            action: action,
            phase: "release",
            status: status,
            mark: mark
          )
        )
      end

      def image_url_cache
        return nil if @image_url_cache_path.to_s.empty?

        @image_url_cache ||= ImageUrlCache.new(path: @image_url_cache_path)
      end

      def configured_image_url_cache_path
        value = ENV.fetch("KETTLE_IMAGE_URL_CACHE", nil)
        return ImageUrlCache.default_path if value.nil? || value.to_s.strip.empty?
        return nil if value.to_s.strip.match?(Kettle::Dev::ENV_FALSE_RE)

        value
      end

      def env_truthy?(value)
        !!value.to_s.strip.match?(/\A(true|y|yes|1|on)\z/i)
      end

      def configured_image_url_skip_patterns
        DEFAULT_IMAGE_URL_SKIP_PATTERNS + family_configured_image_url_skip_patterns
      end

      def family_configured_image_url_skip_patterns
        data = family_config_data
        patterns = data.dig("pre_release", "image_url_skip_patterns")
        Array(patterns).map(&:to_s).reject(&:empty?)
      end

      def family_config_data
        config_path = configured_family_config_path
        return {} unless config_path

        data = stringify_keys(YAML.load_file(config_path) || {})
        data.is_a?(Hash) ? data : {}
      rescue Psych::SyntaxError, Errno::EACCES => e
        warn("[kettle-pre-release] Could not read #{config_path}: #{e.class}: #{e.message}")
        {}
      end

      def configured_family_config_path
        env_path = ENV.fetch("KETTLE_FAMILY_CONFIG", nil)
        return File.expand_path(env_path) if env_path && File.file?(File.expand_path(env_path))

        FAMILY_CONFIG_PATHS.find { |path| File.file?(path) }
      end

      def image_url_skipped?(url)
        return true if github_actions_badge_for_local_workflow?(url)

        @image_url_skip_patterns.any? do |pattern|
          File.fnmatch?(pattern, url, File::FNM_CASEFOLD)
        end
      end

      # A template run can add a workflow and its README badge in the same
      # commit. Before that commit is pushed, GitHub correctly returns 404 for
      # the badge even though the local workflow will make it valid.
      def github_actions_badge_for_local_workflow?(url)
        uri = URI.parse(url)
        return false unless uri.host == "github.com"

        segments = uri.path.split("/").reject(&:empty?)
        return false unless segments.length == 6
        return false unless segments[2, 2] == %w[actions workflows] && segments.last == "badge.svg"
        return false unless local_github_repository_slug == segments.first(2).join("/")

        File.file?(File.join(".github", "workflows", segments[4]))
      rescue URI::InvalidURIError
        false
      end

      def local_github_repository_slug
        return @local_github_repository_slug if defined?(@local_github_repository_slug)

        remote_url, status = Open3.capture2("git", "config", "--get", "remote.origin.url")
        @local_github_repository_slug = status.success? ? github_repository_slug(remote_url) : nil
      end

      def github_repository_slug(remote_url)
        value = remote_url.to_s.strip
        return value.split(":", 2).last.delete_suffix(".git") if value.start_with?("git@github.com:")

        uri = URI.parse(value)
        return unless uri.host == "github.com"

        uri.path.delete_prefix("/").delete_suffix(".git")
      rescue URI::InvalidURIError
        nil
      end

      def stringify_keys(value)
        case value
        when Hash
          value.to_h { |key, item| [key.to_s, stringify_keys(item)] }
        when Array
          value.map { |item| stringify_keys(item) }
        else
          value
        end
      end
    end
  end
end
