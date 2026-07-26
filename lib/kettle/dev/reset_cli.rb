# frozen_string_literal: true

require "optparse"

module Kettle
  module Dev
    class ResetCLI
      def initialize(argv = [], root: Kettle::Dev::CIHelpers.project_root)
        @argv = Array(argv).dup
        @root = root
        @check = false
      end

      def run!
        args = parse!
        target = args.first.to_s
        raise Error, "kettle-reset requires TARGET" if target.empty?
        raise Error, "unexpected argument(s): #{args.drop(1).join(" ")}" if args.length > 1

        if check
          validate(target)
        else
          paths = resetter.lockfile_paths_for(target)
          unless paths.any? { |path| resetter.normalization_needed?(path) }
            puts "#{target} is already reset."
            return 0
          end
          resetter.reset(target)
          puts "Reset #{target}."
        end
        0
      end

      private

      attr_reader :argv, :root, :check

      def parse!
        parser.parse!(argv)
      rescue OptionParser::ParseError => error
        raise Error, error.message
      end

      def parser
        OptionParser.new do |opts|
          opts.banner = "Usage: kettle-reset [--check] TARGET"
          opts.separator "Targets: Gemfile.lock, Appraisal.root.gemfile.lock, release-lockfiles"
          opts.on("--check", "Validate TARGET without changing it") { @check = true }
          opts.on("-h", "--help", "Show this help") do
            puts opts
            exit(0)
          end
        end
      end

      def validate(target)
        paths = resetter.lockfile_paths_for(target)
        diagnostics = paths.flat_map { |path| resetter.diagnostics(path) }
        raise Error, validation_message(target, diagnostics) unless diagnostics.empty?

        puts "#{target} is already reset."
      end

      def validation_message(target, diagnostics)
        <<~MSG
          #{target} is not reset:
          #{diagnostics.map { |diagnostic| "  - #{diagnostic}" }.join("\n")}
        MSG
      end

      def resetter
        @resetter ||= Kettle::Dev::LockfileReset.new(root: root, command_runner: method(:run_cmd!))
      end

      def run_cmd!(command)
        puts "$ #{command}"
        system(command) || raise(Error, "Command failed: #{command}")
      end
    end
  end
end
