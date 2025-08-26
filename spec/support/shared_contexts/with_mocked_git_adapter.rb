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

  before(:each) do |example|
    # Allow opting out for specs that need the real implementation
    next if example.metadata[:real_git_adapter]

    # Ensure the class is loaded so we can stub it
    require "kettle/dev/git_adapter"

    # Create a fresh double per example to avoid cross-test leakage
    adapter_double = instance_double("Kettle::Dev::GitAdapter")
    allow(adapter_double).to receive(:push) { |_remote, _branch, **_opts| git_push_success }

    allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter_double)
  end
end
