# frozen_string_literal: true

RSpec.describe Kettle::Dev::CIMonitor do
  let(:helpers) { Kettle::Dev::CIHelpers }

  before do
    # Speed up polling loops
    allow(described_class).to receive(:sleep)
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

      # Set env to 0 to avoid real delay
      ENV["K_RELEASE_CI_INITIAL_SLEEP"] = "0"
      begin
        expect { described_class.collect_github }.not_to raise_error
      ensure
        ENV.delete("K_RELEASE_CI_INITIAL_SLEEP")
      end
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
