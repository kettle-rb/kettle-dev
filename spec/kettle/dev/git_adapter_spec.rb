# frozen_string_literal: true

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
      urls = adapter.remotes_with_urls
      # Be flexible: accept SSH or HTTPS; only assert the domains are present
      expect(urls.fetch("origin")).to include("github.com")
      expect(urls.fetch("gl")).to include("gitlab.com")
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

  describe "ENV override to disable git gem" do
    include_context "with stubbed env"

    # rubocop:disable RSpec/LeakyConstantDeclaration
    # Ensure verifying doubles work even when the git gem is not installed.
    unless defined?(Git)
      module ::Git; end
    end
    unless defined?(Git::Base)
      class ::Git::Base; end
    end
    # rubocop:enable RSpec/LeakyConstantDeclaration

    let(:git_repo) { instance_double("Git::Base") } # rubocop:disable RSpec/VerifiedDoubleReference
    # Detect whether the 'git' gem is actually available in this environment.
    # We attempt to require it; if it is not installed, we'll skip tests that
    # need the constant ::Git to exist.
    let(:git_gem_available) do
      begin
        require "git"
        true
      rescue LoadError
        false
      end
    end

    it "uses gem backend when available and no override" do
      skip "git gem not available in this environment" unless git_gem_available
      # Simulate git gem available
      allow(Kernel).to receive(:require).with("git").and_return(true)
      allow(Git).to receive(:open).and_return(git_repo)
      allow(git_repo).to receive(:push).and_return(true)
      adapter = described_class.new
      expect(adapter.push("origin", "feat")).to be true
      expect(git_repo).to have_received(:push).with("origin", "feat", force: false)
    end

    it "forces CLI backend when KETTLE_DEV_DISABLE_GIT_GEM is truthy even if gem is available" do
      stub_env("KETTLE_DEV_DISABLE_GIT_GEM" => "true")
      # Even if require succeeds, we must not use ::Git.open in this mode.
      allow(Kernel).to receive(:require).with("git").and_return(true)
      allow(Git).to receive(:open) if defined?(Git)
      adapter = described_class.new
      allow(adapter).to receive(:system).and_return(true)
      expect(adapter.push("origin", "feat")).to be true
      expect(adapter).to have_received(:system).with("git", "push", "origin", "feat")
    end
  end
end


# Consolidated from git_adapter_clean_spec.rb: clean? behavior
RSpec.describe Kettle::Dev::GitAdapter, :real_git_adapter do
  describe "#clean?" do
    context "when using git gem backend" do
      let(:git_repo) { double("Git::Base") }
      let(:status_obj) { double("Git::Status", changed: {}, added: {}, deleted: {}, untracked: {}) }

      it "returns true when status has no changes" do
        adapter = described_class.new
        adapter.instance_variable_set(:@backend, :gem)
        adapter.instance_variable_set(:@git, git_repo)
        expect(git_repo).to receive(:status).and_return(status_obj)
        expect(adapter.clean?).to be true
      end

      it "returns false when there are any changes" do
        dirty_status = double("Git::Status", changed: {"a" => "M"}, added: {}, deleted: {}, untracked: {})
        adapter = described_class.new
        adapter.instance_variable_set(:@backend, :gem)
        adapter.instance_variable_set(:@git, git_repo)
        expect(git_repo).to receive(:status).and_return(dirty_status)
        expect(adapter.clean?).to be false
      end

      it "returns false when status raises an error" do
        adapter = described_class.new
        adapter.instance_variable_set(:@backend, :gem)
        adapter.instance_variable_set(:@git, git_repo)
        allow(git_repo).to receive(:status).and_raise(StandardError)
        expect(adapter.clean?).to be false
      end
    end

    context "when using CLI backend" do
      let(:ok) { instance_double(Process::Status, success?: true) }
      let(:fail_status) { instance_double(Process::Status, success?: false) }

      before do
        allow(Kernel).to receive(:require).with("git").and_raise(LoadError)
      end

      it "returns true when porcelain output is empty" do
        expect(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["\n", ok])
        adapter = described_class.new
        expect(adapter.clean?).to be true
      end

      it "returns false when porcelain output has content" do
        expect(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return([" M lib/file.rb\n?? new.rb\n", ok])
        adapter = described_class.new
        expect(adapter.clean?).to be false
      end

      it "returns false when git status fails" do
        expect(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["", fail_status])
        adapter = described_class.new
        expect(adapter.clean?).to be false
      end

      it "returns false on unexpected errors" do
        expect(Open3).to receive(:capture2).and_raise(StandardError)
        adapter = described_class.new
        expect(adapter.clean?).to be false
      end
    end
  end
end
