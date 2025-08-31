# frozen_string_literal: true

# Shared context to mock Kettle::Dev::InputAdapter per-example.
# - Included globally from spec_helper.
# - Skips mocking when example metadata includes :real_input_adapter.
# - Provides a safe default that immediately returns a newline (accept default)
#   or uses TEST_INPUT_DEFAULT when provided.
# - If a spec assigns $stdin = KettleTestInputMachine.new(default: ...), this
#   context will respect that default to ease migration from direct STDIN stubbing.
RSpec.shared_context "with mocked input adapter" do
  before do |example|
    next if example.metadata[:real_input_adapter]

    default = ENV["TEST_INPUT_DEFAULT"]

    if defined?(KettleTestInputMachine) && $stdin.is_a?(KettleTestInputMachine)
      # The helper returns "\n" when default is nil/empty; otherwise ensures a trailing newline
      if $stdin.instance_variable_defined?(:@default)
        d = $stdin.instance_variable_get(:@default)
        default = (d.nil? || d.to_s.empty?) ? "" : d.to_s
      end
    end

    answer = if default.nil?
      "\n"
    else
      s = default.to_s
      s.end_with?("\n") ? s : (s + "\n")
    end

    allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return(answer)
  end
end
