# frozen_string_literal: true

# External RSpec & related config
require "kettle/test/rspec"

# Internal ENV config
require_relative "config/debug"

# Config for development dependencies of this library
# i.e., not configured by this library
#
# Simplecov & related config (must run BEFORE any other requires)
# NOTE: Gemfiles for older rubies won't have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require "kettle-soup-cover"
  require "simplecov" if Kettle::Soup::Cover::DO_COV # `.simplecov` is run here!
rescue LoadError => error
  # check the error message and re-raise when unexpected
  raise error unless error.message.include?("kettle")
end

# this library
require "kettle-dev"
# Ensure GitAdapter constant is available for global stubbing
require "kettle/dev/git_adapter"
# Ensure ExitAdapter constant is available for potential stubbing
require "kettle/dev/exit_adapter"

# rspec-pending_for: enable skipping on incompatible Ruby versions
require "rspec/pending_for"
RSpec.configure do |config|
  config.include Rspec::PendingFor

  # Auto-skip examples that require Bundler >= 2.7 (which implies Ruby >= 3.2)
  config.before(:each, :bundler_27_only) do
    # Skip on Ruby < 3.2 using rspec-pending_for's version matcher
    pending_for(reason: "Requires Bundler >= 2.7 which is unavailable on Ruby < 3.2", ruby: Range.new(GemVersion.new("2.3"), GemVersion.new("3.2")), skip: true)
  end
end

# Internal RSpec & related config
require_relative "support/shared_contexts/with_rake"
# Include the global mocked git adapter context
require_relative "support/shared_contexts/with_mocked_git_adapter"
# Include the global mocked exit adapter context
require_relative "support/shared_contexts/with_mocked_exit_adapter"

# Global input machine to prevent blocking prompts during tests
# Many tasks/executables read from $stdin directly (e.g., $stdin.gets).
# Replace $stdin with a fake IO that returns an immediate answer.
class KettleTestInputMachine
  def initialize(default: nil)
    # default of nil => return "\n" to accept defaults like [Y/n] or [l]
    @default = default
  end

  def gets(*_args)
    (@default.nil? ? "\n" : @default.to_s) + ("\n" unless @default&.to_s&.end_with?("\n")).to_s
  end

  def readline(*_args)
    gets
  end

  def read(*_args)
    # Behave like non-interactive empty input
    ""
  end

  def each_line
    return enum_for(:each_line) unless block_given?
    # No lines by default
    nil
  end

  def tty?
    false
  end
end

RSpec.configure do |config|
  config.before(:suite) do
    $original_stdin = $stdin
    default = ENV["TEST_INPUT_DEFAULT"]
    $stdin = KettleTestInputMachine.new(default: ((default && !default.empty?) ? default : nil))
  end

  # Include mocked git adapter for all examples; it will skip when :real_git_adapter is set
  config.include_context "with mocked git adapter"

  # Include mocked exit adapter for all examples; it will skip when :real_exit_adapter is set
  config.include_context "with mocked exit adapter"

  config.after(:suite) do
    # Always restore the real STDIN at the end of the suite, even if $original_stdin was overwritten
    $stdin = ((defined?($original_stdin) && $original_stdin) ? $original_stdin : STDIN)
    $original_stdin = nil
  end
end
