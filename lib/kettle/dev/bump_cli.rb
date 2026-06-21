# frozen_string_literal: true

require "optparse"

module Kettle
  module Dev
    # CLI for bumping the current project's gem version before changelog prep.
    class BumpCLI
      BUMP_TYPES = %w[major minor patch pre].freeze

      def initialize(argv = [], out: $stdout, err: $stderr, root: Kettle::Dev::CIHelpers.project_root)
        @argv = argv.dup
        @out = out
        @err = err
        @root = root
      end

      def run!
        options = parse_options
        return 0 if options.fetch(:help)

        current_version = Kettle::Dev::Versioning.detect_version(root)
        target_version = resolve_target_version(options.fetch(:target), current_version)
        edits = collect_edits(
          current_version: current_version,
          target_version: target_version,
          from_version: options[:from]
        )
        write_edits(edits) if options.fetch(:mode) == :execute

        out.puts(summary(edits: edits, current_version: current_version, target_version: target_version, mode: options.fetch(:mode)))
        (options.fetch(:mode) == :check && edits.any?) ? 1 : 0
      end

      private

      attr_reader :argv, :out, :err, :root

      def parse_options
        options = {mode: :execute, help: false}
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: kettle-bump VERSION|major|minor|patch|pre [options]"
          opts.on("--from VERSION", "Require the current version before bumping") { |value| options[:from] = validate_version(value) }
          opts.on("--check", "Exit non-zero when the bump would change files") { options[:mode] = :check }
          opts.on("--dry-run", "Print planned changes without writing files") { options[:mode] = :dry_run }
          opts.on("--execute", "Write the bump to disk (default)") { options[:mode] = :execute }
          opts.on("-h", "--help", "Show this help") do
            out.puts(opts)
            options[:help] = true
          end
        end
        parser.parse!(argv)
        options[:target] = argv.shift
        raise Kettle::Dev::Error, "kettle-bump requires VERSION, major, minor, patch, or pre" unless options[:target] || options[:help]
        raise Kettle::Dev::Error, "unexpected arguments: #{argv.join(" ")}" unless argv.empty?

        options
      rescue OptionParser::ParseError => error
        raise Kettle::Dev::Error, error.message
      end

      def resolve_target_version(target, current_version)
        if BUMP_TYPES.include?(target)
          bumped_version(target, current_version)
        else
          validate_version(target)
        end
      end

      def bumped_version(type, current_version)
        return bumped_prerelease_version(current_version) if type == "pre"

        version = Gem::Version.new(current_version)
        segments = version.segments
        unless segments.all? { |segment| segment.is_a?(Integer) }
          raise Kettle::Dev::Error, "cannot #{type}-bump non-numeric version #{current_version.inspect}"
        end

        major, minor, patch = (segments + [0, 0, 0])[0, 3]
        case type
        when "major"
          "#{major + 1}.0.0"
        when "minor"
          "#{major}.#{minor + 1}.0"
        when "patch"
          "#{major}.#{minor}.#{patch + 1}"
        end
      end

      def bumped_prerelease_version(current_version)
        version = Gem::Version.new(current_version)
        segments = version.segments
        prerelease_index = segments.index { |segment| !segment.is_a?(Integer) }
        unless prerelease_index
          raise Kettle::Dev::Error, "cannot pre-bump version without prerelease segment #{current_version.inspect}"
        end

        release_core = segments[0...prerelease_index].join(".")
        prerelease_suffix = prerelease_suffix_for(current_version, release_core)
        "#{release_core}.#{prerelease_suffix.next}"
      end

      def prerelease_suffix_for(current_version, release_core)
        prefix = "#{release_core}."
        return string_tail(current_version, prefix.length) if current_version.start_with?(prefix)

        canonical_version = Gem::Version.new(current_version).to_s
        return string_tail(canonical_version, prefix.length) if canonical_version.start_with?(prefix)

        raise Kettle::Dev::Error, "cannot find prerelease segment in version #{current_version.inspect}"
      end

      def string_tail(value, offset)
        value[offset, value.length - offset]
      end

      def validate_version(version)
        Gem::Version.new(version).to_s
      rescue ArgumentError => error
        raise Kettle::Dev::Error, "invalid version #{version.inspect}: #{error.message}"
      end

      def collect_edits(current_version:, target_version:, from_version:)
        if from_version && current_version != from_version
          raise Kettle::Dev::Error, "current version is #{current_version}, not --from #{from_version}"
        end

        version_file_edits(target_version) + gemspec_version_edits(current_version, target_version)
      end

      def version_file_edits(target_version)
        Kettle::Dev::Versioning.version_file_candidates(root).filter_map do |path|
          source = File.read(path)
          node = version_string_node(source, path)
          current = node.unescaped
          next if current == target_version

          replacement = quote_like(node.location.slice, target_version)
          file_edit(path, source, node.location.start_offset, node.location.end_offset, replacement)
        end
      end

      def gemspec_version_edits(current_version, target_version)
        gemspec_path = gemspec_path_for_bump
        return [] unless gemspec_path

        source = File.read(gemspec_path)
        parse_result = parse_source(source, gemspec_path)
        each_node(parse_result.value).filter_map do |node|
          next unless node.is_a?(Prism::CallNode) && node.name == :version=

          version_node = node.arguments&.arguments&.first
          next unless version_node.is_a?(Prism::StringNode)
          next unless version_node.unescaped == current_version
          next if version_node.unescaped == target_version

          replacement = quote_like(version_node.location.slice, target_version)
          file_edit(gemspec_path, source, version_node.location.start_offset, version_node.location.end_offset, replacement)
        end
      end

      def gemspec_path_for_bump
        paths = Dir.glob(File.join(root, "*.gemspec")).sort
        return nil if paths.empty?
        raise Kettle::Dev::Error, "multiple gemspecs found; kettle-bump supports single gems only" if paths.length > 1

        paths.first
      end

      def version_string_node(source, path)
        parse_result = parse_source(source, path)
        constant = each_node(parse_result.value).find do |node|
          node.is_a?(Prism::ConstantWriteNode) && node.name == :VERSION && node.value.is_a?(Prism::StringNode)
        end
        raise Kettle::Dev::Error, "could not find string VERSION constant in #{path}" unless constant

        constant.value
      end

      def parse_source(source, path)
        require_prism
        parse_result = Prism.parse(source)
        raise Kettle::Dev::Error, "could not parse #{path}" unless parse_result.success?

        parse_result
      end

      def require_prism
        return if defined?(Prism)

        require "prism"
      rescue LoadError => error
        raise Kettle::Dev::Error, "kettle-bump requires Prism; install the prism gem or run on Ruby 3.3+ (#{error.message})"
      end

      def each_node(root)
        return enum_for(__method__, root) unless block_given?

        queue = [root]
        until queue.empty?
          node = queue.shift
          yield node
          queue.concat(node.child_nodes.compact) if node.respond_to?(:child_nodes)
        end
      end

      def file_edit(path, source, start_offset, end_offset, replacement)
        {path: path, source: source, start_offset: start_offset, end_offset: end_offset, replacement: replacement}
      end

      def quote_like(original, value)
        quote = original.start_with?("'") ? "'" : '"'
        "#{quote}#{value}#{quote}"
      end

      def write_edits(edits)
        edits.group_by { |edit| edit.fetch(:path) }.each_value do |file_edits|
          source = file_edits.first.fetch(:source)
          file_edits.sort_by { |edit| -edit.fetch(:start_offset) }.each do |edit|
            source[edit.fetch(:start_offset)...edit.fetch(:end_offset)] = edit.fetch(:replacement)
          end
          File.write(file_edits.first.fetch(:path), source)
        end
      end

      def summary(edits:, current_version:, target_version:, mode:)
        lines = ["kettle-bump: #{current_version} -> #{target_version}"]
        if edits.empty?
          lines << "No version changes needed."
        else
          verb = (mode == :execute) ? "updated" : "would update"
          edits.map { |edit| edit.fetch(:path) }.uniq.each { |path| lines << "#{verb} #{Kettle::Dev.display_path(path)}" }
        end
        lines.join("\n")
      end
    end
  end
end
