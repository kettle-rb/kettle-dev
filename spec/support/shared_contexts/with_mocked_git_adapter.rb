# frozen_string_literal: true

# Shared context to mock Kettle::Dev::GitAdapter per-example.
# - Included globally from spec_helper.
# - Provides `let(:git_push_success)` which any example can override to
#   simulate push success/failure.
# - Skips mocking when example metadata includes :real_git_adapter.
RSpec.shared_context "with mocked git adapter" do
  # Default push result; specs can override via:
  #   let(:git_push_success) { false }
  let(:git_push_success) { true }

  before do |example|
    # Allow opting out for specs that need the real implementation
    next if example.metadata[:real_git_adapter]

    # Create a fresh double per example to avoid cross-test leakage
    adapter_double = instance_double(Kettle::Dev::GitAdapter)
    allow(adapter_double).to receive(:push) { |_remote, _branch, **_opts| git_push_success }
    # Support tag pushing via adapter
    allow(adapter_double).to receive(:push_tags) { |_remote| git_push_success }
    # Safe defaults for other methods used by ReleaseCLI
    allow(adapter_double).to receive_messages(
      current_branch: "main",
      remotes: ["origin"],
      remotes_with_urls: {"origin" => "git@github.com:me/repo.git"},
      checkout: true,
      pull: true,
      fetch: true,
    )
    allow(adapter_double).to receive(:remote_url) { |name| (name == "origin") ? "git@github.com:me/repo.git" : nil }

    # Default behavior for generic capture used by ReleaseCLI#git_output
    allow(adapter_double).to receive(:capture) do |args|
      case args.map(&:to_s)
      when ["config", "user.name"]
        ["CI", true]
      when ["config", "user.email"]
        ["ci@example.com", true]
      else
        ["", true]
      end
    end

    allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter_double)
  end
end
