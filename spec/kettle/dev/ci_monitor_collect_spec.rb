# frozen_string_literal: true

RSpec.describe Kettle::Dev::CIMonitor do
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
end
