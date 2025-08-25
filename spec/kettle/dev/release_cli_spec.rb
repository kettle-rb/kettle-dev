# frozen_string_literal: true

RSpec.describe Kettle::Dev::ReleaseCLI do
  include_context "with stubbed env"

  let(:ci_helpers) { Kettle::Dev::CIHelpers }

  it "detects version and gem name from a temporary project root" do
    Dir.mktmpdir do |root|
      # Arrange version file
      lib_dir = File.join(root, "lib", "mygem")
      FileUtils.mkdir_p(lib_dir)
      File.write(File.join(lib_dir, "version.rb"), <<~RB)
        module Mygem
          VERSION = "1.2.3"
        end
      RB

      # Arrange gemspec
      File.write(File.join(root, "mygem.gemspec"), <<~G)
        Gem::Specification.new do |spec|
          spec.name = "mygem"
        end
      G

      # Stub project root used by ReleaseCLI
      allow(ci_helpers).to receive(:project_root).and_return(root)

      cli = described_class.new
      ver = cli.send(:detect_version)
      name = cli.send(:detect_gem_name)

      expect(ver).to eq("1.2.3")
      expect(name).to eq("mygem")
    end
  end
end
