# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, ThreadSafety/DirChdir

require "tmpdir"
require "fileutils"

RSpec.describe GitCommitFooter do
  include_context "with stubbed env"

  describe "::hooks_path_for and directories" do
    it "prefers local .git-hooks when file exists" do
      Dir.mktmpdir do |root|
        local = File.join(root, ".git-hooks")
        FileUtils.mkdir_p(local)
        File.write(File.join(local, "x.txt"), "ok")
        allow(described_class).to receive(:git_toplevel).and_return(root)
        expect(described_class.hooks_path_for("x.txt")).to eq(File.join(local, "x.txt"))
      end
    end

    it "falls back to global hooks dir when local missing" do
      Dir.mktmpdir do |home|
        stub_env("HOME" => home)
        allow(described_class).to receive(:git_toplevel).and_return(nil)
        expect(described_class.hooks_path_for("y.txt")).to eq(File.join(home, ".git-hooks", "y.txt"))
      end
    end
  end

  describe "::goalie_allows_footer?" do
    it "returns true when subject matches a non-comment, non-empty prefix" do
      Dir.mktmpdir do |home|
        stub_env("HOME" => home)
        hooks = File.join(home, ".git-hooks")
        FileUtils.mkdir_p(hooks)
        goalie = File.join(hooks, "commit-subjects-goalie.txt")
        File.write(goalie, "# comment\nfeat: \n")
        allow(described_class).to receive(:commit_goalie_path).and_return(goalie)
        expect(described_class.goalie_allows_footer?("feat: add")).to be(true)
      end
    end

    it "returns false when goalie file missing or empty" do
      Dir.mktmpdir do |home|
        stub_env("HOME" => home)
        expect(described_class.goalie_allows_footer?("feat: add")).to be(false)
        hooks = File.join(home, ".git-hooks")
        FileUtils.mkdir_p(hooks)
        File.write(File.join(hooks, "commit-subjects-goalie.txt"), "\n\n")
        expect(described_class.goalie_allows_footer?("feat: add")).to be(false)
      end
    end
  end

  describe "::render" do
    it "appends footer when enabled, allowed, and no sentinel present" do
      Dir.mktmpdir do |dir|
        stub_env(
          "GIT_HOOK_FOOTER_APPEND" => "true",
          "GIT_HOOK_FOOTER_SENTINEL" => "SENT",
        )
        # prepare hooks
        Dir.mktmpdir do |home|
          stub_env("HOME" => home)
          hooks = File.join(home, ".git-hooks")
          FileUtils.mkdir_p(hooks)
          File.write(File.join(hooks, "commit-subjects-goalie.txt"), "feat: \n")
          File.write(File.join(hooks, "footer-template.erb.txt"), "-- SENT -- <%= @gem_name %>\n")

          # gemspec for deriving gem name
          File.write(File.join(dir, "demo.gemspec"), "Gem::Specification.new { |s| s.name = 'demo' }\n")

          file = File.join(dir, "COMMIT_EDITMSG")
          File.write(file, "feat: header\n\nbody\n")

          Dir.chdir(dir) do
            expect { described_class.render(file) }.not_to raise_error
          end

          content = File.read(file)
          expect(content).to include("-- SENT -- demo")
        end
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, ThreadSafety/DirChdir
