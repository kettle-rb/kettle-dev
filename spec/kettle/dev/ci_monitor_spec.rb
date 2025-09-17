# frozen_string_literal: true

RSpec.describe Kettle::Dev::CIMonitor do
  let(:helpers) { Kettle::Dev::CIHelpers }

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

  describe "::monitor_and_prompt_for_release!" do
    before do
      # Simulate presence of failed checks so the prompt is reached
      allow(described_class).to receive(:collect_all).and_return({
        github: [
          {workflow: "ci.yml", status: "completed", conclusion: "failure", url: "https://example"},
        ],
        gitlab: nil,
      })
      # TTY environment
      allow($stdin).to receive(:tty?).and_return(true)
    end

    it "continues once when user enters c", :check_output do
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("c\n")
      expect { described_class.monitor_and_prompt_for_release!(restart_hint: "hint") }.not_to raise_error
    end

    it "aborts when user enters q" do
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
      expect { described_class.monitor_and_prompt_for_release!(restart_hint: "hint") }.to raise_error(MockSystemExit, /Aborting per user choice/)
    end

    it "aborts when input is nil (no input available)" do
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return(nil)
      expect { described_class.monitor_and_prompt_for_release!(restart_hint: "hint") }.to raise_error(MockSystemExit, /no input available/)
    end

    it "aborts on unrecognized input (single prompt)" do
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("maybe\n")
      expect { described_class.monitor_and_prompt_for_release!(restart_hint: "hint") }.to raise_error(MockSystemExit, /Unrecognized input/)
    end

    it "skips prompt in non-interactive when K_RELEASE_CI_CONTINUE=true", :check_output do
      stub_env("K_RELEASE_CI_CONTINUE" => "true")
      allow($stdin).to receive(:tty?).and_return(false)
      expect { described_class.monitor_and_prompt_for_release!(restart_hint: "hint") }.not_to raise_error
    end

    it "aborts in non-interactive when K_RELEASE_CI_CONTINUE not set" do
      stub_env("K_RELEASE_CI_CONTINUE" => nil)
      allow($stdin).to receive(:tty?).and_return(false)
      expect { described_class.monitor_and_prompt_for_release!(restart_hint: "hint") }.to raise_error(MockSystemExit, /CI checks reported failures/)
    end
  end

  describe "::collect_all" do
    it "handles exceptions from collectors and still returns results hash" do
      # Force collect_github to raise, collect_gitlab to return nil
      allow(described_class).to receive(:collect_github).and_raise(StandardError.new("boom"))
      allow(described_class).to receive(:collect_gitlab).and_return(nil)
      # Stub debug_error to avoid noisy output but assert it is called
      allow(Kettle::Dev).to receive(:debug_error)

      res = described_class.collect_all
      expect(res).to be_a(Hash)
      expect(res[:github]).to eq([]) # default
      expect(res[:gitlab]).to be_nil
      expect(Kettle::Dev).to have_received(:debug_error).at_least(:once)
    end

    it "populates keys when collectors return values" do
      gh = [{workflow: "ci.yml", status: "completed", conclusion: "success", url: "https://x"}]
      gl = {status: "success", url: "https://gitlab.com/x/y/-/pipelines"}
      allow(described_class).to receive_messages(
        collect_github: gh,
        collect_gitlab: gl,
      )
      res = described_class.collect_all
      expect(res[:github]).to eq(gh)
      expect(res[:gitlab]).to eq(gl)
    end
  end

  describe "::summarize_results" do
    it "prints GitHub and GitLab summaries and returns true when ok", :check_output do
      res = {
        github: [
          {workflow: "ci.yml", status: "completed", conclusion: "success", url: "https://example"},
        ],
        gitlab: {status: "success", url: "https://gitlab.com/me/repo/-/pipelines"},
      }
      expect(described_class.summarize_results(res)).to be true
    end

    it "returns false when GitLab failed", :check_output do
      res = {
        github: [],
        gitlab: {status: "failed", url: nil},
      }
      expect(described_class.summarize_results(res)).to be false
    end

    it "handles nil gitlab and empty github", :check_output do
      res = {github: [], gitlab: nil}
      expect(described_class.summarize_results(res)).to be true
    end
  end

  describe "::collect_github" do
    it "returns nil when no gh remote or workflows" do
      allow(helpers).to receive_messages(project_root: Dir.pwd, workflows_list: [])
      allow(described_class).to receive(:preferred_github_remote).and_return(nil)
      expect(described_class.collect_github).to be_nil
    end

    it "collects success and failure runs without aborting", :check_output do
      allow(helpers).to receive_messages(project_root: Dir.pwd, workflows_list: ["ci.yml", "lint.yml"], current_branch: "main")
      allow(described_class).to receive(:preferred_github_remote).and_return("origin")
      allow(described_class).to receive_messages(remote_url: "https://github.com/me/repo.git", parse_github_owner_repo: ["me", "repo"])

      # First workflow succeeds, second fails
      runs = {
        "ci.yml" => {"status" => "completed", "conclusion" => "success", "html_url" => "https://github.com/me/repo/actions/runs/1"},
        "lint.yml" => {"status" => "completed", "conclusion" => "failure", "html_url" => nil},
      }
      allow(helpers).to receive(:latest_run) do |owner:, repo:, workflow_file:, branch:|
        runs[workflow_file]
      end
      allow(helpers).to receive(:success?) { |run| run["conclusion"] == "success" }
      allow(helpers).to receive(:failed?) { |run| run["conclusion"] == "failure" }

      res = described_class.collect_github
      expect(res).to contain_exactly(
        include(workflow: "ci.yml", conclusion: "success", url: "https://github.com/me/repo/actions/runs/1"),
        include(workflow: "lint.yml", conclusion: "failure", url: "https://github.com/me/repo/actions/workflows/lint.yml"),
      )
    end

    it "respects K_RELEASE_CI_INITIAL_SLEEP when set" do
      allow(helpers).to receive_messages(project_root: Dir.pwd, workflows_list: ["ci.yml"], current_branch: "main")
      allow(described_class).to receive_messages(preferred_github_remote: "origin", remote_url: "https://github.com/me/repo.git", parse_github_owner_repo: ["me", "repo"])
      allow(helpers).to receive_messages(latest_run: {"status" => "completed", "conclusion" => "success", "html_url" => "https://x"}, success?: true)

      # Set env to 0 to avoid real delay (do not modify ENV directly in specs)
      stub_env("K_RELEASE_CI_INITIAL_SLEEP" => "0")
      expect { described_class.collect_github }.not_to raise_error
    end
  end

  describe "::collect_gitlab" do
    it "returns nil when not configured" do
      allow(helpers).to receive(:project_root).and_return(Dir.pwd)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(false)
      allow(described_class).to receive_messages(gitlab_remote_candidates: [])
      expect(described_class.collect_gitlab).to be_nil
    end

    it "returns success result when pipeline succeeds", :check_output do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
      allow(described_class).to receive_messages(gitlab_remote_candidates: ["gl"])
      pipe = {"status" => "success", "web_url" => "https://gitlab.com/me/repo/-/pipelines/9"}
      allow(helpers).to receive_messages(project_root: Dir.pwd, current_branch: "feat", repo_info_gitlab: ["me", "repo"], gitlab_latest_pipeline: pipe, gitlab_success?: true)
      res = described_class.collect_gitlab
      expect(res[:status]).to eq("success")
      expect(res[:url]).to eq("https://gitlab.com/me/repo/-/pipelines/9")
    end

    it "returns failed result when pipeline fails normally" do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
      allow(described_class).to receive_messages(gitlab_remote_candidates: ["gl"])
      pipe = {"status" => "failed", "web_url" => nil, "failure_reason" => "script_failure"}
      allow(helpers).to receive_messages(project_root: Dir.pwd, current_branch: "feat", repo_info_gitlab: ["me", "repo"], gitlab_latest_pipeline: pipe, gitlab_success?: false, gitlab_failed?: true)
      res = described_class.collect_gitlab
      expect(res[:status]).to eq("failed")
      expect(res[:url]).to eq("https://gitlab.com/me/repo/-/pipelines")
    end

    it "returns unknown when minutes/quota exhausted" do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
      allow(described_class).to receive_messages(gitlab_remote_candidates: ["gl"])
      pipe = {"status" => "failed", "web_url" => nil, "failure_reason" => "insufficient minutes"}
      allow(helpers).to receive_messages(project_root: Dir.pwd, current_branch: "feat", repo_info_gitlab: ["me", "repo"], gitlab_latest_pipeline: pipe, gitlab_success?: false, gitlab_failed?: true)
      res = described_class.collect_gitlab
      expect(res[:status]).to eq("unknown")
    end

    it "returns blocked when pipeline status is blocked" do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(File.join(Dir.pwd, ".gitlab-ci.yml")).and_return(true)
      allow(described_class).to receive_messages(gitlab_remote_candidates: ["gl"])
      pipe = {"status" => "blocked", "web_url" => nil}
      allow(helpers).to receive_messages(project_root: Dir.pwd, current_branch: "feat", repo_info_gitlab: ["me", "repo"], gitlab_latest_pipeline: pipe, gitlab_success?: false, gitlab_failed?: false)
      res = described_class.collect_gitlab
      expect(res[:status]).to eq("blocked")
    end
  end
end
