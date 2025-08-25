# frozen_string_literal: true

# External gems
# It's not reasonable to test this ENV variable
# :nocov:
require "require_bench" if ENV.fetch("REQUIRE_BENCH", "false").casecmp("true").zero?
# :nocov:
require "version_gem"

# This gem
require_relative "dev/version"
require_relative "emoji_regex"

module Kettle
  module Dev
    # Base error type for kettle-dev.
    class Error < StandardError; end

    # Whether debug logging is enabled for kettle-dev internals.
    # @return [Boolean]
    DEBUGGING = ENV.fetch("DEBUG", "false").casecmp("true").zero?
    # Whether we are running on CI.
    # @return [Boolean]
    IS_CI = ENV.fetch("CI", "false").casecmp("true") == 0
    # Whether to benchmark requires with require_bench.
    # @return [Boolean]
    REQUIRE_BENCH = ENV.fetch("REQUIRE_BENCH", "false").casecmp("true").zero?
    # Whether to load rake tasks at the bottom of this file.
    # Normally they would be loaded in the project's Rakefile,
    #   but if we do that in this project then we can't get accurate code coverage.
    # @return [Boolean]
    RUNNING_AS = File.basename($PROGRAM_NAME)

    @defaults = []

    class << self
      # Install Rake tasks useful for development and tests.
      #
      # Adds RuboCop-LTS tasks, coverage tasks, and loads the
      # gem-shipped rakelib directory so host projects get tasks from this gem.
      # @return [void]
      def install_tasks
        linting_tasks
        coverage_tasks
        load("kettle/dev/tasks.rb")
      end

      # Registry for tasks that should be prerequisites of the default task
      # @return [Array<String>]
      attr_reader :defaults

      # Register a task name to be run by the default task.
      # Also enhances the :default task immediately if it exists.
      # @param task_name [String, Symbol]
      # @return [Array<String>] the updated defaults registry
      def register_default(task_name)
        task_name = task_name.to_s
        unless defaults.include?(task_name)
          defaults << task_name
          if defined?(Rake) && Rake::Task.task_defined?(:default)
            begin
              Rake::Task[:default].enhance([task_name])
            rescue StandardError => e
              Kernel.warn("kettle-dev: failed to enhance :default with #{task_name}: #{e.message}") if DEBUGGING
            end
          end
        end
        defaults
      end

      private

      ### LINTING TASKS
      # Set up rubocop-lts, which cascades to rubocop-rubyX_X => rubocop_gradual)
      # @return [void]
      def linting_tasks
        begin
          # Lazy loaded because it won't be installed for Ruby < 2.7
          require "rubocop/lts"

          Rubocop::Lts.install_tasks
          if Kettle::Dev::IS_CI
            Kettle::Dev.register_default("rubocop_gradual:check")
          else
            Kettle::Dev.register_default("rubocop_gradual:autocorrect")
          end
        rescue LoadError
          # OK, no styles for you.
        end
      end

      ### TEST COVERAGE TASKS
      # Set up kettle-soup-cover
      # @return [void]
      def coverage_tasks
        begin
          # Lazy loaded because it won't be installed for Ruby < 2.7
          require "kettle-soup-cover"

          Kettle::Soup::Cover.install_tasks
          # NOTE: Coverage on CI is configured independent of this task.
          #       This task is for local development, as it opens results in browser
          # :nocov:
          Kettle::Dev.register_default("coverage") unless Kettle::Dev::IS_CI
          # :nocov:
        rescue LoadError
          # OK, no soup for you.
        end
      end
    end
  end
end

Kettle::Dev::Version.class_eval do
  extend VersionGem::Basic
end

# Eagerly load public CLI/APIs so requiring "kettle-dev" exposes them
# for tests and executables
require_relative "dev/tasks/template_task"
require_relative "dev/tasks/install_task"
require_relative "dev/tasks/ci_task"
require_relative "dev/git_commit_footer"
require_relative "dev/readme_backers"
require_relative "dev/release_cli"
require_relative "dev/template_helpers"

Kettle::Dev.install_tasks if Kettle::Dev::RUNNING_AS == "rake"
