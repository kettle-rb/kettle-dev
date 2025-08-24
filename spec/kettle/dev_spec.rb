# frozen_string_literal: true

require "rake"

RSpec.describe Kettle::Dev do
  describe described_class::Error do
    it "is a standard error" do
      expect { raise described_class }.to raise_error(StandardError)
    end
  end

  describe "::install_tasks" do
    subject(:install_tasks) { described_class.install_tasks }

    it "adds rubocop/rubyX_X/rakelib to Rake application's rakelib" do
      rakelibs = ["rakelib"]
      # rakelibs.push(%r{rubocop/ruby\d_\d/rakelib}) # This will only be present on the style CI workflow.
      rakelibs.push(%r{kettle/dev/rakelib})

      block_is_expected.to not_raise_error &
        change {
          Rake.application.options.rakelib
        }.from(["rakelib"]).to(include(rakelibs))
    end
  end
end
