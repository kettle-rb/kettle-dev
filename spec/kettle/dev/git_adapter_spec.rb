# frozen_string_literal: true

require "kettle/dev/git_adapter"

RSpec.describe Kettle::Dev::GitAdapter, :real_git_adapter do
  include_context "with truffleruby 3.1..3.2 skip"
  describe "git operations with git gem present" do
    let(:git_repo) { instance_double(Git::Base) }

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

    it "returns false on exceptions in push" do
      expect(git_repo).to receive(:push).and_raise(StandardError)
      adapter = described_class.new
      expect(adapter.push("origin", "feat")).to be false
    end

    it "returns current_branch and handles error" do
      allow(git_repo).to receive(:current_branch).and_return("main")
      adapter = described_class.new
      expect(adapter.current_branch).to eq("main")
      allow(git_repo).to receive(:current_branch).and_raise(StandardError)
      expect(adapter.current_branch).to be_nil
    end

    it "lists remotes and handles error" do
      remote_a = instance_double(Git::Remote, name: "origin")
      remote_b = instance_double(Git::Remote, name: "github")
      allow(git_repo).to receive(:remotes).and_return([remote_a, remote_b])
      adapter = described_class.new
      expect(adapter.remotes).to eq(["origin", "github"])
      allow(git_repo).to receive(:remotes).and_raise(StandardError)
      expect(adapter.remotes).to eq([])
    end

    it "returns remotes_with_urls and handles error" do
      remote_a = instance_double(Git::Remote, name: "origin", url: "git@github.com:me/repo.git")
      remote_b = instance_double(Git::Remote, name: "github", url: "https://github.com/me/repo.git")
      allow(git_repo).to receive(:remotes).and_return([remote_a, remote_b])
      adapter = described_class.new
      expect(adapter.remotes_with_urls).to eq({
        "origin" => "git@github.com:me/repo.git",
        "github" => "https://github.com/me/repo.git",
      })
      allow(git_repo).to receive(:remotes).and_raise(StandardError)
      expect(adapter.remotes_with_urls).to eq({})
    end

    it "returns remote_url and handles error" do
      remote_a = instance_double(Git::Remote, name: "origin", url: "git@github.com:me/repo.git")
      allow(git_repo).to receive(:remotes).and_return([remote_a])
      adapter = described_class.new
      expect(adapter.remote_url("origin")).to include("github.com")
      allow(git_repo).to receive(:remotes).and_raise(StandardError)
      expect(adapter.remote_url("origin")).to be_nil
    end

    it "checks out a branch and returns false on error" do
      expect(git_repo).to receive(:checkout).with("feat")
      adapter = described_class.new
      expect(adapter.checkout("feat")).to be true
      allow(git_repo).to receive(:checkout).and_raise(StandardError)
      expect(adapter.checkout("feat")).to be false
    end

    it "pulls and returns false on error" do
      expect(git_repo).to receive(:pull).with("origin", "main")
      adapter = described_class.new
      expect(adapter.pull("origin", "main")).to be true
      allow(git_repo).to receive(:pull).and_raise(StandardError)
      expect(adapter.pull("origin", "main")).to be false
    end

    it "fetches with and without ref and returns false on error" do
      expect(git_repo).to receive(:fetch).with("origin", "main")
      adapter = described_class.new
      expect(adapter.fetch("origin", "main")).to be true
      expect(git_repo).to receive(:fetch).with("origin")
      expect(adapter.fetch("origin")).to be true
      allow(git_repo).to receive(:fetch).and_raise(StandardError)
      expect(adapter.fetch("origin", "oops")).to be false
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
