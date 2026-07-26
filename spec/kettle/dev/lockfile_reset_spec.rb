# frozen_string_literal: true

require "tmpdir"

RSpec.describe Kettle::Dev::LockfileReset do
  around do |example|
    Dir.mktmpdir("kettle-dev-lockfile-reset-spec") do |dir|
      @root = dir
      example.run
    end
  end

  it "fully updates lockfiles with path gems using local path env disabled" do
    commands = []
    reset = described_class.new(root: @root, command_runner: ->(command) { commands << command })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      PATH
        remote: /workspace/family/demo
        specs:
          demo (0.1.0)

      GEM
        remote: https://rubygems.org/
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
    expect(command).to include("bundle lock --update --add-checksums")
    expect(command).not_to include("bundle lock --update demo")
    expect(commands).to be_empty
  end

  it "fully updates release lockfiles even when no diagnostics are present" do
    commands = []
    reset = described_class.new(root: @root, command_runner: lambda { |command|
      commands << command
      File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            kettle-test (2.0.15)

        CHECKSUMS
          kettle-test (2.0.15) sha256=abc123
      LOCK
    })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          kettle-test (2.0.16)

      CHECKSUMS
        kettle-test (2.0.16) sha256=localonly
    LOCK
    allow(reset).to receive(:locally_installed?).and_return(false)

    reset.reset("release-lockfiles")

    expect(commands.first).to include("bundle lock --update --add-checksums")
  end

  it "uninstalls locally installed workspace gem versions that are not released" do
    commands = []
    stub_env("KETTLE_DEV_DEV" => @root)
    reset = described_class.new(root: @root, command_runner: lambda { |command|
      commands << command
      File.write(File.join(@root, "Gemfile.lock"), <<~LOCK) if command.include?("bundle lock")
        GEM
          remote: https://rubygems.org/
          specs:
            kettle-test (2.0.15)

        CHECKSUMS
          kettle-test (2.0.15) sha256=abc123
      LOCK
    })
    FileUtils.mkdir_p(File.join(@root, "kettle-test"))
    File.write(File.join(@root, "kettle-test", "kettle-test.gemspec"), "Gem::Specification.new { |s| s.name = 'kettle-test' }\n")
    File.write(File.join(@root, "kettle-dev.gemspec"), "Gem::Specification.new { |s| s.name = 'kettle-dev' }\n")
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          kettle-test (2.0.16)

      CHECKSUMS
        kettle-test (2.0.16) sha256=localonly
    LOCK
    allow(reset).to receive_messages(
      local_workspace_gem_names: Set["kettle-test"],
      locally_installed?: false,
      ruby_gems_version_available?: false
    )
    allow(reset).to receive(:locally_installed?).with("kettle-test", "2.0.15").and_return(true)
    allow(reset).to receive(:ruby_gems_version_available?).with("kettle-test", "2.0.15").and_return(true)
    allow(reset).to receive(:locally_installed?).with("kettle-test", "2.0.16").and_return(true)
    allow(reset).to receive(:ruby_gems_version_available?).with("kettle-test", "2.0.16").and_return(false)

    reset.reset("release-lockfiles")

    expect(commands.first).to include("gem uninstall kettle-test -v 2.0.16 -x -I")
    expect(commands.last).to include("bundle lock --update --add-checksums")
  end

  it "reruns release lockfile reset when Bundler introduces a local-only workspace version" do
    commands = []
    bundle_resets = 0
    reset = described_class.new(root: @root, command_runner: lambda { |command|
      commands << command
      next unless command.include?("bundle lock")

      bundle_resets += 1
      version = (bundle_resets == 1) ? "2.0.16" : "2.0.15"
      checksum = (bundle_resets == 1) ? "localonly" : "released"
      File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            kettle-test (#{version})

        CHECKSUMS
          kettle-test (#{version}) sha256=#{checksum}
      LOCK
    })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          kettle-test (2.0.15)

      CHECKSUMS
        kettle-test (2.0.15) sha256=released
    LOCK
    allow(reset).to receive(:local_workspace_gem_names).and_return(Set["kettle-test"])
    allow(reset).to receive(:locally_installed?).with("kettle-test", "2.0.15").and_return(true)
    allow(reset).to receive(:locally_installed?).with("kettle-test", "2.0.16").and_return(true)
    allow(reset).to receive(:ruby_gems_version_available?).with("kettle-test", "2.0.15").and_return(true)
    allow(reset).to receive(:ruby_gems_version_available?).with("kettle-test", "2.0.16").and_return(false)

    reset.reset("release-lockfiles")

    expect(commands.map { |command| command.include?("bundle lock") }).to eq([true, false, true])
    expect(commands[1]).to include("gem uninstall kettle-test -v 2.0.16 -x -I")
    expect(File.read(File.join(@root, "Gemfile.lock"))).to include("kettle-test (2.0.15)")
  end

  it "continues when another release worker already removed the same local gem version" do
    reset = described_class.new(root: @root, command_runner: ->(_command) { raise "already removed" })
    allow(reset).to receive(:locally_installed?).with("kettle-test", "2.0.16").and_return(false)

    expect { reset.send(:uninstall_unreleased_local_gem, "kettle-test", "2.0.16") }.not_to raise_error
  end

  it "fails when uninstall fails and the local gem version is still installed" do
    reset = described_class.new(root: @root, command_runner: ->(_command) { raise "permission denied" })
    allow(reset).to receive(:locally_installed?).with("kettle-test", "2.0.16").and_return(true)

    expect { reset.send(:uninstall_unreleased_local_gem, "kettle-test", "2.0.16") }
      .to raise_error(RuntimeError, "permission denied")
  end

  it "does not uninstall local workspace gems when RubyGems.org availability cannot be verified" do
    commands = []
    reset = described_class.new(root: @root, command_runner: ->(command) { commands << command })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          kettle-test (2.0.16)

      CHECKSUMS
        kettle-test (2.0.16) sha256=localonly
    LOCK
    allow(reset).to receive(:local_workspace_gem_names).and_return(Set["kettle-test"])
    allow(reset).to receive(:locally_installed?).with("kettle-test", "2.0.16").and_return(true)
    allow(reset).to receive(:ruby_gems_versions).with("kettle-test").and_raise(Kettle::Dev::Error, "RubyGems.org unavailable")

    expect { reset.reset("release-lockfiles") }.to raise_error(Kettle::Dev::Error, /RubyGems.org unavailable/)
    expect(commands).to be_empty
  end

  it "targets checksum-gap registry gems when no path remotes are present" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          kettle-soup-cover (3.0.5)

      CHECKSUMS
        kettle-soup-cover (3.0.5)
        rake (13.4.2) sha256=abc123
    LOCK

    command = reset.reset_command(path: File.join(@root, "Gemfile.lock"), gemfile: File.join(@root, "Gemfile"))

    expect(command).to include("bundle lock --update kettle-soup-cover --add-checksums")
  end

  it "runs targeted checksum reset commands without rebuilding the lockfile" do
    commands = []
    reset = described_class.new(root: @root, command_runner: ->(command) { commands << command })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          kettle-soup-cover (3.0.5)

      CHECKSUMS
        kettle-soup-cover (3.0.5)
        rake (13.4.2) sha256=abc123
    LOCK
    allow(FileUtils).to receive(:rm_f).and_call_original

    reset.reset_lockfile!(File.join(@root, "Gemfile.lock"))

    expect(commands.length).to eq(1)
    expect(commands.first).to include("bundle lock --update kettle-soup-cover --add-checksums")
    expect(FileUtils).not_to have_received(:rm_f).with(File.join(@root, "Gemfile.lock"))
  end

  it "warns and skips reset when the matching Gemfile is missing" do
    commands = []
    reset = described_class.new(root: @root, command_runner: ->(command) { commands << command })
    path = File.join(@root, "Appraisal.root.gemfile.lock")
    File.write(path, "")

    expect { reset.reset_lockfile!(path) }.to output(/Cannot reset .*Appraisal\.root\.gemfile\.lock/).to_stderr
    expect(commands).to be_empty
  end

  it "rejects unsupported reset targets" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})

    expect { reset.lockfile_paths_for("Gemfile.lock.backup") }
      .to raise_error(Kettle::Dev::Error, /is not supported/)
  end

  it "rejects singular lookup for release lockfiles" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    File.write(File.join(@root, "Gemfile.lock"), "")
    File.write(File.join(@root, "Appraisal.root.gemfile.lock"), "")

    expect { reset.lockfile_path_for("release-lockfiles") }
      .to raise_error(Kettle::Dev::Error, /resolves to multiple lockfiles/)
  end

  it "detects path-valued local development env vars" do
    allow(ENV).to receive(:each).and_yield("ALPHA_DEV", "/workspace/alpha")
      .and_yield("BETA_LOCAL", "~/workspace/beta")
      .and_yield("GAMMA_DEV", "relative/workspace")
      .and_yield("DELTA_LOCAL", "false")
      .and_yield("EPSILON_DEV", "true")
    reset = described_class.new(root: @root, command_runner: ->(_command) {})

    expect(reset.normalization_env).to include(
      "ALPHA_DEV" => "false",
      "BETA_LOCAL" => "false",
      "GAMMA_DEV" => "false"
    )
    expect(reset.normalization_env).not_to include("DELTA_LOCAL", "EPSILON_DEV")
  end

  it "detects invalid lockfiles after reset" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      PATH
        remote: ../demo
        specs:
          demo (0.1.0)

      GEM
        remote: https://rubygems.org/
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
        remote: https://rubygems.org/
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
            remote: https://rubygems.org/
            specs:
              thor (1.4.0)

          CHECKSUMS
            thor (1.4.0) sha256=abc123
        LOCK
      else
        File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
          GEM
            remote: https://rubygems.org/
            specs:
              rake (13.4.2)

          CHECKSUMS
            rake (13.4.2) sha256=abc123
        LOCK
      end
    })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Appraisal.root.gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.4.2)

      CHECKSUMS
        rake (13.4.2)
        thor (1.4.0) sha256=abc123
    LOCK
    File.write(File.join(@root, "Appraisal.root.gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
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

  it "restores the original lockfile when a rebuild command fails" do
    reset = described_class.new(root: @root, command_runner: ->(_command) { raise "bundle failed" })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    path = File.join(@root, "Gemfile.lock")
    original = <<~LOCK
      PATH
        remote: ../demo
        specs:
          demo (0.1.0)
    LOCK
    File.write(path, original)

    expect { reset.reset_lockfile!(path, full_update: true) }.to raise_error(RuntimeError, "bundle failed")
    expect(File.read(path)).to eq(original)
  end

  it "matches RubyGems.org platform releases before uninstalling local gems" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    allow(reset).to receive(:ruby_gems_versions).with("native-demo").and_return(
      [{"number" => "1.2.3", "platform" => "x86_64-linux"}]
    )

    expect(reset.send(:ruby_gems_version_available?, "native-demo", "1.2.3-x86_64-linux")).to be(true)
  end

  it "raises when RubyGems.org version lookup fails" do
    response = Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable")
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    expect { reset.send(:ruby_gems_versions, "demo") }
      .to raise_error(Kettle::Dev::Error, /RubyGems\.org \(HTTP 503\)/)
  end

  it "raises when RubyGems.org version lookup returns invalid JSON" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.body = "{"
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    allow(Net::HTTP).to receive(:get_response).and_return(response)

    expect { reset.send(:ruby_gems_versions, "demo") }
      .to raise_error(Kettle::Dev::Error, /Could not parse released versions/)
  end
end
