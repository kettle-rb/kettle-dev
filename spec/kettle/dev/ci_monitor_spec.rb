# frozen_string_literal: true

RSpec.describe Kettle::Dev::CIMonitor do
  let(:helpers) { Kettle::Dev::CIHelpers }

  before do
    # Speed up loops inside monitor (we still assert on the initial sleep with a specific value in dedicated examples)
    allow(described_class).to receive(:sleep)
  end

  describe "::monitor_gitlab! minutes exhausted handling" do
    it "treats insufficient quota/minutes as unknown and continues", :check_output do
      allow(helpers).to receive(:project_root).and_return(Dir.pwd)
      allow(helpers).to receive(:current_branch).and_return("feat")
      # Pretend .gitlab-ci.yml exists and there is a gitlab remote
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
      allow(described_class).to receive(:gitlab_remote_candidates).and_return(["gitlab"])

      allow(helpers).to receive(:repo_info_gitlab).and_return(["me", "repo"])

      # Return a pipeline hash that indicates failure with insufficient quota
      pipe = {"status" => "failed", "web_url" => "https://gitlab.com/me/repo/-/pipelines/1", "id" => 1, "failure_reason" => "insufficient_quota"}
      allow(helpers).to receive(:gitlab_latest_pipeline).and_return(pipe)
      allow(helpers).to receive(:gitlab_success?).and_return(false)
      allow(helpers).to receive(:gitlab_failed?).and_return(true)

      expect { described_class.monitor_gitlab!(restart_hint: "hint") }.not_to raise_error
    end

    it "treats blocked status as unknown and continues", :check_output do
      allow(helpers).to receive(:project_root).and_return(Dir.pwd)
      allow(helpers).to receive(:current_branch).and_return("feat")
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
      allow(described_class).to receive(:gitlab_remote_candidates).and_return(["gitlab"])

      allow(helpers).to receive(:repo_info_gitlab).and_return(["me", "repo"])

      pipe = {"status" => "blocked", "web_url" => "https://gitlab.com/me/repo/-/pipelines/2", "id" => 2}
      allow(helpers).to receive(:gitlab_latest_pipeline).and_return(pipe)
      allow(helpers).to receive(:gitlab_success?).and_return(false)
      allow(helpers).to receive(:gitlab_failed?).and_return(false)

      expect { described_class.monitor_gitlab!(restart_hint: "hint") }.not_to raise_error
    end

    it "still aborts on a normal failure", :check_output do
      allow(helpers).to receive(:project_root).and_return(Dir.pwd)
      allow(helpers).to receive(:current_branch).and_return("feat")
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
      allow(described_class).to receive(:gitlab_remote_candidates).and_return(["gitlab"])

      allow(helpers).to receive(:repo_info_gitlab).and_return(["me", "repo"])

      pipe = {"status" => "failed", "web_url" => "https://gitlab.com/me/repo/-/pipelines/3", "id" => 3, "failure_reason" => "script_failure"}
      allow(helpers).to receive(:gitlab_latest_pipeline).and_return(pipe)
      allow(helpers).to receive(:gitlab_success?).and_return(false)
      allow(helpers).to receive(:gitlab_failed?).and_return(true)

      expect { described_class.monitor_gitlab!(restart_hint: "hint") }.to raise_error(MockSystemExit, /Pipeline failed:/)
    end

    it "returns false when gitlab not configured" do
      allow(helpers).to receive(:project_root).and_return(Dir.pwd)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(false)
      allow(described_class).to receive(:gitlab_remote_candidates).and_return([])
      expect(described_class.monitor_gitlab!(restart_hint: "hint")).to be false
    end
  end

  describe "github helper branches" do
    include_context "with stubbed env"

    it "waits initial seconds before polling GitHub (configurable via K_RELEASE_CI_INITIAL_SLEEP)", :check_output do
      # Arrange a minimal GitHub setup
      allow(helpers).to receive_messages(
        project_root: Dir.pwd,
        workflows_list: ["ci.yml"],
        current_branch: "main",
        latest_run: {"status" => "completed", "conclusion" => "success", "html_url" => "https://github.com/me/repo/actions/runs/1", "id" => 1},
      )
      allow(described_class).to receive_messages(
        preferred_github_remote: "origin",
        remote_url: "https://github.com/me/repo.git",
      )

      # Expect initial sleep to be called with our configured value, then allow other sleeps (loop) to be stubbed
      stub_env("K_RELEASE_CI_INITIAL_SLEEP" => "5")
      allow(described_class).to receive(:sleep)

      expect { described_class.monitor_all!(restart_hint: "hint") }.not_to raise_error
      expect(described_class).to have_received(:sleep).with(5)
    end

    it "preferred_github_remote returns nil when no candidates" do
      allow(described_class).to receive(:remotes_with_urls).and_return({})
      expect(described_class.preferred_github_remote).to be_nil
    end

    it "preferred_github_remote prefers explicit then origin then first" do
      allow(described_class).to receive(:remotes_with_urls).and_return({
        "origin" => "https://github.com/me/repo.git",
        "github" => "https://github.com/me/repo.git",
      })
      expect(described_class.preferred_github_remote).to eq("github")
      allow(described_class).to receive(:remotes_with_urls).and_return({
        "origin" => "https://github.com/me/repo.git",
        "upstream" => "https://github.com/me/repo.git",
      })
      expect(described_class.preferred_github_remote).to eq("origin")
      allow(described_class).to receive(:remotes_with_urls).and_return({
        "foo" => "https://github.com/me/repo.git",
        "bar" => "https://github.com/me/other.git",
      })
      expect(described_class.preferred_github_remote).to eq("foo")
    end

    it "parse_github_owner_repo handles nil and unknown patterns" do
      expect(described_class.parse_github_owner_repo(nil)).to eq([nil, nil])
      expect(described_class.parse_github_owner_repo("ssh://gitlab.com/u/r")).to eq([nil, nil])
    end

    it "parses SSH and HTTPS URLs" do
      expect(described_class.parse_github_owner_repo("git@github.com:me/repo.git")).to eq(["me", "repo"])
      expect(described_class.parse_github_owner_repo("https://github.com/me/repo")).to eq(["me", "repo"])
    end

    it "github_remote_candidates filters by github.com" do
      allow(described_class).to receive(:remotes_with_urls).and_return({
        "origin" => "https://gitlab.com/me/repo.git",
        "gh" => "git@github.com:me/repo.git",
        "cb" => "https://codeberg.org/me/repo.git",
      })
      expect(described_class.github_remote_candidates).to eq(["gh"])
    end

    it "gitlab_remote_candidates filters by gitlab.com" do
      allow(described_class).to receive(:remotes_with_urls).and_return({
        "origin" => "https://github.com/me/repo.git",
        "gl" => "git@gitlab.com:me/repo.git",
        "cb" => "https://codeberg.org/me/repo.git",
      })
      expect(described_class.gitlab_remote_candidates).to eq(["gl"])
    end
  end

  describe "wrappers around GitAdapter" do
    it "delegates remotes_with_urls and remote_url" do
      fake = instance_double(Kettle::Dev::GitAdapter)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake)
      allow(fake).to receive(:remotes_with_urls).and_return({"origin" => "https://github.com/acme/demo.git"})
      allow(fake).to receive(:remote_url).with("origin").and_return("https://github.com/acme/demo.git")
      expect(described_class.remotes_with_urls).to eq({"origin" => "https://github.com/acme/demo.git"})
      expect(described_class.remote_url("origin")).to eq("https://github.com/acme/demo.git")
    end
  end

  describe "::monitor_all! no CI configured" do
    it "aborts when neither GitHub nor GitLab present" do
      allow(helpers).to receive(:project_root).and_return(Dir.pwd)
      allow(helpers).to receive(:workflows_list).and_return([])
      allow(described_class).to receive(:preferred_github_remote).and_return(nil)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(false)
      allow(described_class).to receive(:gitlab_remote_candidates).and_return([])
      allow(helpers).to receive(:current_branch).and_return("feat")
      expect { described_class.monitor_all!(restart_hint: "hint") }.to raise_error(MockSystemExit, /CI configuration not detected/)
    end
  end
end
