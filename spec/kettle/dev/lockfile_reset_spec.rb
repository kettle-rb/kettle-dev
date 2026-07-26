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

    expect(command).to include("env -u BUNDLE_BIN_PATH")
    expect(command).to include("-u RUBYOPT")
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
        remote: ../demo
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

  it "allows the current gemspec path while targeting sibling paths" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      PATH
        remote: .
        specs:
          kettle-dev (2.5.0)

      PATH
        remote: ../kettle-test
        specs:
          kettle-test (2.0.16)

      GEM
        remote: https://gem.coop/
        specs:
          rake (13.4.2)

      CHECKSUMS
        kettle-dev (2.5.0)
        kettle-test (2.0.16)
        rake (13.4.2) sha256=abc123

      DEPENDENCIES
        kettle-dev!
        kettle-test!
    LOCK

    path = File.join(@root, "Gemfile.lock")

    expect(reset.local_path_remote_lines(path)).to eq([7])
    expect(reset.reset_update_gems(path)).to eq(["kettle-test"])
    expect(reset.diagnostics(path)).to eq(["#{path} has local path remote at line 7"])
  end

  it "resets both release lockfiles" do
    commands = []
    reset = described_class.new(root: @root, command_runner: lambda { |command|
      commands << command
      if command.include?("Appraisal.root.gemfile.lock")
        File.write(File.join(@root, "Appraisal.root.gemfile.lock"), <<~LOCK)
          GEM
            remote: https://gem.coop/
            specs:
              thor (1.4.0)

          CHECKSUMS
            thor (1.4.0) sha256=abc123
        LOCK
      else
        File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
          GEM
            remote: https://gem.coop/
            specs:
              rake (13.4.2)

          CHECKSUMS
            rake (13.4.2) sha256=abc123
        LOCK
      end
    })
    File.write(File.join(@root, "Gemfile"), "source \"https://gem.coop\"\n")
    File.write(File.join(@root, "Appraisal.root.gemfile"), "source \"https://gem.coop\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://gem.coop/
        specs:
          rake (13.4.2)

      CHECKSUMS
        rake (13.4.2)
        thor (1.4.0) sha256=abc123
    LOCK
    File.write(File.join(@root, "Appraisal.root.gemfile.lock"), <<~LOCK)
      GEM
        remote: https://gem.coop/
        specs:
          thor (1.4.0)

      CHECKSUMS
        rake (13.4.2) sha256=abc123
        thor (1.4.0)
    LOCK

    reset.reset("release-lockfiles")

    expect(commands.length).to eq(2)
    expect(commands.first).to include("BUNDLE_LOCKFILE=#{File.join(@root, "Appraisal.root.gemfile.lock")}")
    expect(commands.last).to include("BUNDLE_LOCKFILE=#{File.join(@root, "Gemfile.lock")}")
  end
end
