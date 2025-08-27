# frozen_string_literal: true

require "kettle/dev/git_adapter"

RSpec.describe Kettle::Dev::GitAdapter, :real_git_adapter do
  include_context "with truffleruby 3.1..3.2 skip"
  describe "git operations with git gem present" do
    let(:git_repo) { double("Git::Base") }

    it "pushes to named remote and returns true" do
      expect(git_repo).to receive(:push).with("origin", "feat", force: false)
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.push("origin", "feat")).to be true
    end

    it "pushes to default remote when remote is nil" do
      expect(git_repo).to receive(:push).with(nil, "main", force: true)
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.push(nil, "main", force: true)).to be true
    end

    it "returns false on exceptions in push" do
      expect(git_repo).to receive(:push).and_raise(StandardError)
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.push("origin", "feat")).to be false
    end

    it "returns current_branch and handles error" do
      allow(git_repo).to receive(:current_branch).and_return("main")
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.current_branch).to eq("main")
      allow(git_repo).to receive(:current_branch).and_raise(StandardError)
      expect(adapter.current_branch).to be_nil
    end

    it "lists remotes and handles error" do
      remote_a = double("Git::Remote", name: "origin")
      remote_b = double("Git::Remote", name: "github")
      allow(git_repo).to receive(:remotes).and_return([remote_a, remote_b])
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.remotes).to eq(["origin", "github"])
      allow(git_repo).to receive(:remotes).and_raise(StandardError)
      expect(adapter.remotes).to eq([])
    end

    it "returns remotes_with_urls and handles error" do
      remote_a = double("Git::Remote", name: "origin", url: "git@github.com:me/repo.git")
      remote_b = double("Git::Remote", name: "github", url: "https://github.com/me/repo.git")
      allow(git_repo).to receive(:remotes).and_return([remote_a, remote_b])
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.remotes_with_urls).to eq({
        "origin" => "git@github.com:me/repo.git",
        "github" => "https://github.com/me/repo.git",
      })
      allow(git_repo).to receive(:remotes).and_raise(StandardError)
      expect(adapter.remotes_with_urls).to eq({})
    end

    it "returns remote_url and handles error" do
      remote_a = double("Git::Remote", name: "origin", url: "git@github.com:me/repo.git")
      allow(git_repo).to receive(:remotes).and_return([remote_a])
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.remote_url("origin")).to include("github.com")
      allow(git_repo).to receive(:remotes).and_raise(StandardError)
      expect(adapter.remote_url("origin")).to be_nil
    end

    it "checks out a branch and returns false on error" do
      expect(git_repo).to receive(:checkout).with("feat")
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.checkout("feat")).to be true
      allow(git_repo).to receive(:checkout).and_raise(StandardError)
      expect(adapter.checkout("feat")).to be false
    end

    it "pulls and returns false on error" do
      expect(git_repo).to receive(:pull).with("origin", "main")
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.pull("origin", "main")).to be true
      allow(git_repo).to receive(:pull).and_raise(StandardError)
      expect(adapter.pull("origin", "main")).to be false
    end

    it "fetches with and without ref and returns false on error" do
      expect(git_repo).to receive(:fetch).with("origin", "main")
      adapter = described_class.new
      adapter.instance_variable_set(:@backend, :gem)
      adapter.instance_variable_set(:@git, git_repo)
      expect(adapter.fetch("origin", "main")).to be true
      expect(git_repo).to receive(:fetch).with("origin")
      expect(adapter.fetch("origin")).to be true
      allow(git_repo).to receive(:fetch).and_raise(StandardError)
      expect(adapter.fetch("origin", "oops")).to be false
    end
  end

  describe "CLI fallback when git gem is missing" do
    let(:status_ok) { instance_double(Process::Status, success?: true) }

    before do
      # Make `require "git"` raise, to trigger CLI backend
      allow(Kernel).to receive(:require).with("git").and_raise(LoadError)
    end

    it "pushes using system git with remote and without" do
      adapter = described_class.new
      expect(adapter).to receive(:system).with("git", "push", "origin", "feat").and_return(true)
      expect(adapter.push("origin", "feat")).to be true
      expect(adapter).to receive(:system).with("git", "push").and_return(true)
      expect(adapter.push(nil, "feat")).to be true
    end

    it "pushes with --force when requested" do
      adapter = described_class.new
      expect(adapter).to receive(:system).with("git", "push", "--force", "origin", "main").and_return(true)
      expect(adapter.push("origin", "main", force: true)).to be true
      expect(adapter).to receive(:system).with("git", "push", "--force").and_return(true)
      expect(adapter.push(nil, "main", force: true)).to be true
    end

    it "returns current branch via rev-parse" do
      expect(Open3).to receive(:capture2).with("git", "rev-parse", "--abbrev-ref", "HEAD").and_return(["main\n", status_ok])
      adapter = described_class.new
      expect(adapter.current_branch).to eq("main")
    end

    it "lists remotes from `git remote`" do
      expect(Open3).to receive(:capture2).with("git", "remote").and_return(["origin\ngithub\n", status_ok])
      adapter = described_class.new
      expect(adapter.remotes).to eq(["origin", "github"])
    end

    it "parses remotes_with_urls from `git remote -v`" do
      lines = <<~OUT
        origin https://github.com/me/repo.git (fetch)
        origin https://github.com/me/repo.git (push)
        gl     https://gitlab.com/me/repo (fetch)
        gl     https://gitlab.com/me/repo (push)
      OUT
      expect(Open3).to receive(:capture2).with("git", "remote", "-v").and_return([lines, status_ok])
      adapter = described_class.new
      expect(adapter.remotes_with_urls).to include(
        "origin" => "https://github.com/me/repo.git",
        "gl" => "https://gitlab.com/me/repo",
      )
    end

    it "gets remote_url via git config" do
      expect(Open3).to receive(:capture2).with("git", "config", "--get", "remote.origin.url").and_return(["git@github.com:me/repo.git\n", status_ok])
      adapter = described_class.new
      expect(adapter.remote_url("origin")).to include("github.com")
    end

    it "checkout/pull/fetch use system git" do
      adapter = described_class.new
      expect(adapter).to receive(:system).with("git", "checkout", "main").and_return(true)
      expect(adapter.checkout("main")).to be true
      expect(adapter).to receive(:system).with("git", "pull", "origin", "main").and_return(true)
      expect(adapter.pull("origin", "main")).to be true
      expect(adapter).to receive(:system).with("git", "fetch", "origin", "main").and_return(true)
      expect(adapter.fetch("origin", "main")).to be true
      expect(adapter).to receive(:system).with("git", "fetch", "origin").and_return(true)
      expect(adapter.fetch("origin")).to be true
    end
  end
end
