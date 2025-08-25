# frozen_string_literal: true

# External RSpec & related config
require "kettle/test/rspec"

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

# Internal RSpec & related config
require_relative "support/shared_contexts/with_rake"

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

  config.after(:suite) do
    # Always restore the real STDIN at the end of the suite, even if $original_stdin was overwritten
    $stdin = ((defined?($original_stdin) && $original_stdin) ? $original_stdin : STDIN)
    $original_stdin = nil
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  # Use an absolute path to avoid issues when specs change CWD during the run
  begin
    root = Kettle::Dev::TemplateHelpers.project_root
  rescue StandardError
    root = Dir.pwd
  end
  config.example_status_persistence_file_path = File.join(root.to_s, ".rspec_status")
end
