# frozen_string_literal: true

require_relative "version"

module Kettle
  module Dev
    module ExecutableVersion
      module_function

      def print_and_exit!(script_basename, argv, value_option: false)
        return unless requested?(argv, value_option: value_option)

        puts "#{script_basename} #{Kettle::Dev::Version::VERSION}"
        exit(0)
      end

      def print_header(script_basename, argv = ARGV)
        return unless consume_verbose!(argv)

        puts header(script_basename)
      end

      def header(script_basename)
        "== #{script_basename} v#{Kettle::Dev::Version::VERSION} =="
      end

      def verbose?(argv)
        argv.any? { |arg| arg == "--verbose" }
      end

      def consume_verbose!(argv)
        index = argv.index("--verbose")
        return false unless index

        argv.delete_at(index)
        true
      end

      def requested?(argv, value_option: false)
        argv.each_with_index.any? do |arg, index|
          arg == "-v" || bare_long_version?(argv, arg, index, value_option: value_option)
        end
      end

      def bare_long_version?(argv, arg, index, value_option:)
        return false unless arg == "--version"
        return true unless value_option

        index == argv.length - 1 || argv[index + 1].to_s.start_with?("-")
      end
    end
  end
end
