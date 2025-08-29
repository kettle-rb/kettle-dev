# frozen_string_literal: true

RSpec.describe Kettle::Dev::CIHelpers do
  describe "::repo_info parsing" do
    it "parses SSH origin url" do
      allow(Open3).to receive(:capture2).with("git", "config", "--get", "remote.origin.url").and_return(["git@github.com:me/repo.git\n", instance_double(Process::Status, success?: true)])
      expect(described_class.repo_info).to eq(["me", "repo"])
    end

    it "parses HTTPS origin url" do
      allow(Open3).to receive(:capture2).with("git", "config", "--get", "remote.origin.url").and_return(["https://github.com/me/repo\n", instance_double(Process::Status, success?: true)])
      expect(described_class.repo_info).to eq(["me", "repo"])
    end
  end

  describe "::workflows_list exclusions" do
    it "lists workflows and excludes maintenance files" do
      Dir.mktmpdir do |root|
        dir = File.join(root, ".github", "workflows")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "ci.yml"), "name: ci")
        File.write(File.join(dir, "codeql-analysis.yml"), "name: codeql")
        files = described_class.workflows_list(root)
        expect(files).to include("ci.yml")
        expect(files).not_to include("codeql-analysis.yml")
      end
    end
  end

  describe "::gitlab_latest_pipeline enrichment" do
    it "enriches pipeline with detail fields when available" do
      # First call returns list with one pipeline id
      list_body = [{"id" => 42, "status" => "running"}].to_json
      list_resp = instance_double(Net::HTTPSuccess, body: list_body)
      allow(list_resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

      # Second call returns detail with failure_reason, status, and web_url
      det_body = {"id" => 42, "status" => "failed", "web_url" => "https://gitlab.com/me/repo/-/pipelines/42", "failure_reason" => "script_failure"}.to_json
      det_resp = instance_double(Net::HTTPSuccess, body: det_body)
      allow(det_resp).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

      # Net::HTTP.start is called twice; first returns list, second returns detail
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request).with(instance_of(Net::HTTP::Get)).and_return(list_resp)
      http2 = instance_double(Net::HTTP)
      allow(http2).to receive(:request).with(instance_of(Net::HTTP::Get)).and_return(det_resp)

      calls = 0
      allow(Net::HTTP).to receive(:start) do |*_args, **_kwargs, &blk|
        obj = calls.zero? ? http : http2
        calls += 1
        blk.call(obj)
      end

      allow(described_class).to receive(:current_branch).and_return("main")
      result = described_class.gitlab_latest_pipeline(owner: "me", repo: "repo")
      expect(result).to include(
        "id" => 42,
        "status" => "failed",
        "web_url" => "https://gitlab.com/me/repo/-/pipelines/42",
        "failure_reason" => "script_failure",
      )
    end
  end

  describe "CIMonitor.parse_github_owner_repo variations" do
    it "parses SSH and HTTPS URLs" do
      mod = Kettle::Dev::CIMonitor
      expect(mod.parse_github_owner_repo("git@github.com:me/repo.git")).to eq(["me", "repo"])
      expect(mod.parse_github_owner_repo("https://github.com/me/repo")).to eq(["me", "repo"])
    end
  end
end
