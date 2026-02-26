# frozen_string_literal: true

# External gems

# It's not reasonable to test this ENV variable
# :nocov:
require "require_bench" if ENV.fetch("REQUIRE_BENCH", "false").casecmp("true").zero?
# :nocov:

# Autoload public CLI/APIs so requiring "kettle-dev" exposes them lazily
# for tests and executables. Files will be loaded on first constant access.
module Kettle
  autoload :EmojiRegex, "kettle/emoji_regex"
  module Dev
    autoload :ChangelogCLI, "kettle/dev/changelog_cli"
    autoload :CIHelpers, "kettle/dev/ci_helpers"
    autoload :CIMonitor, "kettle/dev/ci_monitor"
    autoload :CommitMsg, "kettle/dev/commit_msg"
    autoload :DvcsCLI, "kettle/dev/dvcs_cli"
    autoload :ExitAdapter, "kettle/dev/exit_adapter"
    autoload :GemSpecReader, "kettle/dev/gem_spec_reader"
    autoload :GitAdapter, "kettle/dev/git_adapter"
    autoload :GitCommitFooter, "kettle/dev/git_commit_footer"
    autoload :InputAdapter, "kettle/dev/input_adapter"
    autoload :ReadmeBackers, "kettle/dev/readme_backers"
    autoload :OpenCollectiveConfig, "kettle/dev/open_collective_config"
    autoload :ReleaseCLI, "kettle/dev/release_cli"
    autoload :PreReleaseCLI, "kettle/dev/pre_release_cli"
    autoload :Version, "kettle/dev/version"
    autoload :Versioning, "kettle/dev/versioning"

    # Nested tasks namespace with autoloaded task modules
    module Tasks
      autoload :CITask, "kettle/dev/tasks/ci_task"
    end

    # Base error type for kettle-dev.
    class Error < StandardError; end

    # Whether debug logging is enabled for kettle-dev internals.
    # KETTLE_DEV_DEBUG overrides DEBUG.
    # @return [Boolean]
    DEBUGGING = ENV.fetch("KETTLE_DEV_DEBUG", ENV.fetch("DEBUG", "false")).casecmp("true").zero?
    # Whether we are running on CI.
    # @return [Boolean]
    IS_CI = ENV.fetch("CI", "false").casecmp("true") == 0
    # Whether to benchmark requires with require_bench.
    # @return [Boolean]
    REQUIRE_BENCH = ENV.fetch("REQUIRE_BENCH", "false").casecmp("true").zero?
    # The current program name (e.g., "rake", "rspec").
    # Used to decide whether to auto-load rake tasks at the bottom of this file.
    # Normally tasks are loaded in the host project's Rakefile, but when running
    # under this gem's own test suite we need precise coverage; so we only
    # auto-install tasks when invoked via the rake executable.
    # @return [String]
    RUNNING_AS = File.basename($PROGRAM_NAME)
    # A case-insensitive regular expression that matches common truthy ENV values.
    # Accepts 1, true, y, yes (any case).
    # @return [Regexp]
    ENV_TRUE_RE = /\A(1|true|y|yes)\z/i

    # A case-insensitive regular expression that matches common falsy ENV values.
    # Accepts false, n, no, 0 (any case).
    # @return [Regexp]
    ENV_FALSE_RE = /\A(false|n|no|0)\z/i
    # Absolute path to the root of the kettle-dev gem (repository root when working from source)
    # @return [String]
    GEM_ROOT = File.expand_path("../..", __dir__)

    @defaults = [].freeze

    class << self
      # Emit a debug warning for rescued errors when kettle-dev debugging is enabled.
      # Controlled by KETTLE_DEV_DEBUG=true (or DEBUG=true as fallback).
      # @param error [Exception]
      # @param context [String, Symbol, nil] optional label, often __method__
      # @return [void]
      def debug_error(error, context = nil)
        return unless DEBUGGING

        ctx = context ? context.to_s : "KETTLE-DEV-RESCUE"
        Kernel.warn("[#{ctx}] #{error.class}: #{error.message}")
        Kernel.warn(error.backtrace.first(5).join("\n")) if error.respond_to?(:backtrace) && error.backtrace
      rescue StandardError
        # never raise from debug logging
      end

      # Emit a debug log line when kettle-dev debugging is enabled.
      # Controlled by KETTLE_DEV_DEBUG=true (or DEBUG=true as fallback).
      # @param msg [String]
      # @return [void]
      def debug_log(msg, context = nil)
        return unless DEBUGGING

        ctx = context ? context.to_s : "KETTLE-DEV-DEBUG"
        Kernel.warn("[#{ctx}] #{msg}")
      rescue StandardError
        # never raise from debug logging
      end

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
          @defaults = (defaults + [task_name]).freeze # rubocop:disable ThreadSafety/ClassInstanceVariable
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

      def default_registered?(task_name)
        defaults.include?(task_name.to_s)
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

Kettle::Dev.install_tasks if Kettle::Dev::RUNNING_AS == "rake"
