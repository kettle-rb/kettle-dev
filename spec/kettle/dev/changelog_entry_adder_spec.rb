# frozen_string_literal: true

RSpec.describe Kettle::Dev::ChangelogEntryAdder do
  around do |example|
    Dir.mktmpdir("kettle-dev-changelog-entry-adder-spec") do |root|
      @root = root
      example.run
    end
  end

  before do
    install_fake_markly_context
    $LOADED_FEATURES << markly_feature unless $LOADED_FEATURES.include?(markly_feature)
  end

  after do
    $LOADED_FEATURES.delete(markly_feature)
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

  it "adds an entry that is already formatted as a changelog bullet" do
    write_changelog(<<~MARKDOWN)
      # Changelog

      ## [Unreleased]

      ### Added

      ### Changed
      ### Deprecated
      ### Removed
      ### Fixed
      ### Security
    MARKDOWN

    result = described_class.new(root: @root, section: "Added", entry: "- Already a bullet.").run

    expect(result).to eq(:changed)
    expect(read_changelog).to include("### Added\n\n- Already a bullet.\n\n### Changed")
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

  it "fails when the changelog entry is empty" do
    expect { described_class.new(root: @root, section: "Changed", entry: "  ") }
      .to raise_error(Kettle::Dev::Error, /changelog entry must not be empty/)
  end

  it "fails when the requested section is unsupported" do
    write_complete_changelog
    adder = described_class.new(root: @root, section: "Invalid", entry: "Entry.")

    expect { adder.run }.to raise_error(Kettle::Dev::Error, /unsupported changelog section "Invalid"/)
  end

  it "fails when the changelog is missing" do
    adder = described_class.new(root: @root, section: "Changed", entry: "Entry.")

    expect { adder.run }.to raise_error(Kettle::Dev::Error, /missing CHANGELOG\.md/)
  end

  it "fails when there is not exactly one Unreleased section" do
    write_changelog(<<~MARKDOWN)
      # Changelog

      ## [Unreleased]
      ### Changed

      ## [Unreleased]
      ### Changed
    MARKDOWN

    adder = described_class.new(root: @root, section: "Changed", entry: "Entry.")

    expect { adder.run }.to raise_error(Kettle::Dev::Error, /expected exactly one ## \[Unreleased\] section/)
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

  it "wraps the Markly CRISPR load error in a kettle-dev error" do
    $LOADED_FEATURES.delete(markly_feature)
    adder = described_class.new(root: @root, section: "Changed", entry: "Entry.")
    adder.define_singleton_method(:require) do |name|
      raise LoadError, "cannot load markly" if name == "ast/crispr/markdown/markly"

      super(name)
    end

    expect { adder.send(:require_markly_crispr!) }
      .to raise_error(Kettle::Dev::Error, /requires ast-crispr-markdown-markly/)
  end

  def install_fake_markly_context
    ast = Module.new
    crispr = Module.new
    markdown = Module.new
    markly = Module.new

    ast.const_set(:Crispr, crispr)
    crispr.const_set(:Markdown, markdown)
    markdown.const_set(:Markly, markly)
    stub_const("Ast", ast)

    allow(markly).to receive(:document_context) do |content:, **|
      double("FakeDocumentContext", structural_owners: fake_heading_sections(content))
    end
  end

  def fake_location_class
    @fake_location_class ||= Struct.new(:start_line, :end_line)
  end

  def fake_heading_class
    @fake_heading_class ||= Struct.new(:heading_source, :heading_text, :level, :location)
  end

  def markly_feature
    "ast/crispr/markdown/markly.rb"
  end

  def fake_heading_sections(content)
    heading_rows = content.lines.each_with_index.each_with_object([]) do |(line, index), rows|
      heading_level = line.each_char.take_while { |char| char == "#" }.length
      next rows if heading_level.zero? || line[heading_level] != " "

      rows << [index + 1, heading_level, line.strip, line[(heading_level + 1)..-1].to_s.strip]
    end

    heading_rows.each_with_index.map do |(start_line, level, source, text), index|
      next_heading = heading_rows[(index + 1)..-1].to_a.find { |(_, next_level, _, _)| next_level <= level }
      end_line = next_heading ? next_heading.first - 1 : content.lines.length
      fake_heading_class.new(source, text, level, fake_location_class.new(start_line, end_line))
    end
  end

  def write_complete_changelog
    write_changelog(<<~MARKDOWN)
      # Changelog

      ## [Unreleased]

      ### Added
      ### Changed
      ### Deprecated
      ### Removed
      ### Fixed
      ### Security
    MARKDOWN
  end

  def write_changelog(content)
    File.write(File.join(@root, "CHANGELOG.md"), content)
  end

  def read_changelog
    File.read(File.join(@root, "CHANGELOG.md"))
  end
end
