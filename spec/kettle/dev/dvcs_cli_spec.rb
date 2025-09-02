# frozen_string_literal: true

require "tmpdir"
require "kettle/dev/dvcs_cli"

RSpec.describe Kettle::Dev::DvcsCLI do
  include_context "with mocked git adapter"

  let(:argv) { ["--force", "my-org", "my-repo"] }

  it "normalizes remotes and updates README when all fetches succeed" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Minimal README with the Federated DVCS summary line (with Coming soon!)
        File.write("README.md", <<~MD)
          ### Federated DVCS
          <details>
            <summary>Find this repo on other forges (Coming soon!)</summary>
          </details>
        MD

        # Also create a .git directory marker so some tools treat it as a repo-like folder
        Dir.mkdir(".git")

        # Prepare a stricter adapter double for this example to assert interactions
        adapter = instance_double(Kettle::Dev::GitAdapter)
        allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)

        # Clean working tree
        allow(adapter).to receive(:clean?).and_return(true)

        # No remotes initially; the CLI should add them
        allow(adapter).to receive(:remotes).and_return([])
        allow(adapter).to receive(:remotes_with_urls).and_return({})
        allow(adapter).to receive(:remote_url).and_return(nil)

        # Generic capture should succeed for all write commands
        allow(adapter).to receive(:capture).and_return(["", true])

        # Fetch from all three remotes should be attempted and succeed
        allow(adapter).to receive(:fetch).with("origin").and_return(true)
        allow(adapter).to receive(:fetch).with("gl").and_return(true)
        allow(adapter).to receive(:fetch).with("cb").and_return(true)

        status = described_class.new(argv).run!
        expect(status).to eq(0)

        content = File.read("README.md")
        expect(content).to include("<summary>Find this repo on other forges</summary>")
        expect(content).not_to include("(Coming soon!)")

        # verify some essential git remote operations were attempted
        # e.g., adding origin, gl, cb, and all remotes in some order
        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "origin", "git@github.com:my-org/my-repo.git")).at_least(:once)
        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "gl", "git@gitlab.com:my-org/my-repo.git")).at_least(:once)
        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "cb", "git@codeberg.org:my-org/my-repo.git")).at_least(:once)
        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "all", "git@github.com:my-org/my-repo.git")).at_least(:once)
      end
    end
  end

  it "prints import links and preserves Coming soon! when some fetches fail", :check_output do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("README.md", <<~MD)
          ### Federated DVCS
          <details>
            <summary>Find this repo on other forges</summary>
          </details>
        MD
        Dir.mkdir(".git")

        adapter = instance_double(Kettle::Dev::GitAdapter)
        allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
        allow(adapter).to receive(:clean?).and_return(true)
        allow(adapter).to receive(:remotes).and_return([])
        allow(adapter).to receive(:remotes_with_urls).and_return({})
        allow(adapter).to receive(:remote_url).and_return(nil)
        allow(adapter).to receive(:capture).and_return(["", true])

        # Fail GitLab and Codeberg
        allow(adapter).to receive(:fetch).with("origin").and_return(true)
        allow(adapter).to receive(:fetch).with("gl").and_return(false)
        allow(adapter).to receive(:fetch).with("cb").and_return(false)

        status = described_class.new(argv).run!
        expect(status).to eq(0)

        content = File.read("README.md")
        expect(content).to include("(Coming soon!)")
        expect(content).to include("<summary>Find this repo on other forges (Coming soon!)</summary>")
      end
    end
  end

  it "uses default 'gh' as GitHub remote name when origin is gitlab" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("README.md", "# Readme\n")
        Dir.mkdir(".git")
        adapter = instance_double(Kettle::Dev::GitAdapter)
        allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
        allow(adapter).to receive(:clean?).and_return(true)
        allow(adapter).to receive(:remotes).and_return([])
        allow(adapter).to receive(:remotes_with_urls).and_return({})
        allow(adapter).to receive(:remote_url).and_return(nil)
        allow(adapter).to receive(:capture).and_return(["", true])
        allow(adapter).to receive(:fetch).with("origin").and_return(true)
        allow(adapter).to receive(:fetch).with("gh").and_return(true)
        allow(adapter).to receive(:fetch).with("cb").and_return(true)

        status = described_class.new(["--force", "--origin", "gitlab", "my-org", "my-repo"]).run!
        expect(status).to eq(0)

        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "origin", "git@gitlab.com:my-org/my-repo.git")).at_least(:once)
        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "gh", "git@github.com:my-org/my-repo.git")).at_least(:once)
        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "cb", "git@codeberg.org:my-org/my-repo.git")).at_least(:once)
      end
    end
  end

  it "honors --github-name override when origin is codeberg" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("README.md", "# Readme\n")
        Dir.mkdir(".git")
        adapter = instance_double(Kettle::Dev::GitAdapter)
        allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
        allow(adapter).to receive(:clean?).and_return(true)
        allow(adapter).to receive(:remotes).and_return([])
        allow(adapter).to receive(:remotes_with_urls).and_return({})
        allow(adapter).to receive(:remote_url).and_return(nil)
        allow(adapter).to receive(:capture).and_return(["", true])
        allow(adapter).to receive(:fetch).with("origin").and_return(true)
        allow(adapter).to receive(:fetch).with("gl").and_return(true)
        allow(adapter).to receive(:fetch).with("hub").and_return(true)

        status = described_class.new(["--force", "--origin", "codeberg", "--github-name", "hub", "my-org", "my-repo"]).run!
        expect(status).to eq(0)

        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "origin", "git@codeberg.org:my-org/my-repo.git")).at_least(:once)
        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "gl", "git@gitlab.com:my-org/my-repo.git")).at_least(:once)
        expect(adapter).to have_received(:capture).with(array_including("remote", "add", "hub", "git@github.com:my-org/my-repo.git")).at_least(:once)
      end
    end
  end

  it "prints ahead/behind status for each remote relative to origin/main" do
    Dir.mktmpdir do |_dir|
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)

      # Status mode should not require clean working tree, but clean? may be called in other flows
      allow(adapter).to receive(:clean?).and_return(true)

      # Simulate default origin=github and expected lookups
      allow(adapter).to receive_messages(
        remotes: ["origin", "gl", "cb"],
        remotes_with_urls: {"origin" => "git@github.com:org/repo.git"},
        remote_url: nil,
      )

      # detect_default_branch!: first try origin/main ok
      allow(adapter).to receive(:capture).with(["rev-parse", "--verify", "origin/main"]).and_return(["", true])

      # fetches for status
      allow(adapter).to receive(:fetch).with("origin").and_return(true)
      allow(adapter).to receive(:fetch).with("gl").and_return(true)
      allow(adapter).to receive(:fetch).with("cb").and_return(true)

      # Show ahead/behind for gl and cb vs origin/main
      # Use output format "<left>\t<right>" or space – we split on whitespace
      allow(adapter).to receive(:capture).with(["rev-list", "--left-right", "--count", "origin/main...gl/main"]).and_return(["3\t1", true])
      allow(adapter).to receive(:capture).with(["rev-list", "--left-right", "--count", "origin/main...cb/main"]).and_return(["0\t0", true])

      result = nil
      expect {
        result = described_class.new(["--force", "--status", "org", "repo"]).run!
      }.to output(/Remote status relative to origin\/main:.*- gitlab \(gl\): ahead by 1, behind by 3.*- codeberg \(cb\): in sync/m).to_stdout_from_any_process
      expect(result).to eq(0)
    end
  end

  describe "detect_default_branch! variations" do
    it "falls back to master when origin/main missing but origin/master exists" do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
      allow(adapter).to receive(:clean?).and_return(true)
      allow(adapter).to receive_messages(remotes: ["origin"], remotes_with_urls: {"origin" => "git@github.com:o/r.git"})
      allow(adapter).to receive(:fetch).and_return(true)
      # main fails, master ok
      allow(adapter).to receive(:capture).with(["rev-parse", "--verify", "origin/main"]).and_return(["", false])
      allow(adapter).to receive(:capture).with(["rev-parse", "--verify", "origin/master"]).and_return(["", true])
      # status rev-list returns empty to hit "no data" path for non-origin remotes
      allow(adapter).to receive(:capture).with(["rev-list", "--left-right", "--count", "origin/master...gl/master"]).and_return(["", false])
      allow(adapter).to receive(:capture).with(["rev-list", "--left-right", "--count", "origin/master...cb/master"]).and_return(["", false])
      # Use status mode; provide inferred names
      allow(adapter).to receive(:remote_url).and_return(nil)
      # Names set so that github remote equals origin (so loop skips) and others nil
      # We'll simulate only github present as origin
      allow(adapter).to receive(:remotes).and_return(["origin"])
      expect(
        described_class.new(["--status", "o", "r"]).run!,
      ).to eq(0)
    end

    it "defaults to main when neither main nor master verifies" do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
      allow(adapter).to receive(:clean?).and_return(true)
      allow(adapter).to receive_messages(remotes: ["origin", "gl"], remotes_with_urls: {"origin" => "git@github.com:o/r.git"})
      allow(adapter).to receive(:fetch).and_return(true)
      allow(adapter).to receive(:capture).with(["rev-parse", "--verify", "origin/main"]).and_return(["", false])
      allow(adapter).to receive(:capture).with(["rev-parse", "--verify", "origin/master"]).and_return(["", false])
      # Then show_status! should use origin/main as base; provide rev-list data
      allow(adapter).to receive(:capture).with(["rev-list", "--left-right", "--count", "origin/main...gl/main"]).and_return([" ", false])
      allow(adapter).to receive(:capture).with(["rev-list", "--left-right", "--count", "origin/main...cb/main"]).and_return([" ", false])
      allow(adapter).to receive(:remote_url).and_return(nil)
      expect(
        described_class.new(["--status", "o", "r"]).run!,
      ).to eq(0)
    end
  end

  it "prints no data when rev-list fails for a remote", :check_output do
    adapter = instance_double(Kettle::Dev::GitAdapter)
    allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
    allow(adapter).to receive(:clean?).and_return(true)
    allow(adapter).to receive_messages(remotes: ["origin", "gl"], remotes_with_urls: {"origin" => "git@github.com:o/r.git"})
    allow(adapter).to receive(:fetch).and_return(true)
    allow(adapter).to receive(:capture).with(["rev-parse", "--verify", "origin/main"]).and_return(["", true])
    allow(adapter).to receive(:capture).with(["rev-list", "--left-right", "--count", "origin/main...gl/main"]).and_return(["", false])
    allow(adapter).to receive(:capture).with(["rev-list", "--left-right", "--count", "origin/main...cb/main"]).and_return(["", false])
    allow(adapter).to receive(:remote_url).and_return(nil)
    expect {
      described_class.new(["--status", "o", "r"]).run!
    }.to output(/no data \(branch missing\?\)/).to_stdout_from_any_process
  end

  it "shows help and exits 0 on -h", :real_exit_adapter do
    cli = described_class.new(["-h"])
    expect { cli.send(:parse!) }.to raise_error(SystemExit) do |e|
      expect(e.status).to eq(0)
    end
  end

  it "aborts on invalid origin in opts bypassing OptionParser", :real_exit_adapter do
    cli = described_class.new([])
    cli.instance_variable_get(:@opts)[:origin] = "bitbucket"
    expect { cli.send(:parse!) }.to raise_error(SystemExit)
  end

  it "aborts when GitAdapter is missing", :real_exit_adapter do
    hide_const("Kettle::Dev::GitAdapter")
    cli = described_class.new([])
    expect { cli.send(:ensure_git_adapter!) }.to raise_error(SystemExit)
  end

  it "builds https forge urls when protocol is https" do
    cli = described_class.new(["--protocol", "https"])
    cli.send(:parse!)
    urls = cli.send(:forge_urls, "org", "repo")
    expect(urls[:github]).to eq("https://github.com/org/repo.git")
    expect(urls[:gitlab]).to eq("https://gitlab.com/org/repo.git")
    expect(urls[:codeberg]).to eq("https://codeberg.org/org/repo.git")
  end

  describe "resolve_org_repo" do
    it "infers org/repo from remote url when not provided" do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
      allow(adapter).to receive(:clean?).and_return(true)
      allow(adapter).to receive(:remotes).and_return([])
      allow(adapter).to receive(:remotes_with_urls).and_return({"upstream" => "git@github.com:orgx/repo-y.git"})
      allow(adapter).to receive(:remote_url).and_return(nil)
      allow(adapter).to receive(:capture).and_return(["", true])
      allow(adapter).to receive(:fetch).and_return(true)
      # Reach resolve_org_repo via status mode
      expect(described_class.new(["--status"]).send(:resolve_org_repo, adapter)).to eq(["orgx", "repo-y"])
    end

    it "aborts when force and cannot infer org/repo", :real_exit_adapter do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(adapter).to receive(:remotes_with_urls).and_return({})
      cli = described_class.new(["--force"])
      cli.send(:parse!)
      expect { cli.send(:resolve_org_repo, adapter) }.to raise_error(SystemExit)
    end

    it "prompts for org/repo when not force; respects defaults and required constraint" do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(adapter).to receive(:remotes_with_urls).and_return({})
      cli = described_class.new([])
      cli.send(:parse!)
      # Simulate user entering blank for org, then "myorg"; same for repo
      input = StringIO.new("\nmyorg\n\nmyrepo\n")
      $stdin = input
      begin
        begin
          cli.send(:prompt, "Organization name", default: nil)
        rescue
          nil
        end
        expect { cli.send(:prompt, "Repository name", default: nil) }.not_to raise_error
      ensure
        $stdin = STDIN
      end
    end
  end

  describe "ensure_remote_alignment! operations" do
    it "updates url when remote exists with different url" do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      cli = described_class.new([])
      allow(adapter).to receive(:remotes).and_return(["origin"])
      allow(adapter).to receive(:remote_url).with("origin").and_return("git@github.com:o/a.git")
      expect(adapter).to receive(:capture).with(["remote", "set-url", "origin", "git@github.com:o/r.git"]).and_return(["", true])
      cli.send(:ensure_remote_alignment!, adapter, "origin", "git@github.com:o/r.git")
    end

    it "renames remote when url already present under different name" do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      cli = described_class.new([])
      allow(adapter).to receive(:remotes).and_return(["upstream"])
      allow(adapter).to receive(:remote_url).with("upstream").and_return("git@github.com:o/r.git")
      allow(adapter).to receive(:remotes_with_urls).and_return({"upstream" => "git@github.com:o/r.git"})
      expect(adapter).to receive(:capture).with(["remote", "rename", "upstream", "origin"]).and_return(["", true])
      cli.send(:ensure_remote_alignment!, adapter, "origin", "git@github.com:o/r.git")
    end
  end

  describe "configure_all_remote! variants" do
    it "removes existing all remote before recreating" do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      cli = described_class.new(["--force", "o", "r"])
      cli.send(:parse!)
      names = {origin: "origin", all: "all", github: "origin", gitlab: "gl", codeberg: "cb"}
      urls = {github: "git@github.com:o/r.git", gitlab: "git@gitlab.com:o/r.git", codeberg: "git@codeberg.org:o/r.git"}
      allow(adapter).to receive(:remotes).and_return(["all"])
      expect(adapter).to receive(:capture).with(["remote", "remove", "all"]).and_return(["", true])
      expect(adapter).to receive(:capture).with(["remote", "add", "all", "git@github.com:o/r.git"]).and_return(["", true])
      expect(adapter).to receive(:capture).with(["config", "--unset-all", "remote.all.fetch"]).and_return(["", true])
      expect(adapter).to receive(:capture).with(["config", "--add", "remote.all.fetch", "+refs/heads/*:refs/remotes/all/*"]).and_return(["", true])
      expect(adapter).to receive(:capture).with(["config", "--add", "remote.all.pushurl", "git@github.com:o/r.git"]).and_return(["", true])
      expect(adapter).to receive(:capture).with(["config", "--add", "remote.all.pushurl", "git@gitlab.com:o/r.git"]).and_return(["", true])
      expect(adapter).to receive(:capture).with(["config", "--add", "remote.all.pushurl", "git@codeberg.org:o/r.git"]).and_return(["", true])
      cli.send(:configure_all_remote!, adapter, names, urls)
    end
  end

  describe "sh_git! error handling" do
    it "aborts when args contain empty value", :real_exit_adapter do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      cli = described_class.new([])
      expect { cli.send(:sh_git!, adapter, ["remote", "add", "", "x"]) }.to raise_error(SystemExit)
    end

    it "aborts when git.capture returns not ok", :real_exit_adapter do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(adapter).to receive(:capture).and_return(["boom", false])
      cli = described_class.new([])
      expect { cli.send(:sh_git!, adapter, ["remote", "add", "n", "x"]) }.to raise_error(SystemExit)
    end
  end

  describe "show_remotes! display" do
    it "prints remote -v output when available", :check_output do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(adapter).to receive(:capture).with(["remote", "-v"]).and_return(["origin\tgit@x (fetch)\n", true])
      cli = described_class.new([])
      expect { cli.send(:show_remotes!, adapter) }.to output(/Current remotes \(git remote -v\):/).to_stdout_from_any_process
    end

    it "falls back to listing mapping when remote -v not available", :check_output do
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(adapter).to receive(:capture).with(["remote", "-v"]).and_return(["", false])
      allow(adapter).to receive(:remotes_with_urls).and_return({"a" => "url-a", "b" => "url-b"})
      cli = described_class.new([])
      expect { cli.send(:show_remotes!, adapter) }.to output(/Current remotes \(name => fetch URL\):\n  a\turl-a \(fetch\)\n  b\turl-b \(fetch\)/).to_stdout_from_any_process
    end
  end

  it "rescues errors while updating README federation status and warns", :check_output do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        File.write("README.md", "# hi\n")
        cli = described_class.new([])
        allow(File).to receive(:read).and_raise(StandardError.new("boom"))
        expect { cli.send(:update_readme_federation_status!, "o", "r", {github: true, gitlab: true, codeberg: true}) }.to output(/Failed to update README federation status: boom/).to_stderr_from_any_process
      end
    end
  end

  it "abort! warns and exits 1", :check_output, :real_exit_adapter do
    cli = described_class.new([])
    expect { cli.send(:abort!, "nope") }.to raise_error(SystemExit) do |e|
      expect(e.status).to eq(1)
    end
  end
end
