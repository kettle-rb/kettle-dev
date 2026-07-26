# frozen_string_literal: true

RSpec.describe Kettle::Dev::InteractiveReleaseCommand do
  it "waits for the MFA response prompt before writing an OTP" do
    provider = instance_double(Kettle::Dev::ReleaseSecrets::OnePassword, rubygems_otp: "123456")
    output = StringIO.new
    command = described_class.new(secrets_provider: provider, output: output)
    input = StringIO.new

    command.send(:handle_prompt, input, "You have enabled multi-factor authentication.\n")
    expect(input.string).to eq("")

    command.send(:handle_prompt, input, "Code: ")
    expect(input.string).to eq("123456\n")
    expect(output.string).to include("RubyGems MFA code loaded from configured secrets provider.")
  end

  it "memoizes the gem signing passphrase for repeated PEM prompts" do
    provider = instance_double(Kettle::Dev::ReleaseSecrets::OnePassword, gem_signing_passphrase: "secret")
    command = described_class.new(secrets_provider: provider, output: StringIO.new)
    input = StringIO.new

    command.send(:handle_prompt, input, "Enter PEM pass phrase: ")
    command.send(:handle_prompt, input, "Enter PEM pass phrase: ")

    expect(input.string).to eq("secret\nsecret\n")
    expect(provider).to have_received(:gem_signing_passphrase).once
  end
end
