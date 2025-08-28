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
# Ensure InputAdapter constant is available for stubbing
require "kettle/dev/input_adapter"

# rspec-pending_for: enable skipping on incompatible Ruby versions
require "rspec/pending_for"
RSpec.configure do |config|
  config.include Rspec::PendingFor

  # Auto-skip examples that require Bundler >= 2.7 (which implies Ruby >= 3.2)
  config.before(:each, :bundler_27_only) do
    # Skip on Ruby < 3.2 using rspec-pending_for's version matcher
    pending_for(reason: "Requires Bundler >= 2.7 which is unavailable on Ruby < 3.2", ruby: Range.new(Gem::Version.new("2.3"), Gem::Version.new("3.2")), skip: true)
  end
end

# Internal RSpec & related config
require_relative "support/shared_contexts/with_rake"
# Include the global mocked git adapter context
require_relative "support/shared_contexts/with_mocked_git_adapter"
# Include the global mocked exit adapter context
require_relative "support/shared_contexts/with_mocked_exit_adapter"
# Include skip context for TruffleRuby 3.1..3.2 incompatibilities
require_relative "support/shared_contexts/with_truffleruby_skip_31_32"
# Include mocked input adapter for all examples; it will skip when :real_input_adapter is set
require_relative "support/shared_contexts/with_mocked_input_adapter"

# Legacy helper used by some specs; no longer globally assigned to $stdin.
# Specs that set $stdin = KettleTestInputMachine.new(default: ...) will be
# respected by the mocked input adapter context for defaults.
class KettleTestInputMachine
  def initialize(default: nil)
    @default = default
  end

  def gets(*_args)
    (@default.nil? ? "\n" : @default.to_s) + ("\n" unless @default&.to_s&.end_with?("\n")).to_s
  end

  def readline(*_args)
    gets
  end

  def read(*_args)
    ""
  end

  def each_line
    return enum_for(:each_line) unless block_given?
    nil
  end

  def tty?
    false
  end
end

RSpec.configure do |config|
  # Include mocked git adapter for all examples; it will skip when :real_git_adapter is set
  config.include_context "with mocked git adapter"

  # Include mocked exit adapter for all examples; it will skip when :real_exit_adapter is set
  config.include_context "with mocked exit adapter"

  config.include_context "with mocked input adapter"
end
