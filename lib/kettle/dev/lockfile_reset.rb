# frozen_string_literal: true

require "set"
require "shellwords"
require "fileutils"

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
      RELEASE_LOCKFILES_TARGET = "release-lockfiles"
      SUPPORTED_TARGETS = ["Gemfile.lock", "Appraisal.root.gemfile.lock", RELEASE_LOCKFILES_TARGET].freeze
      UNBUNDLED_ENV_KEYS = %w[
        BUNDLE_BIN_PATH
        BUNDLE_FROZEN
        BUNDLER_VERSION
        RUBYOPT
      ].freeze

      def initialize(root:, command_runner:)
        @root = root
        @command_runner = command_runner
      end

      def reset(target)
        paths = lockfile_paths_for(target)
        paths.each do |path|
          reset_lockfile!(path) if normalization_needed?(path)
        end
        diagnostics = paths.flat_map { |path| diagnostics(path) }
        raise Error, validation_message(target, diagnostics) unless diagnostics.empty?

        paths
      end

      def reset_lockfile!(path)
        gemfile = gemfile_for_lockfile(path)
        unless gemfile && File.file?(gemfile)
          warn("Cannot reset #{display_path(path)} because its Gemfile was not found.")
          return
        end

        command = reset_command(path: path, gemfile: gemfile)
        if has_local_path_remote?(path)
          rebuild_lockfile(path) { command_runner.call(command) }
        else
          command_runner.call(command)
        end
      end

      def reset_command(path:, gemfile:)
        update_gems = reset_update_gems(path)
        env = normalization_env.merge(
          "BUNDLE_GEMFILE" => gemfile,
          "BUNDLE_LOCKFILE" => path
        )
        command = +"env"
        UNBUNDLED_ENV_KEYS.each do |key|
          command << " -u #{key}"
        end
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
        paths = lockfile_paths_for(target)
        raise Error, "reset target #{target.inspect} resolves to multiple lockfiles; use lockfile_paths_for" if paths.length != 1

        paths.first
      end

      def lockfile_paths_for(target)
        normalized = target.to_s.strip
        raise Error, "reset requires TARGET" if normalized.empty?
        if normalized.casecmp(RELEASE_LOCKFILES_TARGET).zero?
          paths = lockfile_paths
          raise Error, "no release lockfiles found" if paths.empty?

          return paths
        end
        supported = SUPPORTED_TARGETS.reject { |candidate| candidate == RELEASE_LOCKFILES_TARGET }
        match = supported.find { |candidate| candidate.casecmp(normalized).zero? }
        unless match
          raise Error, "reset target #{normalized.inspect} is not supported; supported targets: #{SUPPORTED_TARGETS.join(", ")}"
        end

        [File.join(root, match)]
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
          next if line == "  remote: .\n"
          next unless line.start_with?("  remote: /", "  remote: .", "  remote: ./", "  remote: ../")

          index
        end
      end

      def empty_registry_checksums(path)
        path_gems = path_source_gems(path) | path_dependency_gems(path) | self_path_source_gems(path)
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
        current_path_is_self = false
        File.readlines(path).each do |line|
          header = line.strip
          if header.match?(/\A[A-Z][A-Z ]*\z/)
            in_path = header == "PATH"
            in_specs = false
            current_path_is_self = false
            next
          end
          next unless in_path

          if header.start_with?("remote:")
            current_path_is_self = header == "remote: ."
            next
          end
          if header == "specs:"
            in_specs = true
            next
          end
          next unless in_specs
          next if current_path_is_self

          match = line.match(/\A    ([A-Za-z0-9_.-]+) \([^)]+\)/)
          gems << match[1] if match
        end
        gems
      end

      def path_dependency_gems(path)
        self_gems = self_path_source_gems(path)
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
          gems << match[1] if match && !self_gems.include?(match[1])
        end
        gems
      end

      def self_path_source_gems(path)
        gems = Set.new
        in_path = false
        in_specs = false
        current_path_is_self = false
        File.readlines(path).each do |line|
          header = line.strip
          if header.match?(/\A[A-Z][A-Z ]*\z/)
            in_path = header == "PATH"
            in_specs = false
            current_path_is_self = false
            next
          end
          next unless in_path

          if header.start_with?("remote:")
            current_path_is_self = header == "remote: ."
            next
          end
          if header == "specs:"
            in_specs = true
            next
          end
          next unless in_specs && current_path_is_self

          match = line.match(/\A    ([A-Za-z0-9_.-]+) \([^)]+\)/)
          gems << match[1] if match
        end
        gems
      end

      def display_path(path)
        Kettle::Dev.display_path(path)
      end

      private

      attr_reader :root, :command_runner

      def rebuild_lockfile(path)
        backup = backup_path_for(path)
        FileUtils.mkdir_p(File.dirname(backup))
        FileUtils.cp(path, backup)
        FileUtils.rm_f(path)
        yield
        FileUtils.rm_f(backup)
      rescue
        FileUtils.mv(backup, path, force: true) if File.file?(backup)
        raise
      end

      def backup_path_for(path)
        backup_dir = File.join(root, "tmp", "kettle-reset")
        "#{File.join(backup_dir, File.basename(path))}.#{Process.pid}.bak"
      end

      def validation_message(target, diagnostics)
        <<~MSG
          Reset #{target} failed validation:
          #{diagnostics.map { |diagnostic| "  - #{diagnostic}" }.join("\n")}
        MSG
      end
    end
  end
end
