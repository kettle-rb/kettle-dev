# frozen_string_literal: true

require "json"

RSpec.describe Kettle::Dev::ChangelogCLI, :check_output do
  include_context "with mocked git adapter"
  include_context "with mocked exit adapter"

  it "lists Unreleased first, then newest to oldest versions in footer" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib", "my", "gem"))
      File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
        module My
          module Gem
            VERSION = "2.0.14"
          end
        end
      RB
      FileUtils.mkdir_p(File.join(root, "coverage"))
      File.write(File.join(root, "coverage", "coverage.json"), {result: {covered_lines: 100, total_lines: 100, covered_branches: 10, total_branches: 10}}.to_json)

      fixture_path = File.expand_path("../../support/fixtures/CHANGELOG.md", __dir__)
      content = File.read(fixture_path)
      File.write(File.join(root, "CHANGELOG.md"), content)

      ci_helpers = Kettle::Dev::CIHelpers
      allow(ci_helpers).to receive_messages(project_root: root, repo_info: ["acme", "my-gem"]) # owner, repo

      t = Time.new(2025, 8, 30)
      allow(Time).to receive(:now).and_return(t)

      cli = described_class.new
      expect { cli.run }.not_to raise_error

      updated = File.read(File.join(root, "CHANGELOG.md"))

      # Extract footer lines only
      footer = updated.lines.drop_while { |l| !l.start_with?("[Unreleased]:") }
      keys = footer.grep(/^\[[^\]]+\]:/).map { |l| l[/^\[([^\]]+)\]:/, 1] }

      # Ensure Unreleased is first
      expect(keys.first).to eq("Unreleased")

      # Find versions order that follows Unreleased
      versions = keys.drop(1).map { |k| k.sub(/t\z/, "") }
      # Remove duplicates for compare/tag pairs
      versions_uniq = []
      versions.each { |v| versions_uniq << v unless versions_uniq.include?(v) }

      # Expect strictly descending order (newest to oldest)
      parsed = versions_uniq.map { |s| Gem::Version.new(s) }
      expect(parsed).to eq(parsed.sort.reverse)
    end
  end
end
