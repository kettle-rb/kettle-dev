# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, ThreadSafety/DirChdir

require "tmpdir"
require "fileutils"

RSpec.describe Kettle::Dev::GitCommitFooter do
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

    it "falls back to global when local exists but file is absent (covers 46[else])" do
      Dir.mktmpdir do |root|
        Dir.mktmpdir do |home|
          stub_env("HOME" => home)
          local = File.join(root, ".git-hooks")
          FileUtils.mkdir_p(local)
          allow(described_class).to receive(:git_toplevel).and_return(root)
          # Do NOT create the file in local; expect global path
          expect(described_class.hooks_path_for("z.txt")).to eq(File.join(home, ".git-hooks", "z.txt"))
        end
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
        expect(described_class.goalie_allows_footer?("feat: add")).to be(false) # covers 60[then]
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

    it "raises when append is true and sentinel missing (covers line 75, 75[then])" do
      Dir.mktmpdir do |dir|
        stub_env(
          "GIT_HOOK_FOOTER_APPEND" => "true",
          "GIT_HOOK_FOOTER_SENTINEL" => nil,
        )
        file = File.join(dir, "COMMIT_EDITMSG")
        File.write(file, "chore: header\n\nbody\n")
        expect { described_class.render(file) }.to raise_error(RuntimeError, /GIT_HOOK_FOOTER_SENTINEL/)
      end
    end

    it "exits early when sentinel already present (covers line 80, 80[then])" do
      Dir.mktmpdir do |dir|
        stub_env(
          "GIT_HOOK_FOOTER_APPEND" => "true",
          "GIT_HOOK_FOOTER_SENTINEL" => "SENT",
        )
        file = File.join(dir, "COMMIT_EDITMSG")
        File.write(file, "feat: header\n\nbody\nSENT\n")
        allow(described_class).to receive(:goalie_allows_footer?).and_return(true)
        expect { described_class.render(file) }.to raise_error(MockSystemExit)
      end
    end

    it "does nothing when append disabled or not allowed (covers 89[else])" do
      Dir.mktmpdir do |dir|
        stub_env(
          "GIT_HOOK_FOOTER_APPEND" => "false",
          "GIT_HOOK_FOOTER_SENTINEL" => "SENT",
        )
        file = File.join(dir, "COMMIT_EDITMSG")
        original = "docs: header\n\nbody\n"
        File.write(file, original)
        expect { described_class.render(file) }.not_to raise_error
        expect(File.read(file)).to eq(original)
      end
    end
  end

  describe "parsing gem name and fallbacks" do
    it "parse_gemspec_name returns nil when assignment missing (covers 113[else], line 118)" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "demo.gemspec"), "Gem::Specification.new do |s|\n# no name here\nend\n")
        Dir.chdir(dir) do
          obj = described_class.new
          expect(obj.send(:parse_gemspec_name)).to be_nil
        end
      end
    end

    it "derive_gem_name returns basename when path present (covers line 122[then])" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "demo.gemspec"), "Gem::Specification.new { |s| s.name = 'demo' }\n")
        Dir.chdir(dir) do
          obj = described_class.new
          expect(obj.send(:derive_gem_name)).to eq("demo")
        end
      end
    end

    it "derive_gem_name returns nil when path missing (covers line 122[else])" do
      obj = described_class.allocate
      obj.instance_variable_set(:@gemspec_path, nil)
      expect(obj.send(:derive_gem_name)).to be_nil
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, ThreadSafety/DirChdir
