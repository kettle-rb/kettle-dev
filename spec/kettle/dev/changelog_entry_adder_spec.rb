# frozen_string_literal: true

RSpec.describe Kettle::Dev::ChangelogEntryAdder, :markly_crispr do
  around do |example|
    Dir.mktmpdir("kettle-dev-changelog-entry-adder-spec") do |root|
      @root = root
      example.run
    end
  end

  it "adds an entry to an existing Unreleased section" do
    write_changelog(<<~MARKDOWN)
      # Changelog

      ## [Unreleased]

      ### Added
      ### Changed
      ### Deprecated
      ### Removed
      ### Fixed
      ### Security

      ## [1.0.0] - 2026-01-01
    MARKDOWN

    result = described_class.new(
      root: @root,
      section: "Changed",
      entry: "Added support for JRuby 10.1 and TruffleRuby 34.0."
    ).run

    expect(result).to eq(:changed)
    expect(read_changelog).to include(<<~MARKDOWN)
      ### Changed

      - Added support for JRuby 10.1 and TruffleRuby 34.0.

      ### Deprecated
    MARKDOWN
  end

  it "does not duplicate an existing exact entry" do
    write_changelog(<<~MARKDOWN)
      # Changelog

      ## [Unreleased]

      ### Added
      ### Changed

      - Existing entry.

      ### Deprecated
      ### Removed
      ### Fixed
      ### Security
    MARKDOWN

    result = described_class.new(root: @root, section: "Changed", entry: "Existing entry.").run

    expect(result).to eq(:unchanged)
    expect(read_changelog.scan("- Existing entry.").size).to eq(1)
  end

  it "fails when the requested section is missing" do
    write_changelog(<<~MARKDOWN)
      # Changelog

      ## [Unreleased]

      ### Added
    MARKDOWN

    adder = described_class.new(root: @root, section: "Changed", entry: "Entry.")

    expect { adder.run }.to raise_error(Kettle::Dev::Error, /expected exactly one ### Changed section/)
  end

  def write_changelog(content)
    File.write(File.join(@root, "CHANGELOG.md"), content)
  end

  def read_changelog
    File.read(File.join(@root, "CHANGELOG.md"))
  end
end
