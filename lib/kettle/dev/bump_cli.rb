# frozen_string_literal: true

require "optparse"

module Kettle
  module Dev
    # CLI for bumping the current project's gem version before changelog prep.
    class BumpCLI
      def initialize(argv = [], out: $stdout, err: $stderr, root: Kettle::Dev::CIHelpers.project_root)
        @argv = argv.dup
        @out = out
        @err = err
        @root = root
      end

      def run!
        options = parse_options
        return 0 if options.fetch(:help)

        bump = Kettle::Dev::VersionBump.new(
          root: root,
          target_version: options.fetch(:target),
          from_version: options[:from]
        )
        edits = bump.edits
        Kettle::Dev::VersionBump.write_edits(edits) if options.fetch(:mode) == :execute

        out.puts(summary(edits: edits, current_version: bump.current_version, target_version: bump.target_version, mode: options.fetch(:mode)))
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

      def validate_version(version)
        Kettle::Dev::VersionBump.validate_version(version)
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
