# frozen_string_literal: true

RSpec.describe Kettle::Dev::MarkdownReferenceValidator do
  def write_markdown(root, path, content)
    full_path = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  it "accepts defined references and local heading anchors" do
    Dir.mktmpdir do |root|
      write_markdown(root, "README.md", <<~MD)
        # Project Guide

        [guide][docs]
        [docs]: docs/guide.md#installation
        [inline](docs/guide.md#usage)
      MD
      write_markdown(root, "docs/guide.md", <<~MD)
        # Installation

        Usage
        -----
      MD

      report = described_class.new(root: root, files: ["README.md", "docs/guide.md"]).validate!

      expect(report.file_count).to eq(2)
      expect(report.reference_count).to eq(1)
      expect(report.local_target_count).to eq(2)
      expect(report.issues).to be_empty
    end
  end

  it "reports undefined references, missing files, and missing headings" do
    Dir.mktmpdir do |root|
      write_markdown(root, "README.md", <<~MD)
        [missing][not-defined]
        [bad-file](docs/nope.md#section)
        [bad-heading](docs/guide.md#unknown)
      MD
      write_markdown(root, "docs/guide.md", "# Existing Section\n")

      expect {
        described_class.new(root: root, files: ["README.md", "docs/guide.md"]).validate!
      }.to raise_error(Kettle::Dev::Error, /3 issue\(s\)/)
    end
  end

  it "ignores references and headings inside fenced code" do
    Dir.mktmpdir do |root|
      write_markdown(root, "README.md", <<~MD)
        ```markdown
        [not-a-link][missing]
        [missing]: nowhere.md
        # Not a heading
        ```
      MD

      report = described_class.new(root: root, files: ["README.md"]).validate!

      expect(report.reference_count).to eq(0)
      expect(report.issues).to be_empty
    end
  end

  it "uses GitHub-style suffixes for duplicate headings" do
    Dir.mktmpdir do |root|
      write_markdown(root, "README.md", <<~MD)
        # Setup
        # Setup

        [first](README.md#setup)
        [second](README.md#setup-1)
      MD

      report = described_class.new(root: root, files: ["README.md"]).validate!

      expect(report.issues).to be_empty
    end
  end
end
