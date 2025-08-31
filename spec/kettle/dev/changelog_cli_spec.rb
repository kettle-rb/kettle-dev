# frozen_string_literal: true

require "json"

RSpec.describe "kettle-changelog integration", :check_output do
  include_context "with mocked git adapter"
  include_context "with mocked exit adapter"

  it "preserves older release blocks and interspersed link refs when adding new version" do
    Dir.mktmpdir do |root|
      # Prepare minimal gem fixture
      FileUtils.mkdir_p(File.join(root, "lib", "my", "gem"))
      # version.rb
      File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
        module My
          module Gem
            VERSION = "9.9.9"
          end
        end
      RB
      # coverage json minimal to satisfy CLI coverage parsing
      FileUtils.mkdir_p(File.join(root, "coverage"))
      File.write(File.join(root, "coverage", "coverage.json"), {result: {covered_lines: 100, total_lines: 100, covered_branches: 10, total_branches: 10}}.to_json)

      # Copy the complex CHANGELOG fixture into this temp gem
      fixture_path = File.expand_path("../../support/fixtures/CHANGELOG.md", __dir__)
      content = File.read(fixture_path)
      File.write(File.join(root, "CHANGELOG.md"), content)

      # Stub project_root and repo_info for deterministic link updates
      ci_helpers = Kettle::Dev::CIHelpers
      allow(ci_helpers).to receive(:project_root).and_return(root)
      allow(ci_helpers).to receive(:repo_info).and_return(["acme", "my-gem"]) # owner, repo

      # Freeze time for deterministic date
      t = Time.new(2025, 8, 30)
      allow(Time).to receive(:now).and_return(t)

      # Run the CLI
      cli = Kettle::Dev::ChangelogCLI.new
      expect { cli.run }.not_to raise_error

      updated = File.read(File.join(root, "CHANGELOG.md"))

      # It should add the new section header with date and TAG
      expect(updated).to include("## [9.9.9] - 2025-08-30")
      expect(updated).to include("- TAG: [v9.9.9][9.9.9t]")

      # Crucially, it should preserve at least one older section header
      expect(updated).to include("## [2.0.12] - 2025-05-31").or include("## [2.0.11] - 2025-05-23")

      # And preserve interspersed link refs that appear near 2.0.13 in the fixture
      expect(updated).to include("[gh660]: https://github.com/ruby-oauth/oauth2/pull/660")
      expect(updated).to include("[gh657]: https://github.com/ruby-oauth/oauth2/pull/657")
      expect(updated).to include("[gh656]: https://github.com/ruby-oauth/oauth2/pull/656")

      # Unreleased section should be reset with headings intact
      expect(updated).to include("## [Unreleased]\n### Added\n### Changed\n### Deprecated\n### Removed\n### Fixed\n### Security")
    end
  end

  it "works with a vanilla keep-a-changelog fixture" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib", "my", "gem"))
      File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
        module My
          module Gem
            VERSION = "9.9.9"
          end
        end
      RB
      FileUtils.mkdir_p(File.join(root, "coverage"))
      File.write(File.join(root, "coverage", "coverage.json"), {result: {covered_lines: 100, total_lines: 100, covered_branches: 10, total_branches: 10}}.to_json)

      # Copy the vanilla Keep a Changelog fixture
      fixture_path = File.expand_path("../../support/fixtures/KEEP_A_CHANGELOG.md", __dir__)
      content = File.read(fixture_path)
      File.write(File.join(root, "CHANGELOG.md"), content)

      # Stub project_root and repo_info for deterministic link updates
      ci_helpers = Kettle::Dev::CIHelpers
      allow(ci_helpers).to receive(:project_root).and_return(root)
      allow(ci_helpers).to receive(:repo_info).and_return(["acme", "my-gem"]) # owner, repo

      # Freeze time for deterministic date
      t = Time.new(2025, 8, 30)
      allow(Time).to receive(:now).and_return(t)

      cli = Kettle::Dev::ChangelogCLI.new
      expect { cli.run }.not_to raise_error

      updated = File.read(File.join(root, "CHANGELOG.md"))

      # New section and TAG
      expect(updated).to include("## [9.9.9] - 2025-08-30")
      expect(updated).to include("- TAG: [v9.9.9][9.9.9t]")

      # Preserve at least one older release section from the vanilla fixture
      expect(updated).to include("## [1.3.3] - 2024-11-08").or include("## [1.3.2] - 2024-11-05")

      # Unreleased section reset with headings intact
      expect(updated).to include("## [Unreleased]\n### Added\n### Changed\n### Deprecated\n### Removed\n### Fixed\n### Security")

      # Footer should still contain the Unreleased link-ref and include new compare/tag refs for 9.9.9
      expect(updated).to include("[Unreleased]: ")
      expect(updated).to include("[9.9.9]: https://github.com/acme/my-gem/compare/")
      expect(updated).to include("[9.9.9t]: https://github.com/acme/my-gem/releases/tag/v9.9.9")
    end
  end
end
