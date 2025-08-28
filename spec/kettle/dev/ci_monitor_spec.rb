# frozen_string_literal: true

require "kettle/dev/ci_monitor"

RSpec.describe Kettle::Dev::CIMonitor do
  let(:helpers) { Kettle::Dev::CIHelpers }

  before do
    # Speed up loops inside monitor
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
    it "preferred_github_remote returns nil when no candidates" do
      allow(described_class).to receive(:remotes_with_urls).and_return({})
      expect(described_class.preferred_github_remote).to be_nil
    end

    it "preferred_github_remote prefers explicit then origin" do
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
    end

    it "parse_github_owner_repo handles nil and unknown patterns" do
      expect(described_class.parse_github_owner_repo(nil)).to eq([nil, nil])
      expect(described_class.parse_github_owner_repo("ssh://gitlab.com/u/r")).to eq([nil, nil])
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
