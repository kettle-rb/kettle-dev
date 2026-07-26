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

  describe ".header" do
    it "formats executable headers consistently" do
      expect(described_class.header("kettle-example")).to eq("== kettle-example v#{Kettle::Dev::Version::VERSION} ==")
    end
  end

  describe ".print_header" do
    it "does not print by default" do
      expect { described_class.print_header("kettle-example", []) }.not_to output.to_stdout
    end

    it "prints when verbose output is requested" do
      argv = ["--verbose"]

      expect { described_class.print_header("kettle-example", argv) }
        .to output("== kettle-example v#{Kettle::Dev::Version::VERSION} ==\n").to_stdout
      expect(argv).to eq([])
    end
  end
end
