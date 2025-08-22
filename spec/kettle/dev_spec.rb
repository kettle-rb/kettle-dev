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
      block_is_expected.to not_raise_error &
        change {
          Rake.application.options.rakelib
        }.from(["rakelib"])
          .to(
            include(
              "rakelib",
              %r{rubocop/ruby\d_\d/rakelib},
              %r{kettle/dev/rakelib},
            ),
          )
    end
  end
end
