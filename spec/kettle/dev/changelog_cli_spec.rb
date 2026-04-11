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
        allow(Kettle::Dev::CIHelpers).to receive_messages(project_root: root, repo_info: [nil, nil])
        t = Time.new(2025, 8, 31)
        allow(Time).to receive(:now).and_return(t)

        cli = described_class.new(strict: false)
        expect { cli.run }.not_to raise_error
        updated = File.read(File.join(root, "CHANGELOG.md"))
        expect(updated).to include("## [1.2.3] - 2025-08-31")
      end
    end

    it "prompts and aborts when duplicate version exists and user declines reformat" do
      mkproj do |root|
        File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
          module My; module Gem; VERSION = "1.2.3"; end; end
        RB
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)
        # Duplicate section already exists
        File.write(File.join(root, "CHANGELOG.md"), <<~MD)
          # Changelog
          ## [Unreleased]

          ## [1.2.3] - 2025-08-30
        MD
        allow(Kettle::Dev::CIHelpers).to receive_messages(project_root: root, repo_info: ["o", "r"])
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("n\n")
        cli = described_class.new(strict: false)
        expect { cli.run }.to raise_error(MockSystemExit, /Aborting: version not bumped/)
      end
    end

    it "reformats only when duplicate version exists and user agrees" do
      mkproj do |root|
        File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
          module My; module Gem; VERSION = "1.2.3"; end; end
        RB
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)
        # Changelog with minimal missing blank lines to demonstrate reformat
        File.write(File.join(root, "CHANGELOG.md"), <<~MD)
          # Changelog
          ## [Unreleased]
          ### Added
          - item
          ## [1.2.3] - 2025-08-30
          - prev
        MD
        allow(Kettle::Dev::CIHelpers).to receive_messages(project_root: root, repo_info: ["o", "r"])
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("y\n")
        cli = described_class.new(strict: false)
        expect { cli.run }.not_to raise_error
        updated = File.read(File.join(root, "CHANGELOG.md"))
        # Should not add another 1.2.3 section
        expect(updated.scan(/^## \[1\.2\.3\]/).size).to eq(1)
        # Headings should have blank lines around
        expect(updated).to match(/# Changelog\n\n## \[Unreleased\]/)
        expect(updated).to match(/## \[Unreleased\]\n\n### Added/)
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
        cli = described_class.new(strict: false)
        expect { cli.run }.to raise_error(MockSystemExit, /Could not find '## \[Unreleased\]'/)
      end
    end
  end

  describe "#detect_initial_compare_base (private)" do
    it "returns KETTLE_CHANGELOG_INITIAL_SHA env var when set (highest priority)" do
      cli = described_class.new(strict: false)
      orig = ENV.fetch("KETTLE_CHANGELOG_INITIAL_SHA", nil)
      begin
        ENV["KETTLE_CHANGELOG_INITIAL_SHA"] = "upstream-sha-abc123"
        expect(cli.send(:detect_initial_compare_base)).to eq("upstream-sha-abc123")
      ensure
        orig ? ENV["KETTLE_CHANGELOG_INITIAL_SHA"] = orig : ENV.delete("KETTLE_CHANGELOG_INITIAL_SHA")
      end
    end

    it "returns the root commit SHA from git when env var is absent" do
      cli = described_class.new(strict: false)
      # The mocked git adapter returns deadbeefcafe1234deadbeefcafe1234deadbeef
      expect(cli.send(:detect_initial_compare_base)).to eq("deadbeefcafe1234deadbeefcafe1234deadbeef")
    end

    it "falls back to HEAD^ when git command fails" do
      cli = described_class.new(strict: false)
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(adapter).to receive(:capture).and_return(["", false])
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
      expect(cli.send(:detect_initial_compare_base)).to eq("HEAD^")
    end
  end

  describe "#detect_version" do
    it "errors when no version.rb present" do
      mkproj do |root|
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new(strict: false)
        expect { cli.send(:detect_version) }.to raise_error(MockSystemExit, /Could not find version.rb/)
      end
    end

    it "errors when VERSION constant not found" do
      mkproj do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "x"))
        File.write(File.join(root, "lib", "x", "version.rb"), "module X; end\n")
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new(strict: false)
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
        cli = described_class.new(strict: false)
        expect { cli.send(:detect_version) }.to raise_error(MockSystemExit, /Multiple VERSION constants/)
      end
    end

    it "returns the single VERSION value when consistent" do
      mkproj do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "a"))
        File.write(File.join(root, "lib", "a", "version.rb"), "module A; VERSION='3.2.1'; end\n")
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new(strict: false)
        expect(cli.send(:detect_version)).to eq("3.2.1")
      end
    end
  end

  describe "#extract_unreleased and #detect_previous_version" do
    it "returns nils when Unreleased heading missing and previous_version nil when not matched" do
      cli = described_class.new(strict: false)
      unreleased, before, after = cli.send(:extract_unreleased, "# Changelog\n")
      expect(unreleased).to be_nil
      expect(before).to be_nil
      expect(after).to be_nil
      expect(cli.send(:detect_previous_version, "random\ntext")).to be_nil
    end
  end

  describe "#filter_unreleased_sections" do
    it "keeps only sections with content and trims trailing blanks" do
      cli = described_class.new(strict: false)
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
        cli = described_class.new(strict: false)
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
        cli = described_class.new(strict: false)
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
          cli = described_class.new(strict: false)
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
          cli = described_class.new(strict: false)
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
    it "warns and returns nil when bin/rake not executable" do
      mkproj do |root|
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        cli = described_class.new(strict: false)
        expect(cli.send(:yard_percent_documented)).to be_nil
      end
    end

    it "returns nil and warns when percent not found in output" do
      mkproj do |root|
        # fake bin/rake
        path = File.join(root, "bin")
        FileUtils.mkdir_p(path)
        cmd = File.join(path, "rake")
        File.write(cmd, "#!/usr/bin/env ruby\nputs 'no percent here'\n")
        FileUtils.chmod(0o755, cmd)
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        # Don't actually execute file; just stub capture2 to return our text
        allow(File).to receive(:executable?).and_call_original
        allow(File).to receive(:executable?).with(cmd).and_return(true)
        allow(Open3).to receive(:capture2).and_return(["nothing documented line\n", double("ps")])
        cli = described_class.new(strict: false)
        expect(cli.send(:yard_percent_documented)).to be_nil
      end
    end

    it "rescues failures running yard" do
      mkproj do |root|
        path = File.join(root, "bin")
        FileUtils.mkdir_p(path)
        cmd = File.join(path, "rake")
        File.write(cmd, "#!/usr/bin/env ruby\nputs 'hi'\n")
        FileUtils.chmod(0o755, cmd)
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        allow(Open3).to receive(:capture2).and_raise(StandardError.new("boom"))
        cli = described_class.new(strict: false)
        expect(cli.send(:yard_percent_documented)).to be_nil
      end
    end
  end

  describe "#update_link_refs GitLab conversion and owner/repo behavior" do
    it "converts GitLab compare and tag links to GitHub using captured owner/repo when nil provided" do
      cli = described_class.new(strict: false)
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
      cli = described_class.new(strict: false)
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
      cli = described_class.new(strict: false)
      input = <<~TXT
        [1.2.3]: https://gitlab.com/foo/bar/-/compare/deadbeef...v1.2.3
      TXT
      out = cli.send(:update_link_refs, input, "acme", "widget", "1.2.2", "1.2.3")
      expect(out).to include("https://github.com/acme/widget/compare/deadbeef...v1.2.3")
      # Ensure old GitLab URL no longer present
      expect(out).not_to include("gitlab.com/foo/bar/-/compare/deadbeef...v1.2.3")
    end

    it "converts multiple GitLab compare links using captured groups when owner/repo are nil" do
      cli = described_class.new(strict: false)
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
    it "returns KETTLE_CHANGELOG_INITIAL_SHA env var when set" do
      cli = described_class.new(strict: false)
      orig = ENV.fetch("KETTLE_CHANGELOG_INITIAL_SHA", nil)
      begin
        ENV["KETTLE_CHANGELOG_INITIAL_SHA"] = "forked-sha-xyz"
        expect(cli.send(:detect_initial_compare_base)).to eq("forked-sha-xyz")
      ensure
        orig ? ENV["KETTLE_CHANGELOG_INITIAL_SHA"] = orig : ENV.delete("KETTLE_CHANGELOG_INITIAL_SHA")
      end
    end

    it "returns the git root commit SHA when env var absent and git succeeds" do
      cli = described_class.new(strict: false)
      expect(cli.send(:detect_initial_compare_base)).to eq("deadbeefcafe1234deadbeefcafe1234deadbeef")
    end

    it "defaults to HEAD^ when git fails and env var is absent" do
      cli = described_class.new(strict: false)
      adapter = instance_double(Kettle::Dev::GitAdapter)
      allow(adapter).to receive(:capture).and_return(["", false])
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(adapter)
      expect(cli.send(:detect_initial_compare_base)).to eq("HEAD^")
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

      cli = described_class.new(strict: false)
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
      allow(ci_helpers).to receive_messages(project_root: root, repo_info: ["acme", "my-gem"])

      # Freeze time for deterministic date
      t = Time.new(2025, 8, 30)
      allow(Time).to receive(:now).and_return(t)

      # Run the CLI
      cli = described_class.new(strict: false)
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

      # Unreleased section should be reset with headings intact and spaced by blank lines
      expect(updated).to match(/## \[Unreleased\]\n\n### Added\n\n### Changed\n\n### Deprecated\n\n### Removed\n\n### Fixed\n\n### Security/)
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
      allow(ci_helpers).to receive_messages(project_root: root, repo_info: ["acme", "my-gem"])

      # Freeze time for deterministic date
      t = Time.new(2025, 8, 30)
      allow(Time).to receive(:now).and_return(t)

      cli = described_class.new(strict: false)
      expect { cli.run }.not_to raise_error

      updated = File.read(File.join(root, "CHANGELOG.md"))

      # New section and TAG
      expect(updated).to include("## [9.9.9] - 2025-08-30")
      expect(updated).to include("- TAG: [v9.9.9][9.9.9t]")

      # Preserve at least one older release section from the vanilla fixture
      expect(updated).to include("## [1.3.3] - 2024-11-08").or include("## [1.3.2] - 2024-11-05")

      # Unreleased section reset with headings intact and spaced by blank lines
      expect(updated).to match(/## \[Unreleased\]\n\n### Added\n\n### Changed\n\n### Deprecated\n\n### Removed\n\n### Fixed\n\n### Security/)

      # Footer should still contain the Unreleased link-ref and include new compare/tag refs for 9.9.9
      expect(updated).to include("[Unreleased]: ")
      expect(updated).to include("[9.9.9]: https://github.com/acme/my-gem/compare/")
      expect(updated).to include("[9.9.9t]: https://github.com/acme/my-gem/releases/tag/v9.9.9")
    end
  end

  it "works with a partial-unreleased changelog fixture" do
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
      File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)

      # Copy the new partial Unreleased fixture
      fixture_path = File.expand_path("../../support/fixtures/CHANGELOG_PARTIAL_UNRELEASED.md", __dir__)
      content = File.read(fixture_path)
      File.write(File.join(root, "CHANGELOG.md"), content)

      # Stub project_root and repo_info for deterministic link updates
      allow(Kettle::Dev::CIHelpers).to receive_messages(project_root: root, repo_info: ["acme", "x"]) # owner, repo

      # Freeze time for deterministic date
      t = Time.new(2025, 8, 30)
      allow(Time).to receive(:now).and_return(t)

      cli = described_class.new(strict: false)
      expect { cli.run }.not_to raise_error

      updated = File.read(File.join(root, "CHANGELOG.md"))

      # New section and TAG
      expect(updated).to include("## [9.9.9] - 2025-08-30")
      expect(updated).to include("- TAG: [v9.9.9][9.9.9t]")

      # Unreleased section should be fully reset to all standard subheadings without duplication
      expect(updated).to match(/## \[Unreleased\]\n\n### Added\n\n### Changed\n\n### Deprecated\n\n### Removed\n\n### Fixed\n\n### Security\n\n## \[9\.9\.9\] - 2025-08-30/)

      # Ensure footer [Unreleased] link-ref is preserved (fixture uses ...main)
      expect(updated).to include("[Unreleased]: ")
      expect(updated).to include("...main").or include("...HEAD")
    end
  end

  # ── Bug regression specs ────────────────────────────────────────────────────

  # Bug: link-ref definition lines (e.g. `[key]: https://...`) were treated as
  # real content when deciding whether an H3 section was non-empty.  A section
  # that contains ONLY link-ref defs (no list items / paragraphs) must be
  # dropped from the released block.
  describe "bug: link-ref definitions must not count as section content" do
    def run_with_fixture(fixture_name, version: "9.9.9", owner: "acme", repo: "x")
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "my", "gem"))
        File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
          module My; module Gem; VERSION = "#{version}"; end; end
        RB
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)

        fixture_path = File.expand_path("../../support/fixtures/#{fixture_name}", __dir__)
        File.write(File.join(root, "CHANGELOG.md"), File.read(fixture_path))

        allow(Kettle::Dev::CIHelpers).to receive_messages(project_root: root, repo_info: [owner, repo])
        allow(Time).to receive(:now).and_return(Time.new(2025, 8, 30))

        cli = described_class.new(strict: false)
        expect { cli.run }.not_to raise_error
        yield File.read(File.join(root, "CHANGELOG.md"))
      end
    end

    it "drops H3 section whose body contains only link-ref definitions" do
      run_with_fixture("CHANGELOG_BUG_LINK_REFS_AS_CONTENT.md") do |updated|
        # ### Changed body had only a link-ref def — must be omitted
        released = updated[/## \[9\.9\.9\].*?(?=## \[|\z)/m]
        expect(released).not_to include("### Changed")
        # ### Added and ### Fixed had real list items — must be kept
        expect(released).to include("### Added")
        expect(released).to include("### Fixed")
        # ### Deprecated, ### Removed, ### Security were all empty — must be omitted
        expect(released).not_to include("### Deprecated")
        expect(released).not_to include("### Removed")
        expect(released).not_to include("### Security")
      end
    end

    it "keeps inline link-ref defs that accompany real content, drops refs from dropped sections" do
      run_with_fixture("CHANGELOG_BUG_LINK_REFS_AS_CONTENT.md") do |updated|
        released = updated[/## \[9\.9\.9\].*?(?=## \[|\z)/m]
        # [🔀ref1] lives in ### Added (kept) → must be preserved in the released body
        expect(released).to include("[🔀ref1]: https://example.com/one")
        # [🔀ref2] lives in ### Changed (dropped, link-ref only) → must be absent
        expect(released).not_to include("[🔀ref2]:")
        # [🔀ref3] lives in ### Security (dropped, link-ref only) → must be absent
        expect(released).not_to include("[🔀ref3]:")
      end
    end
  end

  # Bug: when the CHANGELOG has no previous `## [...]` release (i.e. this is the
  # very first release), the footer link-refs (`[Unreleased]: ...` etc.) live
  # directly inside the Unreleased block with no `## [` boundary to stop
  # `extract_unreleased`.  They bleed into the last H3 section (typically
  # ### Security), making it appear non-empty and causing it to be retained with
  # the footer refs as its body.
  describe "bug: footer link-refs must not bleed into unreleased body on first release" do
    it "drops ### Security and places footer link-refs only in the footer" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "my", "gem"))
        File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
          module My; module Gem; VERSION = "1.0.0"; end; end
        RB
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)

        fixture_path = File.expand_path("../../support/fixtures/CHANGELOG_BUG_FOOTER_BLEEDING.md", __dir__)
        File.write(File.join(root, "CHANGELOG.md"), File.read(fixture_path))

        allow(Kettle::Dev::CIHelpers).to receive_messages(project_root: root, repo_info: ["acme", "new-gem"])
        allow(Time).to receive(:now).and_return(Time.new(2025, 8, 30))

        cli = described_class.new(strict: false)
        expect { cli.run }.not_to raise_error

        updated = File.read(File.join(root, "CHANGELOG.md"))
        # Extract just the released section: from ## [1.0.0] until the footer block or next ## [
        released_start = updated.index("## [1.0.0]")
        footer_start = updated.index("\n[Unreleased]:")
        released = (released_start && footer_start) ? updated[released_start...footer_start] : ""

        # Empty sections must be absent from the released block
        expect(released).not_to include("### Security")
        expect(released).not_to include("### Deprecated")
        expect(released).not_to include("### Removed")
        # ### Fixed has real content → must be present
        expect(released).to include("### Fixed")
        expect(released).to include("### Added")
        expect(released).to include("### Changed")

        # Footer link-refs must NOT appear inside the released section body
        expect(released).not_to match(/^\[Unreleased\]:/)
        expect(released).not_to match(/^\[1\.0\.0\]:/)
        expect(released).not_to match(/^\[1\.0\.0t\]:/)

        # But the footer itself must still exist at the end of the file
        footer = updated.lines.drop_while { |l| !l.start_with?("[Unreleased]:") }.join
        expect(footer).to include("[Unreleased]:")
        expect(footer).to include("[1.0.0]:")
        expect(footer).to include("[1.0.0t]:")
        # Compare link must use the git root commit SHA (mocked as deadbeef...)
        expect(footer).to include("deadbeefcafe1234deadbeefcafe1234deadbeef...v1.0.0")
      end
    end
  end

  # Bug: an H4 subsection heading (####) with no list items under it — but
  # appearing under an H3 section that does have real content elsewhere —
  # should not count as real content for a section that is otherwise empty.
  describe "bug: H4 subsection headings alone must not count as section content" do
    it "drops H3 section whose body has only an H4 heading and no list items" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "my", "gem"))
        File.write(File.join(root, "lib", "my", "gem", "version.rb"), <<~RB)
          module My; module Gem; VERSION = "2.0.0"; end; end
        RB
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)

        fixture_path = File.expand_path("../../support/fixtures/CHANGELOG_BUG_H4_ONLY_CONTENT.md", __dir__)
        File.write(File.join(root, "CHANGELOG.md"), File.read(fixture_path))

        allow(Kettle::Dev::CIHelpers).to receive_messages(project_root: root, repo_info: ["acme", "x"])
        allow(Time).to receive(:now).and_return(Time.new(2025, 8, 30))

        cli = described_class.new(strict: false)
        expect { cli.run }.not_to raise_error

        updated = File.read(File.join(root, "CHANGELOG.md"))
        released = updated[/## \[2\.0\.0\] - 2025-08-30.*?(?=## \[|\z)/m]

        # ### Added has ONLY an H4 heading (no list items) → must be dropped
        expect(released).not_to include("### Added")
        expect(released).not_to include("#### From upstream project")
        # Other empty H3 sections must also be absent
        expect(released).not_to include("### Deprecated")
        expect(released).not_to include("### Removed")
        expect(released).not_to include("### Fixed")
        expect(released).not_to include("### Security")
        # ### Changed had a real list item → kept
        expect(released).to include("### Changed")
      end
    end
  end

  # Full integration regression: the real turbo_tests2 CHANGELOG exercising all
  # three bugs simultaneously.
  describe "bug integration: turbo_tests2 CHANGELOG with H4 subsections, inline link-refs, and footer bleeding" do
    it "produces a correct released section from the turbo_tests2 fixture" do
      Dir.mktmpdir do |root|
        FileUtils.mkdir_p(File.join(root, "lib", "turbo_tests2"))
        File.write(File.join(root, "lib", "turbo_tests2", "version.rb"), <<~RB)
          module TurboTests2; VERSION = "3.0.0"; end
        RB
        FileUtils.mkdir_p(File.join(root, "coverage"))
        File.write(File.join(root, "coverage", "coverage.json"), {"coverage" => {}}.to_json)

        fixture_path = File.expand_path("../../support/fixtures/CHANGELOG_TURBO_TESTS2.md", __dir__)
        File.write(File.join(root, "CHANGELOG.md"), File.read(fixture_path))

        allow(Kettle::Dev::CIHelpers).to receive_messages(
          project_root: root,
          repo_info: ["galtzo-floss", "turbo_tests2"],
        )
        allow(Time).to receive(:now).and_return(Time.new(2026, 4, 7))

        cli = described_class.new(strict: false)
        expect { cli.run }.not_to raise_error

        updated = File.read(File.join(root, "CHANGELOG.md"))
        # Extract just the released section: stop before the footer block
        released_start = updated.index("## [3.0.0]")
        footer_start = updated.index("\n[Unreleased]:")
        released = (released_start && footer_start) ? updated[released_start...footer_start] : ""

        # --- Sections that have real content must be present ---
        expect(released).to include("### Added")
        expect(released).to include("### Changed")
        expect(released).to include("### Fixed")

        # --- H4 subsections with content must be preserved ---
        expect(released).to include("#### From `VitalConnectInc/turbo_tests`, now part of `turbo_tests2`")
        expect(released).to include("#### New in `turbo_tests2`")

        # --- Empty sections must be absent ---
        expect(released).not_to include("### Deprecated")
        expect(released).not_to include("### Removed")
        expect(released).not_to include("### Security")

        # --- Footer link-refs must NOT appear in the released section body ---
        expect(released).not_to match(/^\[Unreleased\]:/)
        expect(released).not_to match(/^\[3\.0\.0\]:/)
        expect(released).not_to match(/^\[3\.0\.0t\]:/)

        # --- The footer must be present and correct at end of file ---
        footer = updated.lines.drop_while { |l| !l.start_with?("[Unreleased]:") }.join
        expect(footer).to include("[Unreleased]: https://github.com/galtzo-floss/turbo_tests2")
        expect(footer).to include("[3.0.0]:")
        expect(footer).to include("[3.0.0t]:")
        # The hard-fork compare SHA must be preserved (not overwritten by the git root SHA)
        expect(footer).to include("7d4064e5b8acc2f53929fccf7be3eb63f8a9f140...v3.0.0")

        # --- Unreleased section reset to empty headings ---
        expect(updated).to match(/## \[Unreleased\]\n\n### Added\n\n### Changed\n\n### Deprecated\n\n### Removed\n\n### Fixed\n\n### Security/)
      end
    end
  end

  describe "#yard_percent_documented success" do
    it "parses the documented percentage from yard output" do
      mkproj do |root|
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        path = File.join(root, "bin")
        FileUtils.mkdir_p(path)
        cmd = File.join(path, "rake")
        File.write(cmd, "#!/usr/bin/env ruby\nputs 'ok'\n")
        FileUtils.chmod(0o755, cmd)
        allow(File).to receive(:executable?).and_call_original
        allow(File).to receive(:executable?).with(cmd).and_return(true)
        allow(Open3).to receive(:capture2).and_return(["Some header\n95.5% documented\nMore lines\n", double("ps")])
        cli = described_class.new(strict: false)
        expect(cli.send(:yard_percent_documented)).to eq("95.5% documented")
      end
    end
  end

  describe "#detect_previous_version positive" do
    it "extracts the next released version heading after Unreleased" do
      cli = described_class.new(strict: false)
      after_text = <<~TXT
        ## [2.1.0] - 2025-07-07
        notes
      TXT
      expect(cli.send(:detect_previous_version, after_text)).to eq("2.1.0")
    end
  end

  describe "#update_link_refs without owner/repo" do
    it "does not append new refs when owner and repo are nil" do
      cli = described_class.new(strict: false)
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

  describe "#update_link_refs spacing around footer" do
    it "ensures a blank line before the link-ref block and retains a trailing blank line" do
      cli = described_class.new(strict: false)
      input = <<~TXT
        ## [Unreleased]
        Changelog body
        [Unreleased]: https://github.com/acme/demo/compare/v1.0.0...HEAD
        [1.0.0]: https://github.com/acme/demo/compare/v0.9.0...v1.0.0
      TXT
      out = cli.send(:update_link_refs, input, "acme", "demo", "1.0.0", "1.1.0")
      # There should be exactly one blank line between body and the first ref line
      expect(out).to match(/Changelog body\n\n\[Unreleased\]:/)
      # And the output should end with a blank line (double newline at EOF)
      expect(out).to match(/\n\n\z/)
    end
  end

  describe "tag suffix transformation" do
    it "moves ([tag][Xt]) from heading suffix into first list item under heading using fixtures" do
      cli = described_class.new(strict: false)
      heading_style = File.read(File.join(__dir__, "..", "..", "support", "fixtures", "CHANGELOG_HEADING_TAGS.md"))
      list_style = File.read(File.join(__dir__, "..", "..", "support", "fixtures", "CHANGELOG_LIST_TAGS.md"))
      transformed = cli.send(:convert_heading_tag_suffix_to_list, heading_style)
      expect(transformed).to eq(list_style)
    end
  end
end
