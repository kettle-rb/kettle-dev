# frozen_string_literal: true

# Shared context to mock Kettle::Dev::ReleaseCLI.run_cmd! per-example.
# - Included globally from spec_helper.
# - Provides `let(:release_rake_success)` which any example can override to
#   simulate push success/failure.
# - Skips mocking when example metadata includes :real_release_rake.
RSpec.shared_context "with stubbed release rake" do
  # Default push result; specs can override via:
  #   let(:release_rake_success) { false }
  let(:release_rake_success) { true }

  before do |example|
    # Allow opting out for specs that need the real implementation
    next if example.metadata[:real_release_rake]

    # Only stub the exact command "bundle exec rake release" to a no-op, forwarding others to the original method.
    allow(Kettle::Dev::ReleaseCLI).to receive(:run_cmd!).and_wrap_original do |orig, cmd|
      if cmd =~ /.*rake\s+release\b/
        # no-op: pretend it succeeded / failed as requested by the spec
        release_rake_success
      else
        orig.call(cmd)
      end
    end
  end
end
