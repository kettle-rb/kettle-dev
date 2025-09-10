# frozen_string_literal: true

# rubocop:disable ThreadSafety/DirChdir

RSpec.describe Kettle::Dev::SetupCLI do
  include_context "with stubbed env"

  before do
    require "kettle/dev"
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
    # Ensure we clean up ENV["force"] since SetupCLI writes directly to ENV
    begin
      expect(ENV["force"]).to be_nil
      _cli = described_class.new(["--force"]) # parse! runs in initialize
      expect(ENV["force"]).to eq("true")
    ensure
      ENV.delete("force")
    end
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

    it "seeds FUNDING_ORG from git origin when not provided elsewhere" do
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
      cli.send(:prechecks!)

      expect(ENV["FUNDING_ORG"]).to eq("acme")
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
  # rubocop:enable ThreadSafety/DirChdir
end
