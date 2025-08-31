# frozen_string_literal: true

# Shared context to mock Kettle::Dev::ExitAdapter per-example.
# - Included globally from spec_helper.
# - Skips mocking when example metadata includes :real_exit_adapter.
# - Prevents real SystemExit from terminating the spec process by raising
#   MockSystemExit (a StandardError) instead.
RSpec.shared_context "with mocked exit adapter" do
  before do |example|
    # Allow opting out for specs that need the real implementation
    next if example.metadata[:real_exit_adapter]

    # Define non-leaky exception class via stub_const; auto-restored between examples
    stub_const("MockSystemExit", Class.new(StandardError))

    # Stub out abort and exit to raise MockSystemExit with meaningful messages
    allow(Kettle::Dev::ExitAdapter).to receive(:abort) do |msg|
      # Kernel.abort(msg) would print msg to STDERR and then raise SystemExit.
      # Here we just raise a StandardError to keep the process alive.
      raise(MockSystemExit, msg.to_s)
    end

    allow(Kettle::Dev::ExitAdapter).to receive(:exit) do |status = 0|
      # Simulate exit by raising with a message that can be asserted on.
      # The real SystemExit carries a status; in tests that need to assert on
      # the numeric status, use :real_exit_adapter to bypass this stub.
      raise(MockSystemExit, "exit status #{status}")
    end
  end
end
