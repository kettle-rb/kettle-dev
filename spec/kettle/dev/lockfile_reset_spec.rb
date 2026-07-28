# frozen_string_literal: true

require "tmpdir"

RSpec.describe Kettle::Dev::LockfileReset do
  def released_registry_gem
    "rake"
  end

  def released_registry_version
    "13.4.2"
  end

  def never_released_registry_version
    "0.0.1"
  end

  def never_released_workspace_gem
    "kettle-starfish"
  end

  def released_workspace_version
    "1.0.0"
  end

  def unreleased_workspace_version
    "9.9.9"
  end

  around do |example|
    tmp_root = File.expand_path("../../../tmp/lockfile-reset-spec", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-dev-lockfile-reset-spec", tmp_root) do |dir|
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
    expect(command).to include("-u BUNDLE_GEMFILE")
    expect(command).to include("-u BUNDLE_LOCKFILE")
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
            #{never_released_workspace_gem} (#{released_workspace_version})

        CHECKSUMS
          #{never_released_workspace_gem} (#{released_workspace_version}) sha256=abc123
      LOCK
    })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          #{never_released_workspace_gem} (#{unreleased_workspace_version})

      CHECKSUMS
        #{never_released_workspace_gem} (#{unreleased_workspace_version}) sha256=localonly
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
            #{never_released_workspace_gem} (#{released_workspace_version})

        CHECKSUMS
          #{never_released_workspace_gem} (#{released_workspace_version}) sha256=abc123
      LOCK
    })
    FileUtils.mkdir_p(File.join(@root, never_released_workspace_gem))
    File.write(File.join(@root, never_released_workspace_gem, "#{never_released_workspace_gem}.gemspec"), "Gem::Specification.new { |s| s.name = '#{never_released_workspace_gem}' }\n")
    File.write(File.join(@root, "kettle-dev.gemspec"), "Gem::Specification.new { |s| s.name = 'kettle-dev' }\n")
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          #{never_released_workspace_gem} (#{unreleased_workspace_version})

      CHECKSUMS
        #{never_released_workspace_gem} (#{unreleased_workspace_version}) sha256=localonly
    LOCK
    allow(reset).to receive_messages(
      local_workspace_gem_names: Set[never_released_workspace_gem],
      locally_installed?: false,
      gem_source_version_available?: false
    )
    allow(reset).to receive(:locally_installed?).with(never_released_workspace_gem, released_workspace_version).and_return(true)
    allow(reset).to receive(:gem_source_version_available?).with(never_released_workspace_gem, released_workspace_version, ["https://rubygems.org/"]).and_return(true)
    allow(reset).to receive(:locally_installed?).with(never_released_workspace_gem, unreleased_workspace_version).and_return(true)
    allow(reset).to receive(:gem_source_version_available?).with(never_released_workspace_gem, unreleased_workspace_version, ["https://rubygems.org/"]).and_return(false)

    reset.reset("release-lockfiles")

    expect(commands.first).to include("-u BUNDLE_GEMFILE")
    expect(commands.first).to include("-u BUNDLE_LOCKFILE")
    expect(commands.first).to include("gem uninstall #{never_released_workspace_gem} -v #{unreleased_workspace_version} -x -I")
    expect(commands.last).to include("bundle lock --update --add-checksums")
  end

  it "reruns release lockfile reset when Bundler introduces a local-only workspace version" do
    commands = []
    bundle_resets = 0
    reset = described_class.new(root: @root, command_runner: lambda { |command|
      commands << command
      next unless command.include?("bundle lock")

      bundle_resets += 1
      version = (bundle_resets == 1) ? unreleased_workspace_version : released_workspace_version
      checksum = (bundle_resets == 1) ? "localonly" : "released"
      File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
        GEM
          remote: https://rubygems.org/
          specs:
            #{never_released_workspace_gem} (#{version})

        CHECKSUMS
          #{never_released_workspace_gem} (#{version}) sha256=#{checksum}
      LOCK
    })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          #{never_released_workspace_gem} (#{released_workspace_version})

      CHECKSUMS
        #{never_released_workspace_gem} (#{released_workspace_version}) sha256=released
    LOCK
    allow(reset).to receive(:local_workspace_gem_names).and_return(Set[never_released_workspace_gem])
    allow(reset).to receive(:locally_installed?).with(never_released_workspace_gem, released_workspace_version).and_return(true)
    allow(reset).to receive(:locally_installed?).with(never_released_workspace_gem, unreleased_workspace_version).and_return(true)
    allow(reset).to receive(:gem_source_version_available?).with(never_released_workspace_gem, released_workspace_version, ["https://rubygems.org/"]).and_return(true)
    allow(reset).to receive(:gem_source_version_available?).with(never_released_workspace_gem, unreleased_workspace_version, ["https://rubygems.org/"]).and_return(false)

    reset.reset("release-lockfiles")

    expect(commands.map { |command| command.include?("bundle lock") }).to eq([true, false, true])
    expect(commands[1]).to include("gem uninstall #{never_released_workspace_gem} -v #{unreleased_workspace_version} -x -I")
    expect(File.read(File.join(@root, "Gemfile.lock"))).to include("#{never_released_workspace_gem} (#{released_workspace_version})")
  end

  it "diagnoses fully checksummed workspace gem versions that are not released" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          #{never_released_workspace_gem} (#{unreleased_workspace_version})

      CHECKSUMS
        #{never_released_workspace_gem} (#{unreleased_workspace_version}) sha256=localonly
    LOCK
    allow(reset).to receive(:local_workspace_gem_names).and_return(Set[never_released_workspace_gem])
    allow(reset).to receive(:gem_source_version_available?).with(never_released_workspace_gem, unreleased_workspace_version, ["https://rubygems.org/"]).and_return(false)

    diagnostics = reset.diagnostics(File.join(@root, "Gemfile.lock"))

    expect(diagnostics.join("\n")).to include("locks local workspace gem #{never_released_workspace_gem} #{unreleased_workspace_version} as a registry gem")
  end

  it "targets unreleased workspace registry gems even when checksums are present" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          #{never_released_workspace_gem} (#{unreleased_workspace_version})

      CHECKSUMS
        #{never_released_workspace_gem} (#{unreleased_workspace_version}) sha256=localonly
    LOCK
    allow(reset).to receive(:local_workspace_gem_names).and_return(Set[never_released_workspace_gem])
    allow(reset).to receive(:gem_source_version_available?).with(never_released_workspace_gem, unreleased_workspace_version, ["https://rubygems.org/"]).and_return(false)

    command = reset.reset_command(path: File.join(@root, "Gemfile.lock"), gemfile: File.join(@root, "Gemfile"))

    expect(command).to include("bundle lock --update #{never_released_workspace_gem} --add-checksums")
  end

  it "continues when another release worker already removed the same local gem version" do
    reset = described_class.new(root: @root, command_runner: ->(_command) { raise "already removed" })
    allow(reset).to receive(:locally_installed?).with(never_released_workspace_gem, unreleased_workspace_version).and_return(false)

    expect { reset.send(:uninstall_unreleased_local_gem, never_released_workspace_gem, unreleased_workspace_version) }.not_to raise_error
  end

  it "fails when uninstall fails and the local gem version is still installed" do
    reset = described_class.new(root: @root, command_runner: ->(_command) { raise "permission denied" })
    allow(reset).to receive(:locally_installed?).with(never_released_workspace_gem, unreleased_workspace_version).and_return(true)

    expect { reset.send(:uninstall_unreleased_local_gem, never_released_workspace_gem, unreleased_workspace_version) }
      .to raise_error(RuntimeError, "permission denied")
  end

  it "uninstalls local workspace gems that do not resolve from the configured source" do
    commands = []
    reset = described_class.new(root: @root, command_runner: lambda { |command|
      commands << command
      File.write(File.join(@root, "Gemfile.lock"), <<~LOCK) if command.include?("bundle lock")
        GEM
          remote: https://rubygems.org/
          specs:
            #{never_released_workspace_gem} (#{unreleased_workspace_version})

        CHECKSUMS
          #{never_released_workspace_gem} (#{unreleased_workspace_version}) sha256=localonly
      LOCK
    })
    File.write(File.join(@root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          #{never_released_workspace_gem} (#{unreleased_workspace_version})

      CHECKSUMS
        #{never_released_workspace_gem} (#{unreleased_workspace_version}) sha256=localonly
    LOCK
    allow(reset).to receive(:local_workspace_gem_names).and_return(Set[never_released_workspace_gem])
    allow(reset).to receive(:locally_installed?).with(never_released_workspace_gem, unreleased_workspace_version).and_return(true)
    allow(reset).to receive(:bundler_inline_version_available?).and_return(false)

    expect { reset.reset("release-lockfiles") }.to raise_error(Kettle::Dev::Error, /not resolvable from the configured gem source/)
    expect(commands.grep(/gem uninstall/)).not_to be_empty
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
    env_pairs = {
      "ALPHA_DEV" => "/workspace/alpha",
      "BETA_LOCAL" => "~/workspace/beta",
      "GAMMA_DEV" => "relative/workspace",
      "DELTA_LOCAL" => "false",
      "EPSILON_DEV" => "true"
    }
    allow(ENV).to receive(:each) do |&block|
      env_pairs.each(&block)
    end
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
        remote: ../#{never_released_workspace_gem}
        specs:
          #{never_released_workspace_gem} (#{unreleased_workspace_version})

      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.4.2)

      CHECKSUMS
        kettle-dev (2.5.0)
        #{never_released_workspace_gem} (#{unreleased_workspace_version})
        rake (13.4.2) sha256=abc123

      DEPENDENCIES
        kettle-dev!
        #{never_released_workspace_gem}!
    LOCK

    path = File.join(@root, "Gemfile.lock")

    expect(reset.local_path_remote_lines(path)).to eq([7])
    expect(reset.reset_update_gems(path)).to eq([never_released_workspace_gem])
    expect(reset.diagnostics(path)).to eq(["#{Kettle::Dev.display_path(path)} has local path remote at line 7"])
  end

  it "allows the current gemspec path with CRLF line endings" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    path = File.join(@root, "Gemfile.lock")
    File.binwrite(path, <<~LOCK.gsub("\n", "\r\n"))
      PATH
        remote: .
        specs:
          kettle-dev (2.5.0)

      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.4.2)

      CHECKSUMS
        kettle-dev (2.5.0)
        rake (13.4.2) sha256=abc123
    LOCK

    expect(reset.local_path_remote_lines(path)).to be_empty
    expect(reset.diagnostics(path)).to be_empty
  end

  it "does not treat registry remotes as local path remotes" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    path = File.join(@root, "Gemfile.lock")
    File.write(path, <<~LOCK)
      PATH
        remote: .
        specs:
          kettle-dev (2.5.0)

      GEM
        remote: https://gem.coop/
        specs:
          rake (13.4.2)

      CHECKSUMS
        kettle-dev (2.5.0)
        rake (13.4.2) sha256=abc123
    LOCK

    expect(reset.local_path_remote_lines(path)).to be_empty
    expect(reset.diagnostics(path)).to be_empty
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

  it "uses an isolated exact artifact install probe before treating a version as released" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    success = instance_double(Process::Status, success?: true)

    expect(Open3).to receive(:capture3) do |env, *argv|
      expect(env).to include(
        "BUNDLE_GEMFILE" => nil,
        "BUNDLE_LOCKFILE" => nil,
        "GEM_HOME" => a_string_matching(%r{/tmp/kettle-gem-source-probe-}),
        "GEM_PATH" => a_string_matching(%r{/tmp/kettle-gem-source-probe-})
      )
      expect(argv).to include("gem", "install", released_registry_gem, "-v", "= #{released_registry_version}")
      expect(argv).to include("--source", "https://gem.coop")
      expect(argv).to include("--clear-sources", "--ignore-dependencies", "--no-document")
      ["", "", success]
    end

    expect(reset.send(:gem_source_version_available?, released_registry_gem, released_registry_version, ["https://gem.coop"])).to be(true)
  end

  it "returns false when the exact artifact cannot be installed from the configured source" do
    reset = described_class.new(root: @root, command_runner: ->(_command) {})
    failure = instance_double(Process::Status, success?: false)

    allow(Open3).to receive(:capture3).and_return(["", "not found", failure])

    expect(reset.send(:gem_source_version_available?, released_registry_gem, never_released_registry_version, ["https://gem.coop"])).to be(false)
  end
end
