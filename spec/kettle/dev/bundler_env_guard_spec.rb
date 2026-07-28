# frozen_string_literal: true

require "stringio"

RSpec.describe Kettle::Dev::BundlerEnvGuard do
  before do
    described_class.instance_variable_set(:@warned_unexpected_env_keys, nil)
  end

  it "reports Bundler environment variables that are neither reset nor known inert" do
    stub_env_hash_accessors
    stub_env(
      "BUNDLE_GEMFILE" => "Gemfile",
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => "Gemfile",
      "BUNDLE_SILENCE_DEPRECATIONS" => "true",
      "BUNDLE_NEW_SURPRISE" => "1",
      "BUNDLER_NEW_SURPRISE" => "1"
    )

    expect(described_class.unexpected_env_keys).to eq(%w[BUNDLER_NEW_SURPRISE BUNDLE_NEW_SURPRISE])
  end

  it "warns once for an unchanged unexpected Bundler environment set" do
    stub_env_hash_accessors
    stub_env("BUNDLE_NEW_SURPRISE" => "1")
    stream = StringIO.new

    described_class.warn_unexpected_env!(stream: stream)
    described_class.warn_unexpected_env!(stream: stream)

    expect(stream.string.scan("Unexpected Bundler environment variable").length).to eq(1)
    expect(stream.string).to include("BUNDLE_NEW_SURPRISE")
  end
end
