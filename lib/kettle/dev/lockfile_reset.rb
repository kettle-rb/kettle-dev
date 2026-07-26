# frozen_string_literal: true

require "set"
require "shellwords"

module Kettle
  module Dev
    class LockfileReset
      DEFAULT_DISABLED_ENV = {
        "KETTLE_DEV_DEV" => "false",
        "K_JEM_TEMPLATING" => "false",
        "STRUCTUREDMERGE_DEV" => "false",
        "TREE_SITTER_LANGUAGE_PACK_DEV" => "false",
        "RUBOCOP_LTS_LOCAL" => "false",
        "GALTZO_FLOSS_DEV" => "false",
        "UR_BRAIN_DEV" => "false"
      }.freeze

      def initialize(root:, command_runner:)
        @root = root
        @command_runner = command_runner
      end

      def reset(target)
        path = lockfile_path_for(target)
        return path unless normalization_needed?(path)

        reset_lockfile!(path)
        diagnostics = diagnostics(path)
        raise Error, validation_message(target, diagnostics) unless diagnostics.empty?

        path
      end

      def reset_lockfile!(path)
        gemfile = gemfile_for_lockfile(path)
        unless gemfile && File.file?(gemfile)
          warn("Cannot reset #{display_path(path)} because its Gemfile was not found.")
          return
        end

        command_runner.call(reset_command(path: path, gemfile: gemfile))
      end

      def reset_command(path:, gemfile:)
        update_gems = reset_update_gems(path)
        env = normalization_env.merge(
          "BUNDLE_GEMFILE" => gemfile,
          "BUNDLE_LOCKFILE" => path
        )
        command = +"env"
        env.each do |key, value|
          command << " #{key}=#{Shellwords.escape(value)}"
        end
        command << " bundle lock"
        command << " --update"
        command << " #{update_gems.map { |gem_name| Shellwords.escape(gem_name) }.join(" ")}" unless update_gems.empty?
        command << " --add-checksums"
        command
      end

      def reset_update_gems(path)
        (
          path_source_gems(path).to_a |
          path_dependency_gems(path).to_a |
          empty_registry_checksums(path).map(&:first)
        ).uniq.sort
      end

      def normalization_needed?(path)
        has_local_path_remote?(path) || !empty_registry_checksums(path).empty?
      end

      def diagnostics(path)
        diagnostics = []
        local_path_remote_lines(path).each do |line_number|
          diagnostics << "#{display_path(path)} has local path remote at line #{line_number}"
        end
        empty_registry_checksums(path).each do |name, version, line_number|
          diagnostics << "#{display_path(path)} CHECKSUMS has no sha256 for #{name} #{version} at line #{line_number}"
        end
        diagnostics
      end

      def lockfile_paths
        candidates = [
          File.join(root, "Gemfile.lock"),
          File.join(root, "Appraisal.root.gemfile.lock")
        ]
        candidates.select { |path| File.file?(path) }.sort
      end

      def lockfile_path_for(target)
        normalized = target.to_s.strip
        raise Error, "reset requires TARGET" if normalized.empty?
        raise Error, "reset target #{normalized.inspect} is not supported; supported targets: Gemfile.lock" unless normalized.casecmp("Gemfile.lock").zero?

        File.join(root, "Gemfile.lock")
      end

      def gemfile_for_lockfile(path)
        basename = File.basename(path)
        return File.join(root, "Gemfile") if basename == "Gemfile.lock"

        path.delete_suffix(".lock")
      end

      def normalization_env
        DEFAULT_DISABLED_ENV.merge(dynamic_local_path_env)
      end

      def dynamic_local_path_env
        ENV.each_with_object({}) do |(key, value), env|
          next unless key.end_with?("_DEV", "_LOCAL")
          next unless local_path_env_value?(value)

          env[key] = "false"
        end
      end

      def local_path_env_value?(value)
        text = value.to_s.strip
        return false if text.empty? || text.casecmp("false").zero?
        return true if text.start_with?("/", "./", "../", "~")

        text.include?(File::SEPARATOR)
      end

      def has_local_path_remote?(path)
        !local_path_remote_lines(path).empty?
      end

      def local_path_remote_lines(path)
        File.readlines(path).filter_map.with_index(1) do |line, index|
          next unless line.start_with?("  remote: /", "  remote: .", "  remote: ./", "  remote: ../")

          index
        end
      end

      def empty_registry_checksums(path)
        path_gems = path_source_gems(path) | path_dependency_gems(path)
        in_checksums = false
        entries = File.readlines(path).filter_map.with_index(1) do |line, index|
          stripped = line.strip
          if stripped == "CHECKSUMS"
            in_checksums = true
            next
          end
          next unless in_checksums
          next if stripped.empty?
          next if stripped == "BUNDLED WITH"

          match = stripped.match(/\A([A-Za-z0-9_.-]+) \(([^)]+)\)(?:\s+(sha256=.*))?\z/)
          next unless match

          name = match[1]
          checksum = match[3].to_s
          next unless checksum.empty?
          next if path_gems.include?(name)

          [name, match[2], index]
        end
        return [] unless has_any_sha_checksum?(path)

        entries
      end

      def has_any_sha_checksum?(path)
        in_checksums = false
        File.readlines(path).any? do |line|
          stripped = line.strip
          if stripped == "CHECKSUMS"
            in_checksums = true
            next false
          end
          next false unless in_checksums

          stripped.include?("sha256=")
        end
      end

      def path_source_gems(path)
        gems = Set.new
        in_path = false
        in_specs = false
        File.readlines(path).each do |line|
          header = line.strip
          if header.match?(/\A[A-Z][A-Z ]*\z/)
            in_path = header == "PATH"
            in_specs = false
            next
          end
          next unless in_path

          if header == "specs:"
            in_specs = true
            next
          end
          next unless in_specs

          match = line.match(/\A    ([A-Za-z0-9_.-]+) \([^)]+\)/)
          gems << match[1] if match
        end
        gems
      end

      def path_dependency_gems(path)
        gems = Set.new
        in_dependencies = false
        File.readlines(path).each do |line|
          header = line.strip
          if header.match?(/\A[A-Z][A-Z ]*\z/)
            in_dependencies = header == "DEPENDENCIES"
            next
          end
          next unless in_dependencies

          match = line.match(/\A  ([A-Za-z0-9_.-]+)!\z/)
          gems << match[1] if match
        end
        gems
      end

      def display_path(path)
        Kettle::Dev.display_path(path)
      end

      private

      attr_reader :root, :command_runner

      def validation_message(target, diagnostics)
        <<~MSG
          Reset #{target} failed validation:
          #{diagnostics.map { |diagnostic| "  - #{diagnostic}" }.join("\n")}
        MSG
      end
    end
  end
end
