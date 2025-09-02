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
end
