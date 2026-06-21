# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ci rake tasks" do # rubocop:disable RSpec/DescribeClass
  include_context "with rake", "ci"

  describe "rake ci:act" do
    let(:task_name) { "ci:act" }
    let(:task_args) { ["locked_deps"] }

    it "delegates to the CI task object" do
      allow(Kettle::Dev::Tasks::CITask).to receive(:act)

      invoke

      expect(Kettle::Dev::Tasks::CITask).to have_received(:act).with("locked_deps")
    end
  end
end
