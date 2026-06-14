# frozen_string_literal: true

require "optparse"
require "English"
require "uri"
require "net/http"
require "openssl"
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
    #   3) Validate Markdown image links resolve via HTTP(S) HEAD.
    #
    # Usage: Kettle::Dev::PreReleaseCLI.new(check_num: 1).run
    class PreReleaseCLI
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

      # Markdown parsing helpers
      module Markdown
        module_function

        SCRATCH_PATH_PREFIXES = %w[
          tmp/
          .git/
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
      def initialize(check_num: 1)
        @check_num = (check_num || 1).to_i
        @check_num = 1 if @check_num < 1
      end

      # Execute configured checks starting from @check_num.
      # @return [void]
      def run
        checks = []
        checks << method(:check_github_actions_sha_pins!)
        checks << method(:check_markdown_uri_normalization!)
        checks << method(:check_markdown_images_http!)

        start = @check_num
        raise ArgumentError, "check_num must be >= 1" if start < 1

        begin_idx = start - 1
        checks[begin_idx..-1].each_with_index do |check, i|
          idx = begin_idx + i + 1
          puts "[kettle-pre-release] Running check ##{idx} of #{checks.size}"
          check.call
        end
        nil
      end

      # Check 1: Ensure GitHub Actions workflow action refs are current SHA pins.
      # @return [void]
      def check_github_actions_sha_pins!
        puts "[kettle-pre-release] Check 1: Validate GitHub Actions SHA pins"
        status = Kettle::Dev::GhaShaPinsCLI.new(["--root", Dir.pwd, "--check", "--upgrade", "major"]).run!
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
            addr = Addressable::URI.parse(url_str)
            normalized = addr.normalize.to_s
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
        nil
      end

      # Check 3: Validate Markdown image links by HTTP HEAD (no rescue for parse failures)
      # @return [void]
      def check_markdown_images_http!
        puts "[kettle-pre-release] Check 3: Validate Markdown image links (HTTP HEAD)"
        urls = Markdown.extract_image_urls_from_files
        puts "[kettle-pre-release] Found #{urls.size} unique image URL(s)."
        failures = []
        urls.each do |url|
          print("  -> #{url} … ")
          ok = HTTP.head_ok?(url)
          if ok
            puts "OK"
          else
            puts "FAIL"
            failures << url
          end
        end
        if failures.any?
          warn("[kettle-pre-release] #{failures.size} image URL(s) failed validation:")
          failures.each { |u| warn("  - #{u}") }
          Kettle::Dev::ExitAdapter.abort("Image link validation failed")
        else
          puts "[kettle-pre-release] All image links validated."
        end
        nil
      end
    end
  end
end
