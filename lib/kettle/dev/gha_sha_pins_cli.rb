# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "pathname"

require "psych"
require "kettle/gha/pins"
require "ruby-progressbar"
require_relative "cache_progress"

module Kettle
  module Dev
    # CLI to scan GitHub Action workflow files and pin mutable references in `uses:` to commit SHAs.
    class GhaShaPinsCLI
      API_BASE = Kettle::Gha::Pins::API_BASE
      RELEASE_PATH = Kettle::Gha::Pins::RELEASE_PATH
      SHA_RE = Kettle::Gha::Pins::SHA_RE
      WEAK_SHA_RE = Kettle::Gha::Pins::WEAK_SHA_RE

      NON_SHA_REASON = Kettle::Gha::Pins::NON_SHA_REASON
      STALE_SHA_REASON = Kettle::Gha::Pins::STALE_SHA_REASON
      UPGRADE_REASON = Kettle::Gha::Pins::UPGRADE_REASON
      COMMENT_REASON = "update_version_comment"
      DEFAULT_UPGRADE_LEVEL = Kettle::Gha::Pins::DEFAULT_UPGRADE_LEVEL
      DEFAULT_CACHE_TTL_SECONDS = Kettle::Gha::Pins::DEFAULT_CACHE_TTL_SECONDS
      DEFAULT_HTTP_OPEN_TIMEOUT_SECONDS = Kettle::Gha::Pins::DEFAULT_HTTP_OPEN_TIMEOUT_SECONDS
      DEFAULT_HTTP_READ_TIMEOUT_SECONDS = Kettle::Gha::Pins::DEFAULT_HTTP_READ_TIMEOUT_SECONDS
      DEFAULT_HTTP_REFRESH_TIMEOUT_SECONDS = Kettle::Gha::Pins::DEFAULT_HTTP_REFRESH_TIMEOUT_SECONDS
      VALID_UPGRADE_LEVELS = Kettle::Gha::Pins::VALID_UPGRADE_LEVELS
      PersistentActionCache = Kettle::Gha::Pins::PersistentActionCache
      GitHubClient = Kettle::Gha::Pins::GitHubClient
      VERSION_COMMENT_SUFFIX_RE = /\A\s+#\s*v?(?<version>\d+(?:\.\d+\.\d+(?:[-.]?[0-9A-Za-z.-]+)?)?)/
      VERSION_COMMENT_REPLACEMENT_RE = /\A(?<prefix>\s+#\s*)v?\d+(?:\.\d+\.\d+(?:[-.]?[0-9A-Za-z.-]+)?)?/

      def self.release_version_sort_key(entry)
        Kettle::Gha::Pins::VersionRubric.sort_key(entry)
      end

      def self.release_version_specificity(entry)
        Kettle::Gha::Pins::VersionRubric.specificity(entry)
      end

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
        action_progress = CacheProgress.new(
          total: action_count,
          cached_title: "Actions cached",
          live_title: "Actions live",
          output: @err,
          enabled: progress_enabled?
        )
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
        progress_message("Action resolution checks: #{action_progress.cached_count} cached, #{action_progress.live_count} live.") if action_count.positive?

        print_report(state)
        return 2 unless state[:failures].zero?
        return 3 if @options[:check] && state[:updates].positive?

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
        cached = cache.key?(repo_ref)
        plan = Kettle::Gha::Pins.resolve_action_plan(
          cache: cache,
          client: client,
          repo_ref: repo_ref,
          old_ref: old_ref,
          upgrade_level: @options[:upgrade]
        )
        if cached
          progress.cached
        else
          progress.live
        end
        plan
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
        Kettle::Gha::Pins::VersionRubric.parse(value)
      end

      def matching_version_entry(versions, current_ref, current_sha, client, repo_ref)
        Kettle::Gha::Pins.matching_version_entry(versions, current_ref, current_sha, client, repo_ref)
      end

      def choose_upgrade_target(current_version, versions, level)
        Kettle::Gha::Pins::VersionRubric.choose_upgrade_target(current_version, versions, level)
      end

      def major_line_version?(value)
        Kettle::Gha::Pins::VersionRubric.major_line?(value)
      end

      def latest_outdated_target(current_version, versions)
        Kettle::Gha::Pins::VersionRubric.latest_outdated_target(current_version, versions)
      end

      def determine_upgrade_plan(old_ref:, repo_ref:, versions:, upgrade_level:, client:)
        Kettle::Gha::Pins.determine_upgrade_plan(
          old_ref: old_ref,
          repo_ref: repo_ref,
          versions: versions,
          upgrade_level: upgrade_level,
          client: client
        )
      end

      def version_entry_sha(entry, client, repo_ref)
        Kettle::Gha::Pins.version_entry_sha(entry, client, repo_ref)
      end

      def release_version_sort_key(entry)
        self.class.release_version_sort_key(entry)
      end

      def short_sha?(candidate)
        Kettle::Gha::Pins.short_sha?(candidate)
      end

      def non_sha?(candidate)
        Kettle::Gha::Pins.non_sha?(candidate)
      end

      def stale_sha?(current, latest)
        Kettle::Gha::Pins.stale_sha?(current, latest)
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
        match = suffix.match(VERSION_COMMENT_SUFFIX_RE)
        match && match[:version]
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
          comment = suffix.match(VERSION_COMMENT_REPLACEMENT_RE)
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
        if @options[:check] && state[:planned_changes].any?
          lines << ""
          lines << "Recommended fix: kettle-gha-sha-pins --write --upgrade #{@options[:upgrade]}"
        end

        puts lines.join("
")
      end
    end
  end
end
