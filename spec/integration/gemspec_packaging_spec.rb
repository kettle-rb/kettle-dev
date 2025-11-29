# frozen_string_literal: true

require "rubygems"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "kettle-dev gem packaging (example files inclusion)" do
  it "includes all **/*.example and **/.*.example files in the packaged gem, including .junie/guidelines.md.example" do
    # Determine repo root using the public constant
    root = Kettle::Dev::GEM_ROOT

    # Load the gemspec without changing directories
    path = File.join(root, "kettle-dev.gemspec")
    spec = Gem::Specification.load(path)
    expect(spec).not_to be_nil

    packaged = spec.files.map { |p| p.sub(/\A\.\//, "") }.sort

    # Build the expected set: all *.example files in the repo (including dotfiles),
    # excluding common build/output directories not intended to ship.
    flags = File::FNM_DOTMATCH # Tweak glob pattern matching to match dotfiles.
    expected = Dir.glob(File.join(root, "**/*.example"), flags)

    # Normalize and prune directories that should never be packaged
    exclude_prefixes = %w[
      pkg/
      coverage/
      docs/
      tmp_gem/
      results/
      .git/
      .idea/
      .yardoc/
      coverage-*/
    ]
    expected = expected
      .reject { |p| File.directory?(p) }
      .map { |p| p.sub(/^#{Regexp.escape(root)}\/?/, "") }
      .reject { |p| exclude_prefixes.any? { |pre| p.start_with?(pre) } }
      .uniq
      .sort

    # Assert all example files (including dotfile examples) are packaged
    missing = expected - packaged
    expect(missing).to eq([]), "Missing from packaged gem: \n#{missing.join("\n")}"

    # Specifically assert inclusion of the guidelines example under .junie
    expect(packaged).to include(".junie/guidelines.md.example")
  end
end
# rubocop:enable RSpec/DescribeClass
