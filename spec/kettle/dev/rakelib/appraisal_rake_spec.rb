# frozen_string_literal: true

require "spec_helper"

RSpec.describe "appraisal rake tasks" do # rubocop:disable RSpec/DescribeClass
  include_context "with rake", "appraisal"

  describe "rake appraisal:generate" do
    let(:task_name) { "appraisal:generate" }
    let(:appraisal_env) { {"BUNDLE_GEMFILE" => "Appraisal.root.gemfile"} }
    let(:system_calls) { [] }

    before do
      allow(Bundler).to receive(:with_unbundled_env).and_yield
      allow_any_instance_of(Object).to receive(:system) do |_receiver, *args| # rubocop:disable RSpec/AnyInstance
        system_calls << args
        true
      end
    end

    it "generates appraisal gemfiles in the Appraisal root bundle context" do
      invoke

      expect(system_calls).to eq([
        [appraisal_env, "bundle", "install"],
        [appraisal_env, "bundle", "exec", "appraisal", "generate"]
      ])
    end
  end
end
