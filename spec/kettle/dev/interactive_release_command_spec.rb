# frozen_string_literal: true

require "shellwords"

RSpec.describe Kettle::Dev::InteractiveReleaseCommand do
  it "uses a PTY to write the configured passphrase to prompt-bearing commands" do
    provider = instance_double(Kettle::Dev::ReleaseSecrets::OnePassword, gem_signing_passphrase: "secret")
    output = StringIO.new
    command = described_class.new(secrets_provider: provider, output: output)
    skip "PTY is unavailable on this Ruby engine" unless command.send(:pty_available?)

    script = "print 'Enter PEM pass phrase:'; $stdout.flush; exit(STDIN.gets&.chomp == 'secret' ? 0 : 1)"
    _stdout, _stderr, status = command.call({}, [RbConfig.ruby, "-e", script].shelljoin)

    expect(status).to be_success
    expect(output.string).to include("Enter PEM pass phrase:")
    expect(output.string).to include("gem signing passphrase loaded from configured secrets provider.")
  end

  it "falls back to Open3 when PTY is unavailable" do
    provider = instance_double(Kettle::Dev::ReleaseSecrets::OnePassword, gem_signing_passphrase: "secret")
    output = StringIO.new
    command = described_class.new(secrets_provider: provider, output: output)
    allow(command).to receive(:pty_available?).and_return(false)
    script = "print 'Enter PEM pass phrase:'; $stdout.flush; exit(STDIN.gets&.chomp == 'secret' ? 0 : 1)"

    _stdout, _stderr, status = command.call({}, [RbConfig.ruby, "-e", script].shelljoin)

    expect(status).to be_success
    expect(output.string).to include("gem signing passphrase loaded from configured secrets provider.")
  end

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

  it "emits secret provider events around an MFA prompt response" do
    provider = instance_double(Kettle::Dev::ReleaseSecrets::OnePassword, rubygems_otp: "123456")
    events = []
    command = described_class.new(
      secrets_provider: provider,
      output: StringIO.new,
      secret_event_handler: ->(payload) { events << payload }
    )
    input = StringIO.new

    command.send(:handle_prompt, input, "Code: ")

    expect(input.string).to eq("123456\n")
    expect(events).to contain_exactly(
      include(source: "rubygems_otp", action: "prompt_response", status: "started", label: "RubyGems MFA code"),
      include(source: "rubygems_otp", action: "prompt_response", status: "ok", label: "RubyGems MFA code")
    )
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

  it "fails closed when a configured provider returns no secret for a prompt" do
    provider = instance_double(Kettle::Dev::ReleaseSecrets::OnePassword, gem_signing_passphrase: nil)
    command = described_class.new(secrets_provider: provider, output: StringIO.new)

    expect {
      command.send(:handle_prompt, StringIO.new, "Enter PEM pass phrase: ")
    }.to raise_error(Kettle::Dev::Error, /configured release secrets provider returned no value/)
  end
end
