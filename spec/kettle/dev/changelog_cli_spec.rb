# frozen_string_literal: true

require "json"

RSpec.describe Kettle::Dev::ChangelogCLI, :check_output do
  include_context "with mocked git adapter"
  include_context "with mocked exit adapter"

  def mkproj
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib", "my", "gem"))
      yield root
    end
  end

  describe "#run warnings and aborts" do
    it "warns when owner/repo cannot be determined and Unreleased is empty" do
      mkproj do |root|
        # version.rb
        File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
          module My; module Gem; VERSION = "1.2.3"; end; end
        RB
        # coverage present but empty content acceptable
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)
        # Minimal changelog with empty Unreleased
        File.write(File.join(root, "CHANGELOG.md"), <<~MD)
          # Changelog
          ## [Unreleased]
          ### Added
          ### Changed
          ### Deprecated
          ### Removed
          ### Fixed
          ### Security

          ## [0.9.9] - 2020-01-01
        MD
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        allow(Kettle::Dev::CIHelpers).to receive(:repo_info).and_return([nil, nil])
        t = Time.new(2025, 8, 31)
        allow(Time).to receive(:now).and_return(t)

        cli = described_class.new
        expect { cli.run }.not_to raise_error
        updated = File.read(File.join(root, "CHANGELOG.md"))
        expect(updated).to include("## [1.2.3] - 2025-08-31")
      end
    end

    it "aborts when duplicate version section exists" do
      mkproj do |root|
        File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
          module My; module Gem; VERSION = "1.2.3"; end; end
        RB
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)
        # Duplicate section already exists
        File.write(File.join(root, "CHANGELOG.md"), <<~MD)
          ## [Unreleased]

          ## [1.2.3] - 2025-08-30
        MD
        allow(Kettle::Dev::CIHelpers).to receive_messages(project_root: root, repo_info: ["o", "r"])
        cli = described_class.new
        expect { cli.run }.to raise_error(MockSystemExit, /already has a section/)
      end
    end

    it "aborts when Unreleased section is missing" do
      mkproj do |root|
        File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
          module My; module Gem; VERSION = "1.2.3"; end; end
        RB
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)
        File.write(File.join(root, "CHANGELOG.md"), "# no unreleased here\n")
        allow(Kettle::Dev::CIHelpers).to receive_messages(project_root: root, repo_info: ["o", "r"])
        cli = described_class.new
        expect { cli.run }.to raise_error(MockSystemExit, /Could not find '## \[Unreleased\]'/)
      end
    end
  end

  describe "#detect_initial_compare_base (private)" do
    it "extracts historical base from first compare link when present" do
      cli = described_class.new
      lines = [
        "[Unreleased]: https://github.com/acme/demo/compare/v1.2.3...HEAD\n",
        "[1.0.0]: https://github.com/acme/demo/compare/abc123...v1.0.0\n",
      ]
      expect(cli.send(:detect_initial_compare_base, lines)).to eq("abc123")
    end

    it "defaults to HEAD^ when no historical base found" do
      cli = described_class.new
      lines = [
        "[Unreleased]: https://github.com/acme/demo/compare/v2.0.0...HEAD\n",
        "[2.0.0]: https://github.com/acme/demo/compare/v1.9.9...v2.0.0\n",
      ]
      expect(cli.send(:detect_initial_compare_base, lines)).to eq("HEAD^")
    end
  end

  describe "#detect_version" do
    it "errors when no version.rb present" do
      mkproj do |root|
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect { cli.send(:detect_version) }.to raise_error(MockSystemExit, /Could not find version.rb/)
      end
    end

    it "errors when VERSION constant not found" do
      mkproj do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "x"))
        File.write(File.join(root, "lib", "x", "version.rb"), "module X; end\n")
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect { cli.send(:detect_version) }.to raise_error(MockSystemExit, /VERSION constant not found/)
      end
    end

    it "errors when multiple VERSION values differ" do
      mkproj do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "a"))
        FileUtils.mkdir_p(File.join(root, "lib", "b"))
        File.write(File.join(root, "lib", "a", "version.rb"), "module A; VERSION='1.0.0'; end\n")
        File.write(File.join(root, "lib", "b", "version.rb"), "module B; VERSION='2.0.0'; end\n")
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect { cli.send(:detect_version) }.to raise_error(MockSystemExit, /Multiple VERSION constants/)
      end
    end

    it "returns the single VERSION value when consistent" do
      mkproj do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "a"))
        File.write(File.join(root, "lib", "a", "version.rb"), "module A; VERSION='3.2.1'; end\n")
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect(cli.send(:detect_version)).to eq("3.2.1")
      end
    end
  end

  describe "#extract_unreleased and #detect_previous_version" do
    it "returns nils when Unreleased heading missing and previous_version nil when not matched" do
      cli = described_class.new
      unreleased, before, after = cli.send(:extract_unreleased, "# Changelog\n")
      expect(unreleased).to be_nil
      expect(before).to be_nil
      expect(after).to be_nil
      expect(cli.send(:detect_previous_version, "random\ntext")).to be_nil
    end
  end

  describe "#filter_unreleased_sections" do
    it "keeps only sections with content and trims trailing blanks" do
      cli = described_class.new
      block = <<~BLK
        noise outside
        ### Added
        - one

        ### Changed
        
        ### Fixed
        - fx
        
      BLK
      out = cli.send(:filter_unreleased_sections, block)
      expect(out).to include("### Added\n- one\n")
      expect(out).to include("### Fixed\n- fx\n")
      expect(out).not_to include("### Changed")
      expect(out).not_to include("noise outside")
    end
  end

  describe "#coverage_lines" do
    it "warns and returns nils when coverage.json missing" do
      mkproj do |root|
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        line_cov, branch_cov = cli.send(:coverage_lines)
        expect(line_cov).to be_nil
        expect(branch_cov).to be_nil
      end
    end

    it "rescues JSON parsing errors and returns nils" do
      mkproj do |root|
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), "not json")
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        line_cov, branch_cov = cli.send(:coverage_lines)
        expect(line_cov).to be_nil
        expect(branch_cov).to be_nil
      end
    end

    context "when success aggregation" do
      it "computes line and branch coverage across files" do
        mkproj do |root|
          allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
          FileUtils.mkdir_p(File.join(root, "coverage"))
          data = {
            "coverage" => {
              "lib/a.rb" => {
                "lines" => [1, 0, nil, "x"],
                "branches" => [
                  {"coverage" => 1},
                  {"coverage" => 0},
                  {"coverage" => "n/a"},
                ],
              },
              "lib/b.rb" => {
                "lines" => [0, 0, 2],
                "branches" => [
                  {"coverage" => 0},
                  {"coverage" => 0},
                ],
              },
              "lib/c.rb" => {
                "lines" => [nil, nil],
                "branches" => [],
              },
            },
          }
          File.write(File.join(root, "coverage", "coverage.json"), JSON.pretty_generate(data))
          cli = described_class.new
          line_cov, branch_cov = cli.send(:coverage_lines)
          expect(line_cov).to eq("COVERAGE: 40.00% -- 2/5 lines in 2 files")
          expect(branch_cov).to eq("BRANCH COVERAGE: 25.00% -- 1/4 branches in 2 files")
        end
      end
    end

    context "when branch filtering" do
      it "counts only Hash entries with Numeric coverage and increments covered only for > 0" do
        Dir.mktmpdir do |root|
          allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
          FileUtils.mkdir_p(File.join(root, "coverage"))
          data = {
            "coverage" => {
              "lib/a.rb" => {
                "lines" => [1],
                "branches" => [
                  "string",             # skipped: not a Hash (line 202)
                  123,                   # skipped: not a Hash (line 202)
                  {"coverage" => "n/a"}, # skipped: non-Numeric (line 204)
                  {"coverage" => 0},     # counts in total, not covered (205-206)
                  {"coverage" => 2},      # counts in total and covered (205-206)
                ],
              },
            },
          }
          File.write(File.join(root, "coverage", "coverage.json"), JSON.pretty_generate(data))
          cli = described_class.new
          line_cov, branch_cov = cli.send(:coverage_lines)
          # lines: 1 relevant, 1 covered, 1 file
          expect(line_cov).to eq("COVERAGE: 100.00% -- 1/1 lines in 1 files")
          # branches considered: only the two Hash+Numeric ones => total 2, covered 1
          expect(branch_cov).to eq("BRANCH COVERAGE: 50.00% -- 1/2 branches in 1 files")
        end
      end
    end
  end

  describe "#yard_percent_documented" do
    it "warns and returns nil when bin/yard not executable" do
      mkproj do |root|
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new
        expect(cli.send(:yard_percent_documented)).to be_nil
      end
    end

    it "returns nil and warns when percent not found in output" do
      mkproj do |root|
        # fake bin/yard
        path = File.join(root, "bin")
        FileUtils.mkdir_p(path)
        cmd = File.join(path, "yard")
        File.write(cmd, "#!/usr/bin/env ruby\nputs 'no percent here'\n")
        FileUtils.chmod(0o755, cmd)
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        # Don't actually execute file; just stub capture2 to return our text
        allow(File).to receive(:executable?).and_call_original
        allow(File).to receive(:executable?).with(cmd).and_return(true)
        allow(Open3).to receive(:capture2).and_return(["nothing documented line\n", double("ps")])
        cli = described_class.new
        expect(cli.send(:yard_percent_documented)).to be_nil
      end
    end

    it "rescues failures running yard" do
      mkproj do |root|
        path = File.join(root, "bin")
        FileUtils.mkdir_p(path)
        cmd = File.join(path, "yard")
        File.write(cmd, "#!/usr/bin/env ruby\nputs 'hi'\n")
        FileUtils.chmod(0o755, cmd)
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        allow(Open3).to receive(:capture2).and_raise(StandardError.new("boom"))
        cli = described_class.new
        expect(cli.send(:yard_percent_documented)).to be_nil
      end
    end
  end

  describe "#update_link_refs GitLab conversion and owner/repo behavior" do
    it "converts GitLab compare and tag links to GitHub using captured owner/repo when nil provided" do
      cli = described_class.new
      input = <<~TXT
        ## [Unreleased]
        Something

        [Unreleased]: https://gitlab.com/foo/bar/-/compare/abc...HEAD
        [1.0.0]: https://gitlab.com/foo/bar/-/compare/abc...v1.0.0
        [1.0.0t]: https://gitlab.com/foo/bar/-/tags/v1.0.0
      TXT
      out = cli.send(:update_link_refs, input, nil, nil, "0.9.0", "1.0.1")
      expect(out).to include("https://github.com/foo/bar/compare/abc...v1.0.0")
      expect(out).to include("https://github.com/foo/bar/releases/tag/v1.0.0")
    end

    it "appends new compare and tag refs only when owner/repo present and handles missing Unreleased ref" do
      cli = described_class.new
      input = <<~TXT
        ## [Unreleased]
        Notes

        [1.0.0]: https://github.com/acme/x/compare/v0.9.0...v1.0.0
        [1.0.0t]: https://github.com/acme/x/releases/tag/v1.0.0
      TXT
      out = cli.send(:update_link_refs, input, "acme", "x", "1.0.0", "1.1.0")
      expect(out).to include("[Unreleased]: https://github.com/acme/x/compare/v1.1.0...HEAD")
      expect(out).to include("[1.1.0]: https://github.com/acme/x/compare/v1.0.0...v1.1.0")
      expect(out).to include("[1.1.0t]: https://github.com/acme/x/releases/tag/v1.1.0")
    end
  end

  describe "#update_link_refs GitLab compare owner override and multiple entries" do
    it "uses provided owner/repo instead of captured ones when present (compare links)" do
      cli = described_class.new
      input = <<~TXT
        [1.2.3]: https://gitlab.com/foo/bar/-/compare/deadbeef...v1.2.3
      TXT
      out = cli.send(:update_link_refs, input, "acme", "widget", "1.2.2", "1.2.3")
      expect(out).to include("https://github.com/acme/widget/compare/deadbeef...v1.2.3")
      # Ensure old GitLab URL no longer present
      expect(out).not_to include("gitlab.com/foo/bar/-/compare/deadbeef...v1.2.3")
    end

    it "converts multiple GitLab compare links using captured groups when owner/repo are nil" do
      cli = described_class.new
      input = <<~TXT
        [0.9.0]: https://gitlab.com/one/repo/-/compare/abc123...v0.9.0
        [1.0.0]: https://gitlab.com/two/other/-/compare/def456...v1.0.0
      TXT
      out = cli.send(:update_link_refs, input, nil, nil, "0.9.0", "1.0.1")
      expect(out).to include("https://github.com/one/repo/compare/abc123...v0.9.0")
      expect(out).to include("https://github.com/two/other/compare/def456...v1.0.0")
    end
  end

  describe "#detect_initial_compare_base" do
    it "extracts base from first 1.0.0 compare ref when present" do
      cli = described_class.new
      lines = [
        "[1.0.0]: https://github.com/acme/x/compare/abc123...v1.0.0\n",
        "[1.1.0]: https://github.com/acme/x/compare/v1.0.0...v1.1.0\n",
      ]
      expect(cli.send(:detect_initial_compare_base, lines)).to eq("abc123")
    end

    it "defaults to HEAD^ when no suitable ref found" do
      cli = described_class.new
      lines = ["[foo]: https://example.com\n"]
      expect(cli.send(:detect_initial_compare_base, lines)).to eq("HEAD^")
    end
  end

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

  describe "#yard_percent_documented success" do
    it "parses the documented percentage from yard output" do
      mkproj do |root|
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        path = File.join(root, "bin")
        FileUtils.mkdir_p(path)
        cmd = File.join(path, "yard")
        File.write(cmd, "#!/usr/bin/env ruby\nputs 'ok'\n")
        FileUtils.chmod(0o755, cmd)
        allow(File).to receive(:executable?).and_call_original
        allow(File).to receive(:executable?).with(cmd).and_return(true)
        allow(Open3).to receive(:capture2).and_return(["Some header\n95.5% documented\nMore lines\n", double("ps")])
        cli = described_class.new
        expect(cli.send(:yard_percent_documented)).to eq("95.5% documented")
      end
    end
  end

  describe "#detect_previous_version positive" do
    it "extracts the next released version heading after Unreleased" do
      cli = described_class.new
      after_text = <<~TXT
        ## [2.1.0] - 2025-07-07
        notes
      TXT
      expect(cli.send(:detect_previous_version, after_text)).to eq("2.1.0")
    end
  end

  describe "#update_link_refs without owner/repo" do
    it "does not append new refs when owner and repo are nil" do
      cli = described_class.new
      input = <<~TXT
        # Changelog
        ## [Unreleased]
        Things

        [1.0.0]: https://github.com/acme/x/compare/v0.9.0...v1.0.0
        [1.0.0t]: https://github.com/acme/x/releases/tag/v1.0.0
      TXT
      out = cli.send(:update_link_refs, input, nil, nil, "1.0.0", "1.1.0")
      expect(out).not_to include("[1.1.0]: https://github.com")
      expect(out).not_to include("[1.1.0t]: https://github.com")
      # And Unreleased ref is not added because we don't know owner/repo
      expect(out).not_to include("[Unreleased]: https://github.com/")
    end
  end
end
