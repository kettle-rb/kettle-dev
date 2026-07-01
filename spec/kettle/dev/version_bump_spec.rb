# frozen_string_literal: true

RSpec.describe Kettle::Dev::VersionBump, :check_output, :prism_only do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  ensure
    Kettle::Dev::GemSpecReader.clear_cache!
  end

  it "resolves relative bump targets from a supplied current version" do
    expect(described_class.resolve_target_version("patch", "1.2.3")).to eq("1.2.4")
    expect(described_class.resolve_target_version("minor", "1.2.3")).to eq("1.3.0")
    expect(described_class.resolve_target_version("major", "1.2.3")).to eq("2.0.0")
    expect(described_class.resolve_target_version("pre", "1.2.3.rc9")).to eq("1.2.3.rd0")
  end

  it "collects version file and literal gemspec version edits without writing" do
    version_file, gemspec_path = write_project(version: "1.2.3")

    bump = described_class.new(root: @root, target_version: "patch")
    edits = bump.edits

    expect(bump.current_version).to eq("1.2.3")
    expect(bump.target_version).to eq("1.2.4")
    expect(edits.map { |edit| edit.fetch(:path) }).to contain_exactly(version_file, gemspec_path)
    expect(File.read(version_file)).to include('VERSION = "1.2.3"')
    expect(File.read(gemspec_path)).to include('spec.version = "1.2.3"')
  end

  it "writes collected edits through the shared writer" do
    version_file, gemspec_path = write_project(version: "1.2.3")
    bump = described_class.new(root: @root, target_version: "1.2.4")

    described_class.write_edits(bump.edits)

    expect(File.read(version_file)).to include('VERSION = "1.2.4"')
    expect(File.read(gemspec_path)).to include('spec.version = "1.2.4"')
  end

  def write_project(version:)
    FileUtils.mkdir_p(File.join(@root, "lib", "demo"))
    version_file = File.join(@root, "lib", "demo", "version.rb")
    File.write(version_file, <<~RUBY)
      module Demo
        VERSION = "#{version}"
      end
    RUBY
    gemspec_path = File.join(@root, "demo.gemspec")
    File.write(gemspec_path, <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = "demo"
        spec.version = "#{version}"
      end
    RUBY
    Kettle::Dev::GemSpecReader.clear_cache!
    [version_file, gemspec_path]
  end
end
