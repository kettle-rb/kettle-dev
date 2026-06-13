# frozen_string_literal: true

require "json"
require "fileutils"
require "net/http"
require "open3"
require "optparse"
require "pathname"
require "set"
require "time"
require "uri"

require "psych"
begin
  require "ruby-progressbar"
rescue LoadError
  # Progress feedback is helpful but optional; fall back to plain status lines.
end

module Kettle
  module Dev
    # CLI to scan GitHub Action workflow files and pin mutable references in `uses:` to commit SHAs.
    class GhaShaPinsCLI
      API_BASE = "https://api.github.com"
      RELEASE_PATH = "releases/latest"
      SHA_RE = /\A[0-9a-f]{40}\z/i
      WEAK_SHA_RE = /\A[0-9a-f]{7,39}\z/i

      NON_SHA_REASON = "convert_to_sha"
      STALE_SHA_REASON = "upgrade_to_latest_release_sha"
      UPGRADE_REASON = "upgrade_to_allowed_release"
      COMMENT_REASON = "update_version_comment"
      DEFAULT_UPGRADE_LEVEL = "patch"
      DEFAULT_CACHE_TTL_SECONDS = 24 * 60 * 60
      VALID_UPGRADE_LEVELS = %w[major minor patch].freeze

      def initialize(argv, err: $stderr)
        @argv = argv
        @err = err
        @options = {
          root: File.join(Dir.pwd, ".github", "workflows"),
          dry_run: true,
          token: ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"],
          json: false,
          validate: true,
          write: false,
          check: false,
          api_base: API_BASE,
          user_agent: "kettle-gha-sha-pins",
          upgrade: DEFAULT_UPGRADE_LEVEL,
          cache_path: ENV["KETTLE_GHA_SHA_PINS_CACHE"] || PersistentActionCache.default_path,
          refresh_cache: false,
          reject_patterns: Set.new,
          progress: nil
        }
      end

      def run!
        parse!

        @options[:token] ||= gh_auth_token if @options[:api_base] == API_BASE
        persistent_cache = if @options[:cache_path].to_s.empty?
          nil
        else
          PersistentActionCache.new(path: @options[:cache_path])
        end
        client = GitHubClient.new(
          token: @options[:token],
          api_base: @options[:api_base],
          user_agent: @options[:user_agent],
          persistent_cache: persistent_cache,
          refresh_cache: @options[:refresh_cache]
        )

        state = {
          files_scanned: 0,
          files_with_changes: 0,
          updates: 0,
          failures: 0,
          errors: [],
          changed_files: [],
          planned_changes: [],
          outdated_pins: []
        }

        progress_message("Discovering workflow files under #{Kettle::Dev.display_path(@options[:root])}...")
        workflow_files = discover_workflow_files(@options[:root], @options[:reject_patterns])
        progress_message("Discovered #{workflow_files.length} workflow file(s).")

        workflows = load_workflows(workflow_files, state)
        action_count = workflows.sum { |workflow| workflow[:uses_nodes].count { |node| classify_action_ref(node[:value].to_s) } }
        progress_message("Resolving #{action_count} GitHub action reference(s)...") if action_count.positive?
        action_progress = progress_bar(title: "Actions", total: action_count)
        action_plan_cache = {}

        workflows.each do |workflow|
          path = workflow.fetch(:path)
          text = workflow.fetch(:text)
          uses_nodes = workflow.fetch(:uses_nodes)

          edits = []
          uses_nodes.each do |node|
            value = node[:value].to_s
            parsed_ref = classify_action_ref(value)
            next unless parsed_ref

            begin
              action = parsed_ref[:action]
              repo_ref = "#{action[:owner]}/#{action[:repo]}"
              old_ref = action[:ref]
              upgrade_plan = resolve_action_plan(
                cache: action_plan_cache,
                client: client,
                progress: action_progress,
                repo_ref: repo_ref,
                old_ref: old_ref
              )

              updates = nil
              if upgrade_plan[:updates]
                updates = compute_updates(old_ref, upgrade_plan[:updates][:sha], upgrade_plan[:updates][:reason], repo_ref)
                updates[:new_version] = upgrade_plan[:updates][:version]
                updates[:old_version] = upgrade_plan[:current_version]
              end
              if updates.nil? && upgrade_plan[:current_version]
                comment_version = version_comment_from_line(text, node[:line], node[:col], parsed_ref[:value])
                if comment_version && comment_version != upgrade_plan[:current_version]
                  updates = {
                    new_ref: old_ref,
                    new_version: upgrade_plan[:current_version],
                    old_version: comment_version,
                    reason: COMMENT_REASON,
                    action: repo_ref
                  }
                end
              end

              if upgrade_plan[:is_outdated]
                state[:outdated_pins] << {
                  path: path,
                  line: node[:line] + 1,
                  action: repo_ref,
                  old_ref: old_ref,
                  old_version: upgrade_plan[:current_version],
                  new_ref: upgrade_plan[:latest_outdated] ? upgrade_plan[:latest_outdated][:sha] : nil,
                  new_version: upgrade_plan[:latest_outdated] ? upgrade_plan[:latest_outdated][:version] : nil,
                  upgrade_level: @options[:upgrade],
                  reason: upgrade_plan[:reason]
                }
              end

              next unless updates

              replacement = build_replacement_from_line(text, node[:line], node[:col], parsed_ref[:value], updates[:new_ref], updates[:new_version])
              unless replacement
                record_failure(
                  state,
                  path: path,
                  line: node[:line] + 1,
                  error: "token_parse_failed",
                  value: value
                )
                next
              end

              edits << {
                path: path,
                line: node[:line],
                col: node[:col],
                old_ref: old_ref,
                old_version: updates[:old_version],
                new_ref: updates[:new_ref],
                new_version: updates[:new_version],
                reason: updates[:reason],
                start: replacement[:start],
                end: replacement[:end],
                old_value: value,
                new_value: replacement[:new_scalar],
                new_scalar: replacement[:new_scalar],
                action: repo_ref
              }
            ensure
              action_progress&.increment
            end
          end

          if edits.any?
            edited = apply_edits(text, edits)
            if edited[:changed]
              state[:changed_files] << path
              state[:files_with_changes] += 1
              state[:updates] += edits.length
              state[:planned_changes].concat(edited[:edits].map do |entry|
                {
                  path: entry[:path],
                  line: entry[:line] + 1,
                  old_ref: entry[:old_ref],
                  old_version: entry[:old_version],
                  new_ref: entry[:new_ref],
                  new_version: entry[:new_version],
                  reason: entry[:reason],
                  old_value: entry[:old_value],
                  new_value: entry[:new_value],
                  action: entry[:action]
                }
              end)

              if @options[:write]
                File.write(path, edited[:text])
                validate_yaml!(path) if @options[:validate]
              end
            end
          end
        end

        print_report(state)
        return 2 unless state[:failures].zero?
        return 3 if @options[:check] && (state[:updates].positive? || state[:outdated_pins].any?)

        0
      end

      private

      def parse!
        parser = OptionParser.new do |opt|
          opt.banner = "Usage: kettle-gha-sha-pins [options]"
          opt.separator ""
          opt.separator "Normalize GitHub Actions workflow action refs to immutable commit SHAs."
          opt.on("-r", "--root PATH", "Directory to scan (defaults to .github/workflows under cwd)") do |root|
            @options[:root] = root
          end
          opt.on("-w", "--write", "Write edits (dry-run is default)") do
            @options[:write] = true
            @options[:dry_run] = false
          end
          opt.on("--check", "Fail when workflow action pins are stale or mutable") do
            @options[:check] = true
          end
          opt.on("--upgrade LEVEL", "Upgrade strategy: major, minor, patch (default: #{DEFAULT_UPGRADE_LEVEL})") do |level|
            normalized = level.to_s.downcase
            unless VALID_UPGRADE_LEVELS.include?(normalized)
              Kettle::Dev::ExitAdapter.abort("Invalid --upgrade value #{level.inspect}; use one of: #{VALID_UPGRADE_LEVELS.join(", ")}")
            end
            @options[:upgrade] = normalized
          end
          opt.on("--token VALUE", "GitHub token to increase API rate-limit") do |token|
            @options[:token] = token
          end
          opt.on("--refresh-cache", "Bypass cached action release data and refresh discovered actions") do
            @options[:refresh_cache] = true
          end
          opt.on("--cache-path PATH", "Action release cache path (default: #{@options[:cache_path]})") do |path|
            @options[:cache_path] = path
          end
          opt.on("--json", "Emit JSON report") do
            @options[:json] = true
          end
          opt.on("--[no-]progress", "Show progress feedback on STDERR (default: on unless --json)") do |bool|
            @options[:progress] = bool
          end
          opt.on("--skip-pattern PATTERN", "Skip workflow paths matching pattern (repeatable)") do |pattern|
            begin
              @options[:reject_patterns] << Regexp.new(pattern)
            rescue RegexpError => e
              Kettle::Dev::ExitAdapter.abort("Invalid --skip-pattern #{pattern.inspect}: #{e.message}")
            end
          end
          opt.on("--[no-]validate", "Validate YAML after editing") do |bool|
            @options[:validate] = bool
          end
          opt.on("-h", "--help", "Show this help") do
            puts opt
            Kettle::Dev::ExitAdapter.exit(0)
          end
        end
        parser.parse!(@argv)
      end

      def load_workflows(paths, state)
        file_progress = progress_bar(title: "Files", total: paths.length)
        paths.each_with_object([]) do |path, workflows|
          begin
            state[:files_scanned] += 1
            text = begin
              File.read(path)
            rescue Errno::EACCES => e
              record_failure(state, path: path, error: "read_error: #{e.message}")
              next
            end

            parsed = begin
              Psych.parse_stream(text)
            rescue Psych::Exception => e
              record_failure(state, path: path, error: "yaml_parse_error: #{e.message}")
              next
            end

            uses_nodes = extract_uses_nodes(parsed, text)
            workflows << {path: path, text: text, uses_nodes: uses_nodes} unless uses_nodes.empty?
          ensure
            file_progress&.increment
          end
        end
      end

      def resolve_action_plan(cache:, client:, progress:, repo_ref:, old_ref:)
        started_at = monotonic_time
        if cache.key?(repo_ref)
          versions = cache.fetch(repo_ref)
          progress&.log(format("Reused %<ref>s in %<elapsed>.2fs", ref: "#{repo_ref}@#{old_ref}", elapsed: monotonic_time - started_at))
          return determine_upgrade_plan(
            old_ref: old_ref,
            repo_ref: repo_ref,
            versions: versions,
            upgrade_level: @options[:upgrade],
            client: client
          )
        end

        progress&.log("Resolving #{repo_ref}@#{old_ref}")
        versions = client.versions_for_repo(repo_ref)
        cache[repo_ref] = versions
        plan = determine_upgrade_plan(
          old_ref: old_ref,
          repo_ref: repo_ref,
          versions: versions,
          upgrade_level: @options[:upgrade],
          client: client
        )
        progress&.log(format("Resolved %<ref>s in %<elapsed>.2fs", ref: "#{repo_ref}@#{old_ref}", elapsed: monotonic_time - started_at))
        plan
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def progress_enabled?
        return @options[:progress] unless @options[:progress].nil?

        !@options[:json]
      end

      def progress_message(message)
        return unless progress_enabled?

        @err.puts("[kettle-gha-sha-pins] #{message}")
      end

      def gh_auth_token
        stdout, _stderr, status = Open3.capture3("gh", "auth", "token")
        return nil unless status.success?

        token = stdout.to_s.strip
        token.empty? ? nil : token
      rescue Errno::ENOENT
        nil
      end

      def progress_bar(title:, total:)
        return unless progress_enabled?
        return unless total.positive?
        return unless defined?(ProgressBar)

        ProgressBar.create(title: title, total: total, format: "%t %b %c/%C", length: 30, output: @err)
      end

      def discover_workflow_files(root, reject_patterns)
        expanded_root = workflow_analysis_root(root)
        patterns = [
          File.join(expanded_root.to_s, "*.yml"),
          File.join(expanded_root.to_s, "*.yaml")
        ]
        files = Dir.glob(patterns, File::FNM_PATHNAME).uniq.sort
        files.select do |path|
          next false unless File.file?(path)
          next false if reject_patterns.any? { |pattern| pattern.match?(path) }
          true
        end
      end

      def workflow_analysis_root(root)
        expanded_root = Pathname.new(root).expand_path
        workflow_root = expanded_root.join(".github", "workflows")
        return workflow_root if workflow_root.directory?

        expanded_root
      end

      def extract_uses_nodes(parsed, text = nil)
        mapping_node = Psych::Nodes::Mapping
        scalar_node = Psych::Nodes::Scalar
        sequence_node = Psych::Nodes::Sequence

        nodes = []
        fallback_locations = {}
        walk = lambda do |node|
          case node
          when mapping_node
            node.children.each_slice(2) do |key_node, value_node|
              next unless key_node.is_a?(scalar_node)
              if key_node.value == "uses" && value_node.is_a?(scalar_node)
                line, col = if value_node.respond_to?(:start_line) && value_node.respond_to?(:start_column)
                  [value_node.start_line, value_node.start_column]
                else
                  fallback_uses_location(text, value_node.value, fallback_locations)
                end
                nodes << {
                  line: line,
                  col: col,
                  value: value_node.value
                }
                next
              end
              walk.call(value_node)
            end
          when sequence_node
            node.children.each { |child| walk.call(child) }
          else
            if node.respond_to?(:children) && node.children
              node.children.each { |child| walk.call(child) }
            end
          end
        end

        parsed.children.each { |node| walk.call(node) }
        nodes.compact
      end

      def fallback_uses_location(text, value, used_locations)
        return [0, 0] unless text

        text.each_line.with_index do |line, index|
          next if used_locations[index]

          marker = line.index("uses:")
          next unless marker

          value_index = line.index(value.to_s, marker + 5)
          next unless value_index

          used_locations[index] = true
          return [index, value_index]
        end

        [0, 0]
      end

      def classify_action_ref(value)
        return nil unless value.is_a?(String)
        trimmed = value.strip

        return nil if trimmed.empty?
        return nil if trimmed.start_with?("./", "../", "/")
        return nil if trimmed.start_with?("docker://")
        return nil if trimmed.include?("${{")
        return nil unless trimmed.include?("@")

        repo_part, delimiter, ref = trimmed.rpartition("@")
        return nil unless delimiter == "@"
        return nil if repo_part.to_s.empty? || ref.to_s.empty?

        parts = repo_part.split("/")
        return nil if parts.length < 2
        return nil if parts[0].empty? || parts[1].empty?

        {
          value: trimmed,
          action: {
            owner: parts[0],
            repo: parts[1],
            path: (parts.length > 2) ? parts[2..-1].join("/") : nil,
            ref: ref
          }
        }
      end

      def parse_release_version(value)
        normalized = value.to_s.sub(/\A[vV]/, "")
        return nil unless normalized.match?(/\A(?:\d+|\d+\.\d+\.\d+(?:[-.]?[0-9A-Za-z.-]+)?)\z/)

        Gem::Version.new(normalized)
      rescue ArgumentError
        nil
      end

      def matching_version_entry(versions, current_ref, current_sha, client, repo_ref)
        parsed = parse_release_version(current_ref)
        if parsed
          direct = versions.find { |entry| entry[:tag] == current_ref }
          return direct if direct
        end

        return nil unless current_sha

        prefix = current_sha[0, 40]
        versions.find do |entry|
          sha = version_entry_sha(entry, client, repo_ref)
          sha.to_s.start_with?(prefix)
        end
      end

      def choose_upgrade_target(current_version, versions, level)
        current = parse_release_version(current_version)
        return nil if current.nil?
        return nil if level != "major" && major_line_version?(current_version)

        candidates = versions.select do |entry|
          next false unless entry[:version_obj].is_a?(Gem::Version)
          next false unless entry[:version_obj] > current
          next false if entry[:version_obj].prerelease? && !current.prerelease?
          next false if level != "major" && major_line_version?(entry[:version])

          case level
          when "patch"
            entry[:version_obj].segments[0, 2] == current.segments[0, 2]
          when "minor"
            entry[:version_obj].segments[0] == current.segments[0]
          else
            true
          end
        end

        candidates.max_by { |entry| entry[:version_obj] }
      end

      def major_line_version?(value)
        value.to_s.match?(/\A\d+\z/)
      end

      def latest_outdated_target(current_version, versions)
        current = parse_release_version(current_version)
        return nil if current.nil?

        versions
          .select do |entry|
            entry[:version_obj].is_a?(Gem::Version) &&
              entry[:version_obj] > current &&
              (!entry[:version_obj].prerelease? || current.prerelease?)
          end
          .max_by { |entry| entry[:version_obj] }
      end

      def determine_upgrade_plan(old_ref:, repo_ref:, versions:, upgrade_level:, client:)
        level = upgrade_level.to_s.downcase
        level = DEFAULT_UPGRADE_LEVEL unless VALID_UPGRADE_LEVELS.include?(level)

        current_ref = old_ref.to_s.strip
        return {is_outdated: false, updates: nil, reason: nil, current_version: nil} if current_ref.empty?

        available_versions = versions || []
        latest = available_versions.first

        current_sha = if SHA_RE.match?(current_ref) || WEAK_SHA_RE.match?(current_ref)
          current_ref
        else
          client.commit_sha(repo_ref, current_ref)
        end
        parsed_current_ref = parse_release_version(current_ref)
        version_equivalent_entry = if parsed_current_ref
          available_versions.find { |entry| entry[:version_obj] == parsed_current_ref }
        end
        matched_entry = matching_version_entry(available_versions, current_ref, current_sha, client, repo_ref)
        unresolved_version_ref = false
        if matched_entry.nil? && current_sha.to_s.empty? && version_equivalent_entry && non_sha?(current_ref)
          matched_entry = version_equivalent_entry
          unresolved_version_ref = true
        end
        current_version = matched_entry ? matched_entry[:version] : nil

        updates = nil
        reason = nil
        is_outdated = false
        latest_outdated = nil

        if current_version
          latest_outdated = latest_outdated_target(current_version, available_versions)
          target = choose_upgrade_target(current_version, available_versions, level)
          target_sha = target ? version_entry_sha(target, client, repo_ref) : nil
          latest_outdated_sha = latest_outdated ? version_entry_sha(latest_outdated, client, repo_ref) : nil
          if latest_outdated && stale_sha?(current_ref, latest_outdated_sha)
            latest_outdated = latest_outdated.merge(sha: latest_outdated_sha)
            is_outdated = true
            reason = UPGRADE_REASON
          end
          if target && stale_sha?(current_ref, target_sha)
            updates = {
              sha: target_sha,
              version: target[:version],
              reason: UPGRADE_REASON
            }
            reason ||= UPGRADE_REASON
          end
          if updates.nil? && unresolved_version_ref
            matched_sha = version_entry_sha(matched_entry, client, repo_ref)
            if stale_sha?(current_ref, matched_sha)
              updates = {
                sha: matched_sha,
                version: nil,
                reason: NON_SHA_REASON
              }
              latest_outdated ||= matched_entry.merge(sha: matched_sha)
              is_outdated = true
              reason ||= NON_SHA_REASON
            end
          end
        elsif current_sha && non_sha?(current_ref)
          if stale_sha?(current_ref, current_sha)
            updates = {
              sha: current_sha,
              version: nil,
              reason: NON_SHA_REASON
            }
            reason = NON_SHA_REASON
          end
        elsif current_sha
          latest_sha = latest ? version_entry_sha(latest, client, repo_ref) : nil
          if latest && stale_sha?(current_ref, latest_sha)
            latest_outdated = latest.merge(sha: latest_sha)
            updates = {
              sha: latest_sha,
              version: latest[:version],
              reason: STALE_SHA_REASON
            }
            reason = STALE_SHA_REASON
            is_outdated = true
          end
        end

        {
          is_outdated: is_outdated,
          updates: updates,
          reason: reason,
          current_version: current_version,
          latest_outdated: latest_outdated
        }
      end

      def version_entry_sha(entry, client, repo_ref)
        return nil unless entry
        return entry[:sha] unless entry[:sha].to_s.empty?

        sha = client.commit_sha(repo_ref, entry[:tag])
        entry[:sha] = sha
        sha
      end

      def short_sha?(candidate)
        return false unless candidate
        WEAK_SHA_RE.match?(candidate)
      end

      def non_sha?(candidate)
        !SHA_RE.match?(candidate) && !WEAK_SHA_RE.match?(candidate)
      end

      def stale_sha?(current, latest)
        return false if current.nil? || latest.nil?
        current_down = current.downcase
        latest_down = latest.downcase

        # If `current` is shorter than full SHA, treat prefixes as equal when they match the head
        if current_down.length < latest_down.length
          !latest_down.start_with?(current_down)
        else
          current_down != latest_down
        end
      end

      def compute_updates(old_ref, replacement, reason, action)
        return nil if replacement.nil? || replacement.empty?
        return nil if old_ref == replacement

        {
          new_ref: replacement,
          reason: reason,
          action: action
        }
      end

      def extract_scalar_token(raw_text)
        return nil if raw_text.nil? || raw_text.empty?

        if (match = raw_text.match(/\A"((?:\\.|[^"\\])*)"/))
          return {
            token: match[1].gsub(/\\./) { |frag| frag[1] },
            span: match[0].length,
            quote: :double,
            raw: match[0]
          }
        end

        if (match = raw_text.match(/\A'((?:''|[^'])*)'/))
          return {
            token: match[1].gsub("''", "'"),
            span: match[0].length,
            quote: :single,
            raw: match[0]
          }
        end

        match = raw_text.match(/\A([^\s#]+)(?=\s*(?:#|$))/)
        return nil unless match

        {
          token: match[1],
          span: match[0].length,
          quote: :plain,
          raw: match[0]
        }
      end

      def normalize_quote_scalar(value, quote)
        case quote
        when :single
          "'#{value.gsub("'", "''")}'"
        when :double
          %("#{value.gsub("\\", "\\\\").gsub('"', '\\"')}")
        else
          value
        end
      end

      def render_replacement(old_token, new_ref, quote)
        at_index = old_token.rindex("@")
        return nil if at_index.nil?

        replacement_token = old_token[0...at_index + 1] + new_ref
        {
          token: replacement_token,
          quoted: normalize_quote_scalar(replacement_token, quote)
        }
      end

      def version_comment_from_line(text, line, col, old_token)
        line_text = text.lines[line]
        return nil if line_text.nil?

        raw = line_text[col..-1]
        return nil if raw.nil?

        token_info = extract_scalar_token(raw)
        return nil unless token_info
        return nil unless token_info[:token] == old_token

        suffix = raw[token_info[:span]..-1].to_s
        match = suffix.match(/\A\s+#\s*v?(\d+\.\d+\.\d+(?:[-.]?[0-9A-Za-z.-]+)?)/)
        match && match[1]
      end

      def build_replacement_from_line(text, line, col, old_token, new_ref, new_version = nil)
        line_text = text.lines[line]
        return nil if line_text.nil?

        raw = line_text[col..-1]
        return nil if raw.nil?

        token_info = extract_scalar_token(raw)
        return nil unless token_info
        return nil unless token_info[:token] == old_token

        rendered = render_replacement(old_token, new_ref, token_info[:quote])
        return nil unless rendered

        span = token_info[:span]
        new_scalar = rendered[:quoted]
        if new_version && token_info[:quote] == :plain
          suffix = raw[span..-1].to_s
          comment = suffix.match(/\A(?<prefix>\s+#\s*)v?\d+\.\d+\.\d+(?:[-.]?[0-9A-Za-z.-]+)?/)
          if comment
            span += comment[0].length
            new_scalar += "#{comment[:prefix]}v#{new_version}"
          end
        end

        {
          start: col,
          end: col + span,
          new_scalar: new_scalar,
          new_ref: new_ref,
          old_token: old_token
        }
      end

      def apply_edits(original_text, edits)
        lines = original_text.lines
        grouped = edits.group_by { |entry| entry[:line] }
        updated = lines.dup

        grouped.each_value do |entries|
          entries = entries.sort_by { |entry| -entry[:start] }
          line_num = entries[0][:line]
          line = updated[line_num]
          next if line.nil?

          entries.each do |entry|
            line = line[0...entry[:start]].to_s + entry[:new_scalar] + line[entry[:end]..-1].to_s
          end
          updated[line_num] = line
        end

        new_text = updated.join
        {
          text: new_text,
          changed: new_text != original_text,
          edits: edits
        }
      end

      def validate_yaml!(path)
        Psych.parse_stream(File.read(path))
      end

      def record_failure(state, path:, error:, line: nil, value: nil)
        state[:failures] += 1
        state[:errors] << {
          path: path,
          line: line,
          error: error,
          value: value
        }.delete_if { |_key, value| value.nil? }
      end

      def print_report(state)
        mode = @options[:write] ? "write" : "dry-run"
        if @options[:json]
          payload = {
            mode: mode,
            dry_run: @options[:dry_run],
            root: @options[:root],
            files_scanned: state[:files_scanned],
            files_with_changes: state[:files_with_changes],
            updates: state[:updates],
            failures: state[:failures],
            outdated_pins: state[:outdated_pins],
            changed_files: state[:changed_files].sort,
            planned_changes: state[:planned_changes].sort_by { |c| [c[:path], c[:line], c[:new_ref]] },
            errors: state[:errors]
          }
          puts JSON.pretty_generate(payload)
          return
        end

        lines = []
        lines << "kettle-gha-sha-pins report"
        lines << "  mode: #{mode}"
        lines << "  check: #{@options[:check]}"
        lines << "  root: #{@options[:root]}"
        lines << "  scanned: #{state[:files_scanned]}"
        lines << "  changed_files: #{state[:changed_files].length}"
        lines << "  planned_updates: #{state[:updates]}"
        lines << "  outdated_pins: #{state[:outdated_pins].length}"
        lines << "  failures: #{state[:failures]}"
        lines << ""

        if state[:errors].any?
          lines << "Errors:"
          state[:errors].sort_by { |error| [error[:path], error[:line].to_i] }.each do |error|
            lines << if error[:line]
              "- #{error[:path]}:#{error[:line]} #{error[:error]}"
            else
              "- #{error[:path]} #{error[:error]}"
            end
          end
          lines << ""
        end

        if state[:outdated_pins].empty?
          lines << "Outdated pins: none"
        else
          lines << "Outdated pins (#{state[:outdated_pins].length}):"
          state[:outdated_pins].sort_by { |c| [c[:path], c[:line], c[:old_ref]] }.each do |pin|
            from = pin[:old_version] || pin[:old_ref]
            to = pin[:new_version] || pin[:new_ref]
            lines << "- #{pin[:path]}:#{pin[:line]} #{pin[:action]} #{from} -> #{to} #{pin[:reason]}"
          end
          lines << ""
        end

        if state[:planned_changes].empty?
          lines << "Outdated actions: none"
        else
          lines << "Outdated actions (#{state[:planned_changes].length}):"
          lines << "Action Current Latest Location Reason"
          state[:planned_changes].sort_by { |c| [c[:action], c[:path], c[:line]] }.each do |change|
            current = change[:old_version] || change[:old_ref]
            latest = change[:new_version] || change[:new_ref]
            location = "#{change[:path]}:#{change[:line]}"
            lines << "#{change[:action]} #{current} #{latest} #{location} #{change[:reason]}"
          end
          lines << ""
        end

        if state[:planned_changes].empty?
          lines << "No change candidates found."
        else
          lines << "Planned changes (#{state[:planned_changes].length}):"
          state[:planned_changes].sort_by { |c| [c[:path], c[:line], c[:old_ref]] }.each do |change|
            from = change[:old_version] || change[:old_ref]
            to = change[:new_version] || change[:new_ref]
            lines << "- #{change[:path]}:#{change[:line]} #{from} -> #{to} #{change[:reason]}"
          end
        end
        if @options[:check] && (state[:planned_changes].any? || state[:outdated_pins].any?)
          lines << ""
          lines << "Recommended fix: kettle-gha-sha-pins --write --upgrade #{@options[:upgrade]}"
        end

        puts lines.join("
")
      end

      # Persistent cache of GitHub Action release versions and target SHAs.
      class PersistentActionCache
        VERSION = 2

        def self.default_path
          state_home = ENV["XDG_STATE_HOME"]
          state_home = File.join(Dir.home, ".local", "state") if state_home.to_s.empty?
          File.join(state_home, "kettle-dev", "gha-sha-pins-cache.json")
        rescue ArgumentError
          nil
        end

        def initialize(path:, ttl_seconds: DEFAULT_CACHE_TTL_SECONDS, clock: -> { Time.now })
          @path = path
          @ttl_seconds = ttl_seconds
          @clock = clock
          @data = nil
        end

        def versions_for_repo(repo_ref, fresh: true)
          action = action_data(repo_ref)
          return nil unless action

          versions = action.fetch("versions", {}).values
          return nil if versions.empty?

          entries = if fresh
            versions.select { |entry| fresh_entry?(entry) }
          else
            versions
          end
          return nil if entries.empty?
          return nil if fresh && entries.length != versions.length

          entries.filter_map { |entry| deserialize_version_entry(entry) }
            .sort_by { |entry| entry[:version_obj] }
            .reverse
        end

        def write_versions(repo_ref, versions)
          return if @path.to_s.empty?
          return if repo_ref.to_s.empty?

          action = data.fetch("actions")[repo_ref] ||= {}
          stored_versions = action["versions"] ||= {}
          timestamp = @clock.call.utc.iso8601

          versions.each do |entry|
            version = entry[:version].to_s
            next if version.empty?

            stored_versions[version] = {
              "tag" => entry[:tag].to_s,
              "version" => version,
              "sha" => entry[:sha].to_s,
              "cached_at" => timestamp
            }
          end

          action["targets"] = target_cache(stored_versions.values)
          save!
        end

        def ref_sha(repo_ref, ref, fresh: true)
          action = action_data(repo_ref)
          return nil unless action

          refs = action.fetch("refs", {})
          entry = refs[ref.to_s]
          return nil unless entry
          return nil if fresh && !fresh_entry?(entry)

          sha = entry["sha"].to_s
          sha.empty? ? nil : sha
        end

        def write_ref_sha(repo_ref, ref, sha)
          return if @path.to_s.empty?
          return if repo_ref.to_s.empty? || ref.to_s.empty? || sha.to_s.empty?

          action = data.fetch("actions")[repo_ref] ||= {}
          refs = action["refs"] ||= {}
          refs[ref.to_s] = {
            "sha" => sha.to_s[0, 40],
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

        def action_data(repo_ref)
          data.fetch("actions")[repo_ref]
        end

        def load_data
          parsed = if @path && File.file?(@path)
            JSON.parse(File.read(@path))
          end
          return empty_data unless parsed.is_a?(Hash)
          return empty_data unless parsed["version"].to_i == VERSION

          parsed["version"] ||= VERSION
          parsed["actions"] = {} unless parsed["actions"].is_a?(Hash)
          parsed
        rescue JSON::ParserError, Errno::EACCES
          empty_data
        end

        def empty_data
          {"version" => VERSION, "actions" => {}}
        end

        def save!
          FileUtils.mkdir_p(File.dirname(@path))
          File.write(@path, JSON.pretty_generate(data) + "\n")
        end

        def deserialize_version_entry(entry)
          version = entry["version"].to_s
          parsed = parse_version(version)
          return nil unless parsed

          {
            tag: entry["tag"].to_s,
            version_obj: parsed,
            version: version,
            sha: entry["sha"].to_s
          }
        end

        def target_cache(version_entries)
          entries = version_entries.filter_map do |entry|
            deserialized = deserialize_version_entry(entry)
            next unless deserialized

            deserialized.merge(cached_at: entry["cached_at"].to_s)
          end
          return {} if entries.empty?

          full_semver_entries = entries.reject { |entry| major_line_version?(entry[:version]) }
          {
            "patch" => full_semver_entries.group_by { |entry| entry[:version_obj].segments[0, 2].join(".") }
              .transform_values { |group| serialize_target(group.max_by { |entry| entry[:version_obj] }) },
            "minor" => full_semver_entries.group_by { |entry| entry[:version_obj].segments[0].to_s }
              .transform_values { |group| serialize_target(group.max_by { |entry| entry[:version_obj] }) },
            "major" => {"*" => serialize_target(entries.max_by { |entry| entry[:version_obj] })}
          }
        end

        def serialize_target(entry)
          {
            "tag" => entry[:tag],
            "version" => entry[:version],
            "sha" => entry[:sha],
            "cached_at" => entry[:cached_at]
          }
        end

        def parse_version(value)
          Gem::Version.new(value)
        rescue ArgumentError
          nil
        end

        def major_line_version?(value)
          value.to_s.match?(/\A\d+\z/)
        end

        def fresh_entry?(entry)
          cached_at = Time.iso8601(entry["cached_at"].to_s)
          cached_at >= @clock.call - @ttl_seconds
        rescue ArgumentError
          false
        end
      end

      # Lightweight GitHub API client for commit and release SHA resolution.
      class GitHubClient
        def initialize(token:, api_base:, user_agent:, persistent_cache: nil, refresh_cache: false)
          @token = token
          @api_base = api_base
          @user_agent = user_agent
          @persistent_cache = persistent_cache
          @refresh_cache = refresh_cache
          @commit_cache = {}
          @release_cache = {}
        end

        def versions_for_repo(repo_ref)
          return [] if repo_ref.to_s.empty?
          return @release_cache[repo_ref] if @release_cache.key?(repo_ref)

          unless @refresh_cache
            cached = @persistent_cache&.versions_for_repo(repo_ref, fresh: true)
            if cached
              @release_cache[repo_ref] = cached
              return cached
            end
          end

          data = request_json("/repos/#{repo_ref}/releases?per_page=100")
          unless data.is_a?(Array)
            fallback = @persistent_cache&.versions_for_repo(repo_ref, fresh: false)
            return fallback if fallback

            return []
          end

          tag_shas = tag_ref_shas(repo_ref)
          releases = data.filter_map do |release|
            next unless release.is_a?(Hash)

            tag = release["tag_name"].to_s
            parsed = parse_release_version_text(tag)
            next unless parsed

            {
              tag: tag,
              version_obj: parsed,
              version: parsed.to_s,
              sha: tag_shas[tag]
            }
          end
          released_tags = releases.each_with_object({}) { |release, memo| memo[release[:tag]] = true }
          tag_versions = tag_shas.filter_map do |tag, sha|
            next if released_tags[tag]

            parsed = parse_release_version_text(tag)
            next unless parsed

            {
              tag: tag,
              version_obj: parsed,
              version: parsed.to_s,
              sha: sha
            }
          end
          releases.concat(tag_versions)

          releases.sort_by! { |release| release[:version_obj] }
          releases.reverse!
          @persistent_cache&.write_versions(repo_ref, releases)
          @release_cache[repo_ref] = releases
          releases
        end

        def commit_sha(repo_ref, ref)
          return nil if repo_ref.to_s.empty? || ref.to_s.empty?

          cache_key = "commit:#{repo_ref}:#{ref}"
          return @commit_cache[cache_key] if @commit_cache.key?(cache_key)

          unless @refresh_cache
            cached = @persistent_cache&.ref_sha(repo_ref, ref, fresh: true)
            if cached
              @commit_cache[cache_key] = cached
              return cached
            end
          end

          data = request_json("/repos/#{repo_ref}/commits/#{uri_encode(ref)}")
          sha = if data.is_a?(Hash)
            data.fetch("sha", "")[0, 40]
          end
          if sha.to_s.empty?
            sha = @persistent_cache&.ref_sha(repo_ref, ref, fresh: false)
          else
            @persistent_cache&.write_ref_sha(repo_ref, ref, sha)
          end
          @commit_cache[cache_key] = sha
          sha
        end

        def release_latest_sha(repo_ref)
          versions = versions_for_repo(repo_ref)
          latest = versions.first
          latest ? version_entry_sha(repo_ref, latest) : nil
        end

        private

        def parse_release_version_text(value)
          normalized = value.to_s.sub(/\A[vV]/, "")
          return nil unless normalized.match?(/\A(?:\d+|\d+\.\d+\.\d+(?:[-.]?[0-9A-Za-z.-]+)?)\z/)

          Gem::Version.new(normalized)
        rescue ArgumentError
          nil
        end

        def tag_ref_shas(repo_ref)
          data = request_json("/repos/#{repo_ref}/git/matching-refs/tags/")
          return {} unless data.is_a?(Array)

          data.each_with_object({}) do |entry, memo|
            ref = entry["ref"].to_s
            next unless ref.start_with?("refs/tags/")

            tag = ref.sub(%r{\Arefs/tags/}, "")
            object = entry["object"]
            next unless object.is_a?(Hash)

            sha = object["sha"].to_s[0, 40]
            case object["type"]
            when "commit"
              memo[tag] = sha
            when "tag"
              dereferenced_sha = annotated_tag_commit_sha(repo_ref, sha)
              memo[tag] = dereferenced_sha if dereferenced_sha
            end
          end
        end

        def annotated_tag_commit_sha(repo_ref, tag_sha)
          return nil if tag_sha.to_s.empty?

          data = request_json("/repos/#{repo_ref}/git/tags/#{tag_sha}")
          return nil unless data.is_a?(Hash)

          object = data["object"]
          return nil unless object.is_a?(Hash)
          return nil unless object["type"] == "commit"

          object["sha"].to_s[0, 40]
        end

        def request_json(path, redirects: 3)
          uri = URI.join(@api_base + "/", path)

          response = nil
          loop do
            request = Net::HTTP::Get.new(uri)
            request["Accept"] = "application/vnd.github+json"
            request["User-Agent"] = @user_agent
            request["X-GitHub-Api-Version"] = "2022-11-28"
            request["Authorization"] = "Bearer #{@token}" if @token && !@token.empty?

            response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
              http.request(request)
            end

            break unless response.code.to_i.between?(300, 399)
            redirects -= 1
            return nil if redirects.negative?

            location = response["location"].to_s
            return nil if location.empty?

            uri = URI.join(uri.to_s, location)
          end

          return nil unless response.code.to_i == 200

          begin
            JSON.parse(response.body)
          rescue JSON::ParserError
            nil
          end
        end

        def uri_encode(value)
          URI.encode_www_form_component(value)
        end

        def version_entry_sha(repo_ref, entry)
          return nil unless entry
          return entry[:sha] unless entry[:sha].to_s.empty?

          entry[:sha] = commit_sha(repo_ref, entry[:tag])
        end
      end
    end
  end
end
