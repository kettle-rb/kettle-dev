# frozen_string_literal: true

require "set"
require "shellwords"
require "fileutils"
require "bundler"

require_relative "bundler_env_guard"

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
      UNBUNDLED_ENV_KEYS = (BundlerEnvGuard::RESET_ENV_KEYS + %w[
        RUBYLIB
        RUBYOPT
      ]).freeze

      def initialize(root:, command_runner:)
        @root = root
        @command_runner = command_runner
      end

      def reset(target)
        BundlerEnvGuard.warn_unexpected_env!
        paths = lockfile_paths_for(target)
        force_full_update = release_lockfiles_target?(target)
        uninstall_unreleased_local_gems(paths) if force_full_update
        paths.each do |path|
          reset_lockfile!(path, full_update: force_full_update) if force_full_update || normalization_needed?(path)
        end
        if force_full_update && uninstall_unreleased_local_gems(paths)
          paths.each do |path|
            reset_lockfile!(path, full_update: true)
          end
        end
        diagnostics = paths.flat_map { |path| diagnostics(path) }
        raise Error, validation_message(target, diagnostics) unless diagnostics.empty?

        paths
      end

      def reset_lockfile!(path, full_update: false)
        gemfile = gemfile_for_lockfile(path)
        unless gemfile && File.file?(gemfile)
          warn("Cannot reset #{display_path(path)} because its Gemfile was not found.")
          return
        end

        command = reset_command(path: path, gemfile: gemfile, full_update: full_update)
        if full_update || has_local_path_remote?(path)
          rebuild_lockfile(path) { command_runner.call(command) }
        else
          command_runner.call(command)
        end
      end

      def reset_command(path:, gemfile:, full_update: false)
        update_gems = (full_update || has_local_path_remote?(path)) ? [] : reset_update_gems(path)
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
        reset_platforms(path).each do |platform|
          command << " --add-platform=#{Shellwords.escape(platform)}"
        end
        command << " --update"
        command << " #{update_gems.map { |gem_name| Shellwords.escape(gem_name) }.join(" ")}" unless update_gems.empty?
        command << " --add-checksums"
        command
      end

      def reset_platforms(path)
        (lockfile_platforms(path) | [Gem::Platform.local.to_s]).reject(&:empty?).sort
      end

      def lockfile_platforms(path)
        in_platforms = false
        File.readlines(path).filter_map do |line|
          stripped = line.strip
          if stripped.match?(/\A[A-Z][A-Z ]*\z/)
            in_platforms = stripped == "PLATFORMS"
            next
          end
          next unless in_platforms
          next if stripped.empty?

          stripped
        end
      end

      def reset_update_gems(path)
        (
          path_source_gems(path).to_a |
          path_dependency_gems(path).to_a |
          empty_registry_checksums(path).map(&:first) |
          unreleased_workspace_registry_specs(path).map(&:first)
        ).uniq.sort
      end

      def normalization_needed?(path)
        has_local_path_remote?(path) || !empty_registry_checksums(path).empty? || !unreleased_workspace_registry_specs(path).empty?
      end

      def diagnostics(path)
        diagnostics = []
        local_path_remote_lines(path).each do |line_number|
          diagnostics << "#{display_path(path)} has local path remote at line #{line_number}"
        end
        empty_registry_checksums(path).each do |name, version, line_number|
          diagnostics << "#{display_path(path)} CHECKSUMS has no sha256 for #{name} #{version} at line #{line_number}"
        end
        unreleased_workspace_registry_specs(path).each do |name, version, line_number|
          diagnostics << "#{display_path(path)} locks local workspace gem #{name} #{version} as a registry gem, but that version is not resolvable from the configured gem source at line #{line_number}"
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
        if release_lockfiles_target?(normalized)
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

      def release_lockfiles_target?(target)
        target.to_s.strip.casecmp(RELEASE_LOCKFILES_TARGET).zero?
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
        in_path = false
        File.readlines(path).filter_map.with_index(1) do |line, index|
          stripped = line.strip
          if stripped.match?(/\A[A-Z][A-Z ]*\z/)
            in_path = stripped == "PATH"
            next
          end
          next unless in_path
          next unless stripped.start_with?("remote:")
          next if stripped == "remote: ."
          next unless stripped.start_with?("remote: /", "remote: ./", "remote: ../")

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

      def unreleased_workspace_registry_specs(path)
        local_names = local_workspace_gem_names
        return [] if local_names.empty?

        source_urls = registry_source_urls(path)
        registry_specs_with_lines(path).filter_map do |name, version, line_number|
          next unless local_names.include?(name)
          next if gem_source_version_available?(name, version, source_urls)

          [name, version, line_number]
        end
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
        lockfile_parser(path).specs.each_with_object(Set.new) do |spec, gems|
          source = spec.source
          gems << spec.name if path_source?(source) && !self_path_source?(source)
        end
      end

      def path_dependency_gems(path)
        lockfile_parser(path).dependencies.each_value.each_with_object(Set.new) do |dependency, gems|
          source = dependency.source
          gems << dependency.name if path_source?(source) && !self_path_source?(source)
        end
      end

      def self_path_source_gems(path)
        lockfile_parser(path).specs.each_with_object(Set.new) do |spec, gems|
          gems << spec.name if self_path_source?(spec.source)
        end
      end

      def display_path(path)
        Kettle::Dev.display_path(path)
      end

      private

      attr_reader :root, :command_runner

      def lockfile_parser(path)
        # Bundler validates checksum digest syntax while parsing, but this class
        # only needs Bundler's source model here. Keep checksum diagnostics in
        # the line scanner below so malformed or empty checksum entries can be
        # reported without breaking source classification.
        Bundler::LockfileParser.new(lockfile_source_content(path))
      end

      def lockfile_source_content(path)
        in_checksums = false
        File.readlines(path).filter_map do |line|
          stripped = line.strip
          if stripped == "CHECKSUMS"
            in_checksums = true
            next
          end
          if in_checksums && stripped.match?(/\A[A-Z][A-Z ]*\z/)
            in_checksums = false
          end
          next if in_checksums

          line
        end.join
      end

      def path_source?(source)
        source.instance_of?(::Bundler::Source::Path)
      end

      def self_path_source?(source)
        path_source?(source) && source.path.to_s == "."
      end

      def rebuild_lockfile(path)
        backup = backup_path_for(path)
        FileUtils.mkdir_p(File.dirname(backup))
        FileUtils.cp(path, backup)
        FileUtils.rm_f(path)
        yield
        FileUtils.mv(backup, path, force: true) unless File.file?(path)
        FileUtils.rm_f(backup)
      rescue
        FileUtils.mv(backup, path, force: true) if File.file?(backup)
        raise
      end

      def backup_path_for(path)
        backup_dir = File.join(root, "tmp", "kettle-reset")
        "#{File.join(backup_dir, File.basename(path))}.#{Process.pid}.bak"
      end

      def uninstall_unreleased_local_gems(paths)
        local_names = local_workspace_gem_names
        return false if local_names.empty?

        uninstalled = false
        locked_registry_specs(paths).each do |name, version|
          next unless local_names.include?(name)
          next unless locally_installed?(name, version)
          next if gem_source_version_available?(name, version, source_urls_for_lockfiles(paths))

          uninstall_unreleased_local_gem(name, version)
          uninstalled = true
        end
        uninstalled
      end

      def uninstall_unreleased_local_gem(name, version)
        command_runner.call(uninstall_command(name, version))
      rescue => error
        # Family release waves can ask several member processes to remove the same
        # unreleased sibling version. If another process won that race, the reset
        # goal is already satisfied; otherwise keep the original uninstall failure.
        raise error if locally_installed?(name, version)
      end

      def locked_registry_specs(paths)
        paths.flat_map { |path| registry_specs(path) }.uniq.sort
      end

      def registry_specs(path)
        registry_specs_with_lines(path).map { |name, version, _line_number| [name, version] }
      end

      def registry_specs_with_lines(path)
        specs = []
        in_gem = false
        in_specs = false
        File.readlines(path).each.with_index(1) do |line, line_number|
          stripped = line.chomp
          if stripped == "GEM"
            in_gem = true
            in_specs = false
            next
          end
          next unless in_gem
          break if !stripped.empty? && stripped == stripped.upcase && !stripped.start_with?(" ")

          if stripped == "  specs:"
            in_specs = true
            next
          end
          next unless in_specs

          match = stripped.match(/\A    ([A-Za-z0-9_.-]+) \(([^)]+)\)/)
          specs << [match[1], match[2], line_number] if match
        end
        specs
      end

      def locally_installed?(name, version)
        Gem::Specification.find_all_by_name(name, "= #{version}").any?
      rescue
        false
      end

      def gem_source_version_available?(name, version, source_urls)
        urls = Array(source_urls).compact.uniq
        return false if urls.empty?

        urls.any? { |source_url| bundler_inline_version_available?(name, version, source_url) }
      end

      def bundler_inline_version_available?(name, version, source_url)
        @gem_source_version_available ||= {}
        cache_key = [source_url, name, version]
        return @gem_source_version_available[cache_key] if @gem_source_version_available.key?(cache_key)

        @gem_source_version_available[cache_key] = GemSourceProbe.new(source_url: source_url).available?(name, version)
      end

      def source_urls_for_lockfiles(paths)
        paths.flat_map { |path| registry_source_urls(path) }.uniq
      end

      def registry_source_urls(path)
        urls = []
        in_gem = false
        File.readlines(path).each do |line|
          stripped = line.strip
          if stripped == "GEM"
            in_gem = true
            next
          end
          if stripped.match?(/\A[A-Z][A-Z ]*\z/)
            in_gem = stripped == "GEM"
            next
          end
          next unless in_gem && stripped.start_with?("remote:")

          urls << stripped.delete_prefix("remote:").strip
        end
        urls
      end

      def uninstall_command(name, version)
        command = +"env"
        UNBUNDLED_ENV_KEYS.each do |key|
          command << " -u #{key}"
        end
        command << " gem uninstall #{Shellwords.escape(name)} -v #{Shellwords.escape(version)} -x -I"
        command
      end

      def local_workspace_gem_names
        paths = dynamic_local_path_env.keys.filter_map do |key|
          value = ENV[key].to_s.strip
          value unless value.empty?
        end
        paths << File.expand_path("..", root)
        paths.each_with_object(Set.new) do |path, names|
          next unless File.directory?(path)

          workspace_children(path).each do |child|
            next unless directory?(child)

            Dir[File.join(child, "*.gemspec")].each do |gemspec|
              names << File.basename(gemspec, ".gemspec")
            end
          end
        end
      end

      def workspace_children(path)
        Dir.entries(path).reject { |child| child == "." || child == ".." }.map { |child| File.join(path, child) }
      rescue SystemCallError
        []
      end

      def directory?(path)
        File.stat(path).directory?
      rescue SystemCallError
        false
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
