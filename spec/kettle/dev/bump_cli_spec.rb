# frozen_string_literal: true

RSpec.describe Kettle::Dev::BumpCLI, :check_output, :prism_only do
  def with_project(version: "1.2.3", gemspec_version: version)
    begin
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "demo"))
        version_file = File.join(root, "lib", "demo", "version.rb")
        File.write(version_file, <<~RUBY)
          module Demo
            VERSION = "#{version}"
          end
        RUBY
        gemspec_path = File.join(root, "demo.gemspec")
        File.write(gemspec_path, <<~RUBY)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "#{gemspec_version}"
          end
        RUBY
        Kettle::Dev::GemSpecReader.clear_cache!
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        yield root, version_file, gemspec_path
      end
    ensure
      Kettle::Dev::GemSpecReader.clear_cache!
    end
  end

  it "bumps patch versions and writes version files by default" do
    with_project do |_root, version_file, gemspec_path|
      status = described_class.new(["patch"]).run!

      expect(status).to eq(0)
      expect(File.read(version_file)).to include('VERSION = "1.2.4"')
      expect(File.read(gemspec_path)).to include('spec.version = "1.2.4"')
    end
  end

  it "supports exact target versions" do
    with_project do |_root, version_file, gemspec_path|
      status = described_class.new(["2.0.0"]).run!

      expect(status).to eq(0)
      expect(File.read(version_file)).to include('VERSION = "2.0.0"')
      expect(File.read(gemspec_path)).to include('spec.version = "2.0.0"')
    end
  end

  it "prints planned changes without writing in dry-run mode" do
    with_project do |_root, version_file, gemspec_path|
      expect do
        expect(described_class.new(["minor", "--dry-run"]).run!).to eq(0)
      end.to output(/would update .*version\.rb.*would update .*demo\.gemspec/m).to_stdout

      expect(File.read(version_file)).to include('VERSION = "1.2.3"')
      expect(File.read(gemspec_path)).to include('spec.version = "1.2.3"')
    end
  end

  it "returns non-zero in check mode when changes are needed" do
    with_project do
      expect do
        expect(described_class.new(["major", "--check"]).run!).to eq(1)
      end.to output(/kettle-bump: 1\.2\.3 -> 2\.0\.0/).to_stdout
    end
  end

  it "enforces --from before writing" do
    with_project do
      expect { described_class.new(["patch", "--from", "1.2.2"]).run! }
        .to raise_error(Kettle::Dev::Error, /not --from 1\.2\.2/)
    end
  end

  it "leaves dynamic gemspec versions untouched" do
    with_project do |_root, version_file, gemspec_path|
      File.write(gemspec_path, <<~RUBY)
        gem_version = "1.2.3"
        Gem::Specification.new do |spec|
          spec.name = "demo"
          spec.version = gem_version
        end
      RUBY
      Kettle::Dev::GemSpecReader.clear_cache!

      expect(described_class.new(["patch"]).run!).to eq(0)
      expect(File.read(version_file)).to include('VERSION = "1.2.4"')
      expect(File.read(gemspec_path)).to include("spec.version = gem_version")
    end
  end

  it "rejects non-numeric bump keywords for prerelease versions" do
    with_project(version: "1.2.3.pre") do
      expect { described_class.new(["patch"]).run! }
        .to raise_error(Kettle::Dev::Error, /cannot patch-bump non-numeric version/)
    end
  end
end
