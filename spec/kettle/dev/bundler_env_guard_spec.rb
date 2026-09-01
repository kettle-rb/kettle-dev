# frozen_string_literal: true

require "stringio"

RSpec.describe Kettle::Dev::BundlerEnvGuard do
  before do
    described_class.reset_warning_cache!
  end

  it "reports Bundler environment variables that are neither reset nor known inert" do
    stub_env_hash_accessors
    existing_bundler_env = ENV.to_hash.keys.grep(/\ABUNDLE(?:R)?_/)
    stub_env(existing_bundler_env.each_with_object({}) { |key, hash| hash[key] = nil })
    stub_env(
      "BUNDLE_GEMFILE" => "Gemfile",
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => "Gemfile",
      "BUNDLE_DISABLE_CHECKSUM_VALIDATION" => "true",
      "BUNDLE_SILENCE_DEPRECATIONS" => "true",
      "BUNDLER_DEBUG" => "true",
      "BUNDLE_NEW_SURPRISE" => "1",
      "BUNDLER_NEW_SURPRISE" => "1"
    )

    expect(described_class.unexpected_env_keys).to eq(%w[BUNDLER_NEW_SURPRISE BUNDLE_NEW_SURPRISE])
  end

  it "warns for unexpected Bundler environment variables" do
    stub_env_hash_accessors
    stub_env("BUNDLE_NEW_SURPRISE" => "1")
    stream = StringIO.new

    described_class.warn_unexpected_env!(stream: stream)

    expect(stream.string).to include("Unexpected Bundler environment variable")
    expect(stream.string).to include("BUNDLE_NEW_SURPRISE")
  end

  it "warns once for repeated unexpected Bundler environment snapshots" do
    stub_env_hash_accessors
    stub_env("BUNDLE_NEW_SURPRISE" => "1")
    stream = StringIO.new

    described_class.warn_unexpected_env!(stream: stream)
    described_class.warn_unexpected_env!(stream: stream)

    expect(stream.string.scan("Unexpected Bundler environment variable").size).to eq(1)
  end

  it "clears dynamic Bundler parent markers from child environments" do
    stub_env("BUNDLER_ORIG_BUNDLE_GEMFILE" => "parent/Gemfile")

    expect(described_class.unbundled_env).to include(
      "BUNDLE_GEMFILE" => nil,
      "BUNDLER_ORIG_BUNDLE_GEMFILE" => nil
    )
  end
end
