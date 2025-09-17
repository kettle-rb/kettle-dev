# frozen_string_literal: true

# rubocop:disable ThreadSafety/DirChdir

RSpec.describe Kettle::Dev::SetupCLI do
  def write(file, content)
    File.write(file, content)
  end

  def read(file)
    File.read(file)
  end

  it "updates existing add_development_dependency lines that omit parentheses, without creating duplicates" do
    Dir.mktmpdir do |dir|
      # rubocop:disable ThreadSafety/DirChdir
      Dir.chdir(dir) do
        # rubocop:enable ThreadSafety/DirChdir
        # minimal git repo to satisfy prechecks!
        %x(git init -q)
        # clean working tree
        %x(git add -A && git commit --allow-empty -m initial -q)

        # Create a Gemfile to satisfy prechecks
        write("Gemfile", "source 'https://rubygems.org'\n")

        # Create a target gemspec with non-parenthesized dev deps (from the user's example)
        gemspec = <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = 'example'
            spec.version = '0.0.1'

            spec.add_development_dependency 'addressable', '>= 2'
            spec.add_development_dependency 'rake', '>= 12'
            spec.add_development_dependency 'rexml', '>= 3'
            spec.add_development_dependency 'rspec', '>= 3'
            spec.add_development_dependency 'rspec-block_is_expected'
            spec.add_development_dependency 'rspec-pending_for'
            spec.add_development_dependency 'rspec-stubbed_env'
            spec.add_development_dependency 'rubocop-lts', ['>= 2.0.3', '~>2.0']
            spec.add_development_dependency 'silent_stream'
          end
        RUBY
        write("example.gemspec", gemspec)

        # Stub installed_path to point to the example shipped with repo
        example_path = File.expand_path("../../../kettle-dev.gemspec.example", __dir__)

        cli = described_class.allocate
        cli.instance_variable_set(:@argv, [])
        cli.instance_variable_set(:@passthrough, [])
        cli.send(:parse!) # init options

        # stub prechecks! to set gemspec/Gemfile without enforcing cleanliness again
        cli.instance_variable_set(:@gemspec_path, File.join(dir, "example.gemspec"))

        allow(cli).to receive(:installed_path).and_wrap_original do |orig, rel|
          # Only intercept the example gemspec lookup
          if rel == "kettle-dev.gemspec.example"
            example_path
          else
            orig.call(rel)
          end
        end

        # We also need to bypass git clean check inside prechecks!
        allow(cli).to receive(:prechecks!).and_return(nil)

        # Run just the dependency sync
        cli.send(:ensure_dev_deps!)

        result = read("example.gemspec")

        # Ensure we did not introduce duplicates for gems like rake and rspec-pending_for
        rake_lines = result.lines.grep(/add_development_dependency\s*\(?\s*["']rake["']/)
        pending_for_lines = result.lines.grep(/add_development_dependency\s*\(?\s*["']rspec-pending_for["']/)
        expect(rake_lines.size).to eq(1)
        expect(pending_for_lines.size).to eq(1)

        # Ensure the lines were updated to match the constraints from the example file (i.e., include ~> 13.0 etc.)
        expect(result).to match(/add_development_dependency\(\s*"rake"\s*,\s*"~> 13.0"\s*\)/)
        expect(result).to match(/add_development_dependency\(\s*"rspec-pending_for"\s*,\s*"~> 0.0"\s*,\s*">= 0.0.17"\s*\)/)
      end
    end
  end

  describe "include passthrough" do
    it "run_kettle_install! includes include=... in the rake command" do
      cli = described_class.allocate
      cli.instance_variable_set(:@passthrough, ["include=foo/bar/**"])
      expect(cli).to receive(:sh!).with(a_string_including("bin/rake kettle:dev:install include\\=foo/bar/\\*\\*"))
      cli.send(:run_kettle_install!)
    end
  end

  describe "#ensure_modular_gemfiles!" do
    it "calls ModularGemfiles.sync! and rescues metadata errors (min_ruby=nil)" do
      cli = described_class.allocate
      helpers = class_double(Kettle::Dev::TemplateHelpers)
      allow(helpers).to receive(:project_root).and_return("/tmp/project")
      allow(helpers).to receive(:gem_checkout_root).and_return("/tmp/checkout")
      allow(helpers).to receive(:gemspec_metadata).and_raise(StandardError)
      stub_const("Kettle::Dev::TemplateHelpers", helpers)

      called = false
      expect(Kettle::Dev::ModularGemfiles).to receive(:sync!) do |args|
        called = true
        expect(args[:helpers]).to eq(helpers)
        expect(args[:project_root]).to eq("/tmp/project")
        expect(args[:gem_checkout_root]).to eq("/tmp/checkout")
        expect(args[:min_ruby]).to be_nil
      end

      cli.send(:ensure_modular_gemfiles!)
      expect(called).to be true
    end
  end

  describe "#ensure_dev_deps! additional branches" do
    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    def setup_cli_for_deps(example_path)
      cli = described_class.allocate
      cli.instance_variable_set(:@argv, [])
      cli.instance_variable_set(:@passthrough, [])
      cli.send(:parse!)
      allow(cli).to receive(:installed_path).and_wrap_original do |orig, rel|
        if rel == "kettle-dev.gemspec.example"
          example_path
        else
          orig.call(rel)
        end
      end
      cli
    end

    it "appends wanted lines when target gemspec lacks closing end (no rindex match)" do
      # Create an empty gemspec to force the append code path
      File.write("target.gemspec", "")
      example_path = File.expand_path("../../../kettle-dev.gemspec.example", __dir__)
      cli = setup_cli_for_deps(example_path)
      cli.instance_variable_set(:@gemspec_path, File.join(Dir.pwd, "target.gemspec"))

      # Act
      cli.send(:ensure_dev_deps!)

      content = File.read("target.gemspec")
      # Expect at least one development dependency line to be present (from example)
      expect(content).to match(/add_development_dependency\(\s*"rake"/)
    end

    it "prints up-to-date message when no changes are needed", :check_output do
      # Make the target match the example exactly (after placeholder substitution)
      example_path = File.expand_path("../../../kettle-dev.gemspec.example", __dir__)
      text = File.read(example_path).gsub("{KETTLE|DEV|GEM}", "kettle-dev")
      File.write("target.gemspec", text)

      cli = setup_cli_for_deps(example_path)
      cli.instance_variable_set(:@gemspec_path, File.join(Dir.pwd, "target.gemspec"))

      expect { cli.send(:ensure_dev_deps!) }.to output(/Development dependencies already up to date\./).to_stdout
      expect(File.read("target.gemspec")).to eq(text)
    end
  end

  describe "#commit_bootstrap_changes! fallbacks" do
    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    it "uses Open3 fallback when GitAdapter raises (rescue branch)", :check_output do
      %x(git init -q)
      # Simulate clean working tree via Open3 output empty
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_raise(StandardError)
      allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["", instance_double(Process::Status)])
      cli = described_class.allocate
      expect { cli.send(:commit_bootstrap_changes!) }.to output(/No changes to commit/).to_stdout
    end

    it "uses Open3 path when GitAdapter constant is removed (else branch)", :check_output do
      %x(git init -q)
      hide_const("Kettle::Dev::GitAdapter")
      allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["", instance_double(Process::Status)])
      cli = described_class.allocate
      expect { cli.send(:commit_bootstrap_changes!) }.to output(/No changes to commit/).to_stdout
    end
  end

  describe "#derive_funding_org_from_git_if_missing!" do
    before do
      # Never modify ENV directly in specs; ensure OPENCOLLECTIVE_HANDLE is unset for each example
      # Also ensure FUNDING_ORG is unset to avoid cross-example leakage when a previous
      # example derives it from the git remote.
      stub_env("OPENCOLLECTIVE_HANDLE" => nil, "FUNDING_ORG" => nil)
    end

    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    def build_cli
      described_class.allocate
    end

    it "returns early when .opencollective.yml has org" do
      File.write(".opencollective.yml", "org: cool-co\n")
      cli = build_cli
      # Provide a git adapter that would otherwise set the env if called
      fake_ga = instance_double(Kettle::Dev::GitAdapter)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake_ga)
      allow(fake_ga).to receive(:clean?).and_return(true)
      allow(fake_ga).to receive(:remote_url).and_return("git@github.com:acme/thing.git")

      cli.send(:derive_funding_org_from_git_if_missing!)

      expect(ENV["FUNDING_ORG"]).to be_nil
    end

    it "logs debug when reading .opencollective.yml fails", :check_output do
      stub_env("DEBUG" => "true")
      oc = File.join(Dir.pwd, ".opencollective.yml")
      # Create file and then force File.read to raise for this specific path
      File.write(oc, "org: nope\n")
      cli = build_cli
      allow(File).to receive(:read).and_wrap_original do |orig, path|
        if path == oc
          raise IOError, "boom"
        else
          orig.call(path)
        end
      end
      expect { cli.send(:derive_funding_org_from_git_if_missing!) }
        .to output(/Reading \.opencollective\.yml failed: IOError: boom/).to_stderr
    end

    it "uses remotes_with_urls when remote_url is unavailable and sets FUNDING_ORG from origin", :check_output do
      stub_env("DEBUG" => "true")
      fake_ga = Object.new
      def fake_ga.respond_to?(m)
        m == :remotes_with_urls
      end
      allow(fake_ga).to receive(:remotes_with_urls).and_return({"origin" => "https://github.com/example/repo.git"})
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake_ga)

      cli = build_cli
      expect { cli.send(:derive_funding_org_from_git_if_missing!) }
        .to output(/Derived FUNDING_ORG from git origin: example/).to_stderr
    end

    it "logs debug when remotes_with_urls raises and otherwise continues silently", :check_output do
      stub_env("DEBUG" => "true")
      fake_ga = Object.new
      def fake_ga.respond_to?(m)
        m == :remotes_with_urls
      end
      allow(fake_ga).to receive(:remotes_with_urls).and_raise(StandardError, "bad remote")
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake_ga)

      cli = build_cli
      expect { cli.send(:derive_funding_org_from_git_if_missing!) }
        .to output(/remotes_with_urls failed: StandardError: bad remote/).to_stderr
      expect(ENV["FUNDING_ORG"]).to be_nil
    end

    it "swallows unexpected adapter errors and logs debug (outer rescue)", :check_output do
      stub_env("DEBUG" => "true")
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_raise(RuntimeError, "kaput")
      cli = build_cli
      expect { cli.send(:derive_funding_org_from_git_if_missing!) }
        .to output(/Could not derive funding org from git: RuntimeError: kaput/).to_stderr
    end
  end

  describe "#initialize and parse!" do
    it "collects passthrough options and remaining args; shows help and exits with 0", :check_output do
      argv = ["--allowed=foo", "--force", "--hook_templates=bar", "--only=baz", "-h"]
      expect do
        expect { described_class.new(argv) }.to raise_error(MockSystemExit, /exit status 0/)
      end.to output(/Usage: kettle-dev-setup/).to_stdout
    end

    it "rescues parse errors, prints usage, and exits 2", :check_output do
      argv = ["--unknown"]
      cli = described_class.allocate
      cli.instance_variable_set(:@argv, argv)
      # call private parse! directly to isolate behavior
      expect do
        expect { cli.send(:parse!) }.to raise_error(MockSystemExit, /exit status 2/)
      end.to output(/Usage: kettle-dev-setup/).to_stdout.and output(/OptionParser/).to_stderr
    end

    it "appends remaining argv into @passthrough when no special flags" do
      cli = described_class.new(["foo=1", "bar"])
      expect(cli.instance_variable_get(:@passthrough)).to include("foo=1", "bar")
    end
  end

  it "--force sets ENV['force']=true for in-process auto-yes prompts" do
    # Normally we never modify ENV directly in specs, but
    #   using --force has the effect of modifying ENV, so we need to stub it completely here.
    stub_const("ENV", {})
    _cli = described_class.new(["--force"]) # parse! runs in initialize
    expect(ENV["force"]).to eq("true")
  end

  describe "#debug" do
    it "prints when DEBUG=true", :check_output do
      stub_env("DEBUG" => "true")
      cli = described_class.allocate
      expect { cli.send(:debug, "hi") }.to output(/DEBUG: hi/).to_stderr
    end

    it "does not print when DEBUG=false", :check_output do
      stub_env("DEBUG" => "false")
      cli = described_class.allocate
      expect { cli.send(:debug, "hi") }.not_to output.to_stderr
    end
  end

  describe "#say and #abort!" do
    it "say prints with prefix", :check_output do
      cli = described_class.allocate
      expect { cli.send(:say, "msg") }.to output(/\[kettle-dev-setup\] msg/).to_stdout
    end

    it "abort! uses ExitAdapter and raises MockSystemExit with message" do
      cli = described_class.allocate
      expect { cli.send(:abort!, "boom") }.to raise_error(MockSystemExit, /ERROR: boom/)
    end
  end

  describe "#sh!" do
    it "prints command and stderr, and aborts on non-zero", :check_output do
      cli = described_class.allocate
      allow(Open3).to receive(:capture3).and_return(["", "err", instance_double(Process::Status, success?: false)])
      expect do
        expect { cli.send(:sh!, "echo hi") }.to raise_error(MockSystemExit, /Command failed/)
      end.to output(/exec: echo hi/).to_stdout.and output("err").to_stderr
    end

    it "passes env to capture3 and succeeds", :check_output do
      cli = described_class.allocate
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with({"A" => "1"}, "cmd").and_return(["", "", status])
      expect { cli.send(:sh!, "cmd", env: {"A" => "1"}) }.to output(/exec: cmd/).to_stdout
    end
  end

  describe "#ensure_gemfile_from_example!" do
    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    it "merges Gemfile.example entries without duplicating directives" do
      # minimal git repo and files
      %x(git init -q)
      %x(git add -A && git commit --allow-empty -m initial -q)
      File.write("a.gemspec", "Gem::Specification.new do |s| end\n")

      # Start with a Gemfile that already has source, gemspec, and one eval_gemfile
      initial = <<~G
        source "https://rubygems.org"
        gemspec
        eval_gemfile "gemfiles/modular/style.gemfile"
      G
      File.write("Gemfile", initial)

      cli = described_class.allocate
      cli.instance_variable_set(:@argv, [])
      cli.instance_variable_set(:@passthrough, [])
      cli.send(:parse!)

      # Stub installed_path to return the repo's Gemfile.example
      example_path = File.expand_path("../../../Gemfile.example", __dir__)
      allow(cli).to receive(:installed_path).and_wrap_original do |orig, rel|
        if rel == "Gemfile.example"
          example_path
        else
          orig.call(rel)
        end
      end

      # Act
      cli.send(:ensure_gemfile_from_example!)

      result = File.read("Gemfile")

      # It should not duplicate the existing source/gemspec/eval line
      expect(result.scan(/^source /).size).to eq(1)
      expect(result.scan(/^gemspec/).size).to eq(1)
      expect(result.scan(/^eval_gemfile \"gemfiles\/modular\/style.gemfile\"/).size).to eq(1)

      # It should add the git_source lines (both github and gitlab) from example
      expect(result).to match(/^git_source\(:github\) \{ \|repo_name\| \"https:\/\/github.com\/\#\{repo_name\}\" \}/)
      expect(result).to match(/^git_source\(:gitlab\) \{ \|repo_name\| \"https:\/\/gitlab.com\/\#\{repo_name\}\" \}/)

      # It should add the missing eval_gemfile entries listed in the example
      expect(result).to include('eval_gemfile "gemfiles/modular/debug.gemfile"')
      expect(result).to include('eval_gemfile "gemfiles/modular/coverage.gemfile"')
      expect(result).to include('eval_gemfile "gemfiles/modular/documentation.gemfile"')
      expect(result).to include('eval_gemfile "gemfiles/modular/optional.gemfile"')
      expect(result).to include('eval_gemfile "gemfiles/modular/x_std_libs.gemfile"')

      # Idempotent on second run
      cli.send(:ensure_gemfile_from_example!)
      result2 = File.read("Gemfile")
      expect(result2).to eq(result)
    end
  end

  describe "#prechecks!" do
    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    before do
      # Ensure no leftover env interferes with derivation logic
      # Never modify ENV directly in specs; use stub_env from rspec-stubbed_env
      stub_env("OPENCOLLECTIVE_HANDLE" => nil)
    end

    it "seeds FUNDING_ORG from git origin when not provided elsewhere", :check_output do
      %x(git init -q)
      %x(git add -A && git commit --allow-empty -m initial -q)
      File.write("Gemfile", "")
      File.write("a.gemspec", "Gem::Specification.new do |s| end\n")
      # Ensure no env or oc file
      # stubbed_env context starts with nils, just ensure file not present
      FileUtils.rm_f(".opencollective.yml")

      fake_ga = instance_double(Kettle::Dev::GitAdapter)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake_ga)
      allow(fake_ga).to receive(:clean?).and_return(true)
      allow(fake_ga).to receive(:remote_url).with("origin").and_return("git@github.com:acme/thing.git")

      cli = described_class.allocate
      # Ensure derivation path is taken; use stub_env to clear FUNDING_ORG without asserting on ENV later
      stub_env("FUNDING_ORG" => nil, "DEBUG" => "true")
      expect { cli.send(:prechecks!) }
        .to output(/Derived FUNDING_ORG from git origin: acme/).to_stderr
    end

    it "aborts if not in git repo" do
      cli = described_class.allocate
      expect { cli.send(:prechecks!) }.to raise_error(MockSystemExit, /Not inside a git repository/)
    end

    it "aborts on dirty tree via git status fallback" do
      %x(git init -q)
      File.write("Gemfile", "")
      File.write("a.gemspec", "Gem::Specification.new do |s| end\n")
      out = " M file\n"
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_raise(StandardError)
      allow(Open3).to receive(:capture3).with("git status --porcelain").and_return([out, "", instance_double(Process::Status)])
      cli = described_class.allocate
      expect { cli.send(:prechecks!) }.to raise_error(MockSystemExit, /Git working tree is not clean/)
    end

    it "sets @gemspec_path and passes when clean and files present" do
      %x(git init -q)
      %x(git add -A && git commit --allow-empty -m initial -q)
      File.write("Gemfile", "")
      File.write("a.gemspec", "Gem::Specification.new do |s| end\n")
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(double(clean?: true))
      cli = described_class.allocate
      cli.send(:prechecks!)
      expect(cli.instance_variable_get(:@gemspec_path)).to end_with("a.gemspec")
    end

    it "aborts if no gemspec or Gemfile" do
      %x(git init -q)
      %x(git add -A && git commit --allow-empty -m initial -q)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(double(clean?: true))
      cli = described_class.allocate
      expect { cli.send(:prechecks!) }.to raise_error(MockSystemExit, /No gemspec/)
      File.write("a.gemspec", "Gem::Specification.new do |s| end\n")
      expect { cli.send(:prechecks!) }.to raise_error(MockSystemExit, /No Gemfile/)
    end
  end

  describe "#ensure_bin_setup! and #ensure_rakefile!" do
    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    it "copies bin/setup when missing", :check_output do
      cli = described_class.allocate
      # create a temp source file to simulate installed gem asset
      src = File.expand_path("src_bin_setup", Dir.pwd)
      File.write(src, "#!/usr/bin/env ruby\n")
      FileUtils.chmod("+x", src)
      allow(cli).to receive(:installed_path).and_return(src)
      expect { cli.send(:ensure_bin_setup!) }.to output(/Copied bin\/setup/).to_stdout
      expect(File.exist?("bin/setup")).to be true
      expect(File.stat("bin/setup").mode & 0o111).to be > 0
    end

    it "says present when bin/setup exists", :check_output do
      FileUtils.mkdir_p("bin")
      File.write("bin/setup", "#!/usr/bin/env ruby\n")
      cli = described_class.allocate
      expect { cli.send(:ensure_bin_setup!) }.to output(/bin\/setup present\./).to_stdout
    end

    it "writes Rakefile from example and announces replacement or creation", :check_output do
      cli = described_class.allocate
      # create a temp source Rakefile.example to simulate installed gem asset
      src = File.expand_path("src_Rakefile.example", Dir.pwd)
      File.write(src, "# demo Rakefile contents\n")
      allow(cli).to receive(:installed_path).and_return(src)
      expect { cli.send(:ensure_rakefile!) }.to output(/Creating Rakefile/).to_stdout
      File.write("Rakefile", "old")
      expect { cli.send(:ensure_rakefile!) }.to output(/Replacing existing Rakefile/).to_stdout
      expect(File.read("Rakefile")).to eq(File.read(src))
    end
  end

  describe "#commit_bootstrap_changes! and downstream cmds" do
    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    it "no-ops when clean", :check_output do
      %x(git init -q)
      %x(git add -A && git commit --allow-empty -m initial -q)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(double(clean?: true))
      cli = described_class.allocate
      expect { cli.send(:commit_bootstrap_changes!) }.to output(/No changes to commit/).to_stdout
    end

    it "adds and commits when dirty and prints messages", :check_output do
      %x(git init -q)
      File.write("file", "x")
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(double(clean?: false))
      cli = described_class.allocate
      allow(cli).to receive(:sh!).and_call_original
      # Stub sh! internals to not actually execute
      allow(Open3).to receive(:capture3).and_return(["", "", instance_double(Process::Status, success?: true)])
      expect { cli.send(:commit_bootstrap_changes!) }.to output(/Committed template bootstrap changes/).to_stdout
    end

    it "run_bin_setup! and run_bundle_binstubs! invoke sh! with proper command" do
      cli = described_class.allocate
      expect(cli).to receive(:sh!).with(/bin\/setup/)
      cli.send(:run_bin_setup!)
      expect(cli).to receive(:sh!).with("bundle exec bundle binstubs --all")
      cli.send(:run_bundle_binstubs!)
    end

    it "run_kettle_install! builds rake cmd with passthrough" do
      cli = described_class.allocate
      cli.instance_variable_set(:@passthrough, ["only=hooks"])
      expect(cli).to receive(:sh!).with(a_string_including("bin/rake kettle:dev:install only\\=hooks"))
      cli.send(:run_kettle_install!)
    end
  end

  describe "#installed_path" do
    it "resolves within installed gem when loaded spec present" do
      cli = described_class.allocate
      spec = instance_double(Gem::Specification, full_gem_path: File.expand_path("../../../../", __dir__))
      allow(Gem).to receive(:loaded_specs).and_return({"kettle-dev" => spec})
      path = cli.send(:installed_path, "Rakefile.example")
      expect(path).to end_with("Rakefile.example")
      expect(File.exist?(path)).to be true
    end

    it "falls back to repo checkout path when gem not loaded" do
      cli = described_class.allocate
      allow(Gem).to receive(:loaded_specs).and_return({})
      path = cli.send(:installed_path, "Rakefile.example")
      expect(path).to end_with("Rakefile.example")
      expect(File.exist?(path)).to be true
    end

    it "returns nil when file not present in either location" do
      cli = described_class.allocate
      allow(Gem).to receive(:loaded_specs).and_return({})
      expect(cli.send(:installed_path, "nope.txt")).to be_nil
    end
  end

  describe "#run! end-to-end sequencing" do
    it "calls steps in order" do
      cli = described_class.allocate
      cli.instance_variable_set(:@argv, [])
      allow(cli).to receive(:parse!)
      %i[prechecks! ensure_dev_deps! ensure_gemfile_from_example! ensure_modular_gemfiles! ensure_bin_setup! ensure_rakefile! run_bin_setup! run_bundle_binstubs! commit_bootstrap_changes! run_kettle_install!].each do |m|
        expect(cli).to receive(m).ordered
      end
      expect { cli.run! }.not_to raise_error
    end
  end
end
# rubocop:enable ThreadSafety/DirChdir
