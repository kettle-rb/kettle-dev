# frozen_string_literal: true

module Kettle
  module Dev
    # Reusable engine behind kettle-bump.
    class VersionBump
      BUMP_TYPES = %w[major minor patch pre].freeze

      class << self
        def resolve_target_version(target, current_version)
          target = target.to_s
          if BUMP_TYPES.include?(target)
            bumped_version(target, current_version)
          else
            validate_version(target)
          end
        end

        def validate_version(version)
          Gem::Version.new(version).to_s
        rescue ArgumentError => error
          raise Kettle::Dev::Error, "invalid version #{version.inspect}: #{error.message}"
        end

        def bumped_version(type, current_version)
          return bumped_prerelease_version(current_version) if type == "pre"

          version = Gem::Version.new(current_version)
          segments = version.segments
          return released_patch_version(segments) if type == "patch" && segments.any? { |segment| !segment.is_a?(Integer) }

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

        def released_patch_version(segments)
          release_segments = segments.take_while { |segment| segment.is_a?(Integer) }
          major, minor, patch = (release_segments + [0, 0, 0])[0, 3]
          "#{major}.#{minor}.#{patch}"
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
              source = replace_byte_range(
                source,
                edit.fetch(:start_offset),
                edit.fetch(:end_offset),
                edit.fetch(:replacement)
              )
            end
            File.write(file_edits.first.fetch(:path), source)
          end
        end

        def replace_byte_range(source, start_offset, end_offset, replacement)
          before = source.byteslice(0, start_offset) || +""
          after = source.byteslice(end_offset, source.bytesize - end_offset) || +""
          "#{before}#{replacement}#{after}"
        end
      end

      def initialize(root:, target_version:, current_version: nil, from_version: nil)
        @root = root
        @current_version = current_version || Kettle::Dev::Versioning.detect_version(root)
        @target_version = self.class.resolve_target_version(target_version, @current_version)
        @from_version = self.class.validate_version(from_version) if from_version
      end

      attr_reader :root, :current_version, :target_version, :from_version

      def edits
        validate_from_version
        version_file_edits + gemspec_version_edits
      end

      def write!
        self.class.write_edits(edits)
      end

      private

      def validate_from_version
        return unless from_version && current_version != from_version

        raise Kettle::Dev::Error, "current version is #{current_version}, not --from #{from_version}"
      end

      def version_file_edits
        Kettle::Dev::Versioning.version_file_candidates(root).filter_map do |path|
          source = File.read(path)
          node = self.class.version_string_node(source, path)
          current = node.unescaped
          next if current == target_version

          replacement = self.class.quote_like(node.location.slice, target_version)
          self.class.file_edit(path, source, node.location.start_offset, node.location.end_offset, replacement)
        end
      end

      def gemspec_version_edits
        gemspec_path = gemspec_path_for_bump
        return [] unless gemspec_path

        source = File.read(gemspec_path)
        parse_result = self.class.parse_source(source, gemspec_path)
        self.class.each_node(parse_result.value).filter_map do |node|
          next unless node.is_a?(Prism::CallNode) && node.name == :version=

          version_node = node.arguments&.arguments&.first
          next unless version_node.is_a?(Prism::StringNode)
          next unless version_node.unescaped == current_version
          next if version_node.unescaped == target_version

          replacement = self.class.quote_like(version_node.location.slice, target_version)
          self.class.file_edit(gemspec_path, source, version_node.location.start_offset, version_node.location.end_offset, replacement)
        end
      end

      def gemspec_path_for_bump
        paths = Dir.glob(File.join(root, "*.gemspec")).sort
        return nil if paths.empty?
        raise Kettle::Dev::Error, "multiple gemspecs found; kettle-bump supports single gems only" if paths.length > 1

        paths.first
      end
    end
  end
end
