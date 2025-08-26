# frozen_string_literal: true

require "kettle/dev/git_adapter"

RSpec.describe Kettle::Dev::GitAdapter, :real_git_adapter do
  describe "#push with git gem present" do
    let(:git_repo) { instance_double("Git::Base") }

    before do
      # Simulate git gem present by stubbing Git.open from the git gem
      require "git"
      allow(Git).to receive(:open).and_return(git_repo)
    end

    it "pushes to named remote and returns true" do
      expect(git_repo).to receive(:push).with("origin", "feat", force: false)
      adapter = described_class.new
      expect(adapter.push("origin", "feat")).to be true
    end

    it "pushes to default remote when remote is nil" do
      expect(git_repo).to receive(:push).with(nil, "main", force: true)
      adapter = described_class.new
      expect(adapter.push(nil, "main", force: true)).to be true
    end

    it "returns false on exceptions" do
      expect(git_repo).to receive(:push).and_raise(StandardError)
      adapter = described_class.new
      expect(adapter.push("origin", "feat")).to be false
    end
  end

  # With the 'git' gem mandatory, there is no shell fallback.
  describe "#initialize errors" do
    it "raises Kettle::Dev::Error when git gem cannot open repo" do
      require "git"
      allow(Git).to receive(:open).and_raise(StandardError.new("boom"))
      expect { described_class.new }.to raise_error(Kettle::Dev::Error, /Failed to open git repository/)
    end
  end
end
