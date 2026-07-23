# frozen_string_literal: true

require "kettle/dev/executable_version"

RSpec.describe Kettle::Dev::ExecutableVersion do
  describe ".requested?" do
    it "detects short and bare long version flags" do
      expect(described_class.requested?(["-v"])).to be(true)
      expect(described_class.requested?(["--version"])).to be(true)
    end

    it "preserves long options that consume a version value" do
      expect(described_class.requested?(["--version", "1.2.3"], value_option: true)).to be(false)
      expect(described_class.requested?(["--version=1.2.3"], value_option: true)).to be(false)
      expect(described_class.requested?(["version=1.2.3"], value_option: true)).to be(false)
      expect(described_class.requested?(["--version", "--json"], value_option: true)).to be(true)
    end
  end
end
