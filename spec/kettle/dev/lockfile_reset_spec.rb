# frozen_string_literal: true

require "tmpdir"

RSpec.describe Kettle::Dev::LockfileReset do
  around do |example|
    Dir.mktmpdir("kettle-dev-lockfile-reset-spec") do |dir|
      @root = dir
      example.run
    end
  end

  it "updates path gems and checksum-gap registry gems with local path env disabled" do
    commands = []
    reset = described_class.new(root: @root, command_runner: ->(command) { commands << command })
    File.write(File.join(@root, "Gemfile"), "source \"https://gem.coop\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      PATH
        remote: /workspace/family/demo
        specs:
          demo (0.1.0)

      GEM
        remote: https://gem.coop/
        specs:
          kettle-soup-cover (3.0.5)

      CHECKSUMS
        demo (0.1.0)
        kettle-soup-cover (3.0.5)
        rake (13.4.2) sha256=abc123

      DEPENDENCIES
        demo!
        kettle-soup-cover
    LOCK

    command = reset.reset_command(path: File.join(@root, "Gemfile.lock"), gemfile: File.join(@root, "Gemfile"))

    expect(command).to include("KETTLE_DEV_DEV=false")
    expect(command).to include("K_JEM_TEMPLATING=false")
    expect(command).to include("BUNDLE_GEMFILE=#{File.join(@root, "Gemfile")}")
    expect(command).to include("BUNDLE_LOCKFILE=#{File.join(@root, "Gemfile.lock")}")
    expect(command).to include("bundle lock --update demo kettle-soup-cover --add-checksums")
    expect(commands).to be_empty
  end

  it "detects invalid lockfiles after reset" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      PATH
        remote: .
        specs:
          demo (0.1.0)

      GEM
        remote: https://gem.coop/
        specs:
          rake (13.4.2)

      CHECKSUMS
        rake (13.4.2)
        thor (1.4.0) sha256=abc123
    LOCK

    diagnostics = reset.diagnostics(File.join(@root, "Gemfile.lock"))

    expect(diagnostics.join("\n")).to include("has local path remote")
    expect(diagnostics.join("\n")).to include("CHECKSUMS has no sha256 for rake 13.4.2")
  end
end
