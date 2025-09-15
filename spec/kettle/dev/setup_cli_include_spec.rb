# frozen_string_literal: true

RSpec.describe Kettle::Dev::SetupCLI do
  describe "include passthrough" do
    it "run_kettle_install! includes include=... in the rake command" do
      cli = described_class.allocate
      cli.instance_variable_set(:@passthrough, ["include=foo/bar/**"])
      expect(cli).to receive(:sh!).with(a_string_including("bin/rake kettle:dev:install include\\=foo/bar/\\*\\*"))
      cli.send(:run_kettle_install!)
    end
  end
end
