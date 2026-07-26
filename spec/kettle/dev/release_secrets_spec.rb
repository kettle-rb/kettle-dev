# frozen_string_literal: true

RSpec.describe Kettle::Dev::ReleaseSecrets do
  it "builds an interactive provider by default" do
    provider = described_class::Factory.build

    expect(provider.gem_signing_passphrase).to be_nil
    expect(provider.rubygems_otp).to be_nil
  end

  it "loads the gem signing passphrase from 1Password defaults" do
    allow(Open3).to receive(:capture3)
      .with("op", "item", "get", "Rubygems", "--fields", "label=GEM-SIGN-PASSPHRASE", "--reveal")
      .and_return(["secret\n", "", status(success: true)])

    provider = described_class::Factory.build(provider_name: "1password")

    expect(provider.gem_signing_passphrase).to eq("secret")
  end

  it "loads RubyGems OTP values close to prompt time" do
    allow(Open3).to receive(:capture3)
      .with("op", "item", "get", "Rubygems", "--otp")
      .and_return(["123456\n", "", status(success: true)])

    provider = described_class::Factory.build(provider_name: "op")

    expect(provider.rubygems_otp).to eq("123456")
  end

  it "supports explicit 1Password references and accounts" do
    allow(Open3).to receive(:capture3)
      .with("op", "read", "op://Private/Rubygems/GEM-SIGN-PASSPHRASE", "--account", "work")
      .and_return(["secret\n", "", status(success: true)])

    provider = described_class::Factory.build(
      provider_name: "onepassword",
      config: {
        "account" => "work",
        "gem_signing_passphrase_reference" => "op://Private/Rubygems/GEM-SIGN-PASSPHRASE"
      }
    )

    expect(provider.gem_signing_passphrase).to eq("secret")
  end

  it "uses a cached family passphrase without querying 1Password for it" do
    stub_env(
      "KETTLE_RELEASE_GEM_SIGNING_PASSPHRASE_SOURCE" => "cached",
      "KETTLE_RELEASE_GEM_SIGNING_PASSPHRASE" => "cached-secret"
    )

    provider = described_class::Factory.build(provider_name: "1password")

    expect(Open3).not_to receive(:capture3)
    expect(provider.gem_signing_passphrase).to eq("cached-secret")
  end

  it "redacts lookup failures" do
    allow(Open3).to receive(:capture3)
      .and_return(["", "item not found\n", status(success: false, exitstatus: 1)])

    provider = described_class::Factory.build(provider_name: "1password")

    expect { provider.gem_signing_passphrase }
      .to raise_error(Kettle::Dev::Error, /1Password gem signing passphrase field lookup failed: item not found/)
  end

  def status(success:, exitstatus: success ? 0 : 1)
    instance_double(Process::Status, success?: success, exitstatus: exitstatus)
  end
end
