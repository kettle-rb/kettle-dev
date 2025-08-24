# frozen_string_literal: true

require "tmpdir"
require "fileutils"

require "kettle/dev/ci_helpers"

RSpec.describe Kettle::Dev::CIHelpers do
  include_context "with stubbed env"

  describe "::<module_function> availability" do
    it "responds to expected methods" do
      %i[
        project_root
        repo_info
        current_branch
        workflows_list
        exclusions
        latest_run
        success?
        failed?
        default_token
      ].each do |m|
        expect(described_class).to respond_to(m)
      end
    end
  end

  describe "::project_root" do
    it "uses Rake.application.original_dir when available" do
      original = Dir.pwd
      fake_root = Dir.mktmpdir("proj")
      begin
        rake = double("RakeApp", original_dir: fake_root)
        stub_const("Rake", double("Rake", application: rake))
        expect(described_class.project_root).to eq(fake_root)
      ensure
        Dir.chdir(original)
        FileUtils.remove_entry(fake_root)
      end
    end

    it "falls back to Dir.pwd when Rake is not available" do
      hide_const("Rake") if defined?(Rake)
      expect(described_class.project_root).to eq(Dir.pwd)
    end
  end

  describe "::repo_info" do
    it "parses SSH origin URL" do
      allow(Open3).to receive(:capture2).and_return([
        "git@github.com:owner/repo.git\n",
        instance_double(Process::Status, success?: true),
      ])
      expect(described_class.repo_info).to eq(["owner", "repo"])
    end

    it "parses HTTPS origin URL" do
      allow(Open3).to receive(:capture2).and_return([
        "https://github.com/owner/repo\n",
        instance_double(Process::Status, success?: true),
      ])
      expect(described_class.repo_info).to eq(["owner", "repo"])
    end

    it "returns nil when git command fails" do
      allow(Open3).to receive(:capture2).and_return(["", instance_double(Process::Status, success?: false)])
      expect(described_class.repo_info).to be_nil
    end

    it "returns nil when origin is non-GitHub" do
      allow(Open3).to receive(:capture2).and_return([
        "git@gitlab.com:owner/repo.git\n",
        instance_double(Process::Status, success?: true),
      ])
      expect(described_class.repo_info).to be_nil
    end
  end

  describe "::current_branch" do
    it "returns branch when command succeeds" do
      allow(Open3).to receive(:capture2).and_return([
        "main\n",
        instance_double(Process::Status, success?: true),
      ])
      expect(described_class.current_branch).to eq("main")
    end

    it "returns nil on failure" do
      allow(Open3).to receive(:capture2).and_return(["", instance_double(Process::Status, success?: false)])
      expect(described_class.current_branch).to be_nil
    end
  end

  describe "::workflows_list" do
    it "lists .yml and .yaml files and excludes maintenance ones" do
      Dir.mktmpdir("root") do |root|
        dir = File.join(root, ".github", "workflows")
        FileUtils.mkdir_p(dir)
        %w[ci.yml style.yaml codeql-analysis.yml].each do |f|
          File.write(File.join(dir, f), "name: test\n")
        end
        list = described_class.workflows_list(root)
        expect(list).to include("ci.yml", "style.yaml")
        expect(list).not_to include("codeql-analysis.yml")
      end
    end

    it "returns [] when dir missing" do
      Dir.mktmpdir("root") do |root|
        expect(described_class.workflows_list(root)).to eq([])
      end
    end
  end

  describe "::latest_run / ::success? / ::failed?" do
    let(:owner) { "owner" }
    let(:repo) { "repo" }
    let(:workflow) { "ci.yml" }
    let(:branch) { "main" }

    before do
      allow(described_class).to receive(:current_branch).and_return(branch)
    end

    def http_response(body:, code: "200")
      instance_double(Net::HTTPOK, is_a?: true, body: body, code: code)
    end

    def stub_http_capture_authorization(body:)
      captured = {auth: :unset}
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |req|
        captured[:auth] = req["Authorization"]
        http_response(body: JSON.dump(body))
      end
      allow(Net::HTTP).to receive(:start).and_yield(http)
      captured
    end

    it "returns hash for successful API with a run" do
      data = {"workflow_runs" => [{"status" => "completed", "conclusion" => "success", "html_url" => "https://x/y", "id" => 1}]}
      allow(Net::HTTP).to receive(:start).and_return(http_response(body: JSON.dump(data)))
      run = described_class.latest_run(owner: owner, repo: repo, workflow_file: workflow, branch: branch)
      expect(run).to include("status" => "completed", "conclusion" => "success")
      expect(described_class.success?(run)).to be(true)
      expect(described_class.failed?(run)).to be(false)
    end

    it "returns nil when API returns no runs" do
      data = {"workflow_runs" => []}
      allow(Net::HTTP).to receive(:start).and_return(http_response(body: JSON.dump(data)))
      expect(described_class.latest_run(owner: owner, repo: repo, workflow_file: workflow, branch: branch)).to be_nil
    end

    it "returns nil when API returns no workflow_runs key" do
      data = {"something_else" => []}
      allow(Net::HTTP).to receive(:start).and_return(http_response(body: JSON.dump(data)))
      expect(described_class.latest_run(owner: owner, repo: repo, workflow_file: workflow, branch: branch)).to be_nil
    end

    it "returns nil on HTTP failure" do
      bad = instance_double(Net::HTTPBadRequest, is_a?: false, code: "400", body: "")
      allow(Net::HTTP).to receive(:start).and_return(bad)
      expect(described_class.latest_run(owner: owner, repo: repo, workflow_file: workflow, branch: branch)).to be_nil
    end

    it "returns nil when owner/repo missing" do
      expect(described_class.latest_run(owner: nil, repo: repo, workflow_file: workflow, branch: branch)).to be_nil
    end

    it "returns nil when no branch available" do
      allow(described_class).to receive(:current_branch).and_return(nil)
      expect(described_class.latest_run(owner: owner, repo: repo, workflow_file: workflow)).to be_nil
    end

    it "does not set Authorization header when token is empty" do
      data = {"workflow_runs" => [{"status" => "queued", "conclusion" => nil, "html_url" => "https://x/y", "id" => 2}]}
      cap = stub_http_capture_authorization(body: data)
      described_class.latest_run(owner: owner, repo: repo, workflow_file: workflow, branch: branch, token: "")
      expect(cap[:auth]).to be_nil
    end

    it "sets Authorization header when token provided" do
      data = {"workflow_runs" => [{"status" => "completed", "conclusion" => "success", "html_url" => "https://x/y", "id" => 3}]}
      cap = stub_http_capture_authorization(body: data)
      described_class.latest_run(owner: owner, repo: repo, workflow_file: workflow, branch: branch, token: "SECRET")
      expect(cap[:auth]).to eq("token SECRET")
    end

    it "failed? is true for completed non-success" do
      run = {"status" => "completed", "conclusion" => "failure"}
      expect(described_class.failed?(run)).to be(true)
    end

    it "success? returns false for nil run" do
      expect(described_class).not_to be_success(nil)
    end

    it "failed? returns false for nil run" do
      expect(described_class).not_to be_failed(nil)
    end

    it "success? returns false when conclusion is nil" do
      run = {"status" => "completed", "conclusion" => nil}
      expect(described_class).not_to be_success(run)
    end

    it "failed? returns false when conclusion is nil" do
      run = {"status" => "completed", "conclusion" => nil}
      expect(described_class).not_to be_failed(run)
    end

    it "returns nil when an exception occurs (rescued)" do
      allow(Net::HTTP).to receive(:start).and_raise(StandardError.new("boom"))
      expect(
        described_class.latest_run(owner: owner, repo: repo, workflow_file: workflow, branch: branch),
      ).to be_nil
    end
  end

  describe "::default_token" do
    include_context "with stubbed env"

    it "prefers GITHUB_TOKEN then GH_TOKEN" do
      stub_env("GITHUB_TOKEN" => "aaa", "GH_TOKEN" => "bbb")
      expect(described_class.default_token).to eq("aaa")
      stub_env("GITHUB_TOKEN" => nil, "GH_TOKEN" => "bbb")
      expect(described_class.default_token).to eq("bbb")
      stub_env("GITHUB_TOKEN" => nil, "GH_TOKEN" => nil)
      expect(described_class.default_token).to be_nil
    end
  end

  # --- New: GitLab helpers ---
  describe "GitLab helpers" do
    describe "::origin_url" do
      it "returns origin url when config succeeds" do
        allow(Open3).to receive(:capture2).and_return([
          "git@gitlab.com:owner/repo.git\n",
          instance_double(Process::Status, success?: true),
        ])
        expect(described_class.origin_url).to eq("git@gitlab.com:owner/repo.git")
      end

      it "returns nil when config fails" do
        allow(Open3).to receive(:capture2).and_return(["", instance_double(Process::Status, success?: false)])
        expect(described_class.origin_url).to be_nil
      end
    end

    describe "::repo_info_gitlab" do
      it "parses SSH origin URL" do
        allow(described_class).to receive(:origin_url).and_return("git@gitlab.com:group/proj.git")
        expect(described_class.repo_info_gitlab).to eq(["group", "proj"])
      end

      it "parses HTTPS origin URL" do
        allow(described_class).to receive(:origin_url).and_return("https://gitlab.com/group/proj")
        expect(described_class.repo_info_gitlab).to eq(["group", "proj"])
      end

      it "returns nil when origin is not gitlab" do
        allow(described_class).to receive(:origin_url).and_return("git@github.com:owner/repo.git")
        expect(described_class.repo_info_gitlab).to be_nil
      end
    end

    describe "::default_gitlab_token" do
      it "uses GITLAB_TOKEN when present" do
        stub_env("GITLAB_TOKEN" => "ggg", "GL_TOKEN" => "lll")
        expect(described_class.default_gitlab_token).to eq("ggg")
      end

      it "falls back to GL_TOKEN when GITLAB_TOKEN missing" do
        stub_env("GITLAB_TOKEN" => nil, "GL_TOKEN" => "lll")
        expect(described_class.default_gitlab_token).to eq("lll")
      end

      it "returns nil when neither token is present" do
        stub_env("GITLAB_TOKEN" => nil, "GL_TOKEN" => nil)
        expect(described_class.default_gitlab_token).to be_nil
      end
    end

    describe "::gitlab_latest_pipeline / ::gitlab_success? / ::gitlab_failed?" do
      let(:owner) { "grp" }
      let(:repo) { "proj" }
      let(:branch) { "main" }

      before do
        allow(described_class).to receive(:current_branch).and_return(branch)
      end

      def gitlab_http_ok(body:)
        instance_double(Net::HTTPOK, is_a?: true, body: JSON.dump(body))
      end

      def stub_http_capture_private_token(body:)
        captured = {token: :unset}
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) do |req|
          captured[:token] = req["PRIVATE-TOKEN"]
          gitlab_http_ok(body: body)
        end
        allow(Net::HTTP).to receive(:start).and_yield(http)
        captured
      end

      it "returns hash for successful API with a pipeline" do
        data = [{"status" => "success", "web_url" => "https://gitlab.com/x/y/-/pipelines/1", "id" => 1}]
        allow(Net::HTTP).to receive(:start).and_return(gitlab_http_ok(body: data))
        pipe = described_class.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch)
        expect(pipe).to include("status" => "success", "id" => 1)
      end

      it "classifies the returned pipeline as success" do
        data = [{"status" => "success", "web_url" => "https://gitlab.com/x/y/-/pipelines/1", "id" => 1}]
        allow(Net::HTTP).to receive(:start).and_return(gitlab_http_ok(body: data))
        pipe = described_class.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch)
        expect(described_class.gitlab_success?(pipe)).to be(true)
      end

      it "does not classify the returned pipeline as failed" do
        data = [{"status" => "success", "web_url" => "https://gitlab.com/x/y/-/pipelines/1", "id" => 1}]
        allow(Net::HTTP).to receive(:start).and_return(gitlab_http_ok(body: data))
        pipe = described_class.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch)
        expect(described_class.gitlab_failed?(pipe)).to be(false)
      end

      it "returns nil when API returns empty array" do
        data = []
        allow(Net::HTTP).to receive(:start).and_return(gitlab_http_ok(body: data))
        expect(described_class.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch)).to be_nil
      end

      it "returns nil on HTTP failure" do
        bad = instance_double(Net::HTTPBadRequest, is_a?: false, code: "400", body: "")
        allow(Net::HTTP).to receive(:start).and_return(bad)
        expect(described_class.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch)).to be_nil
      end

      it "returns nil when owner/repo missing" do
        expect(described_class.gitlab_latest_pipeline(owner: nil, repo: repo, branch: branch)).to be_nil
      end

      it "returns nil when no branch available" do
        allow(described_class).to receive(:current_branch).and_return(nil)
        expect(described_class.gitlab_latest_pipeline(owner: owner, repo: repo)).to be_nil
      end

      it "does not set PRIVATE-TOKEN header when token is empty" do
        data = [{"status" => "pending", "web_url" => "https://x/y", "id" => 2}]
        cap = stub_http_capture_private_token(body: data)
        described_class.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch, token: "")
        expect(cap[:token]).to be_nil
      end

      it "sets PRIVATE-TOKEN header when token provided" do
        data = [{"status" => "success", "web_url" => "https://x/y", "id" => 3}]
        cap = stub_http_capture_private_token(body: data)
        described_class.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch, token: "SEKRET")
        expect(cap[:token]).to eq("SEKRET")
      end

      it "gitlab_success? returns true for status=success" do
        expect(described_class.gitlab_success?({"status" => "success"})).to be(true)
      end

      it "gitlab_success? returns false for non-success status" do
        expect(described_class.gitlab_success?({"status" => "failed"})).to be(false)
      end

      it "gitlab_success? returns false for nil" do
        expect(described_class).not_to be_gitlab_success(nil)
      end

      it "gitlab_failed? returns true for status=failed" do
        expect(described_class.gitlab_failed?({"status" => "failed"})).to be(true)
      end

      it "gitlab_failed? returns false for non-failed status" do
        expect(described_class.gitlab_failed?({"status" => "success"})).to be(false)
      end

      it "gitlab_failed? returns false for nil" do
        expect(described_class).not_to be_gitlab_failed(nil)
      end

      it "returns nil when an exception occurs (rescued)" do
        allow(Net::HTTP).to receive(:start).and_raise(StandardError.new("boom"))
        expect(
          described_class.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch),
        ).to be_nil
      end
    end
  end
end
