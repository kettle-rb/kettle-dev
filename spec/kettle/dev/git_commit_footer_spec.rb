# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe GitCommitFooter do
  describe "::hooks_path_for" do
    it "prefers local hooks when file exists, otherwise uses global" do
      Dir.mktmpdir("hooks_global") do |gdir|
        Dir.mktmpdir("hooks_local") do |ldir|
          file = "commit-subjects-goalie.txt"
          gpath = File.join(gdir, file)
          lpath = File.join(ldir, file)
          File.write(gpath, "# global\n")
          # Stub the directories
          allow(described_class).to receive(:global_hooks_dir).and_return(gdir)
          allow(described_class).to receive(:local_hooks_dir).and_return(ldir)
          # With only global
          expect(described_class.hooks_path_for(file)).to eq(gpath)
          # Now create local and expect it to take precedence
          File.write(lpath, "# local\n")
          expect(described_class.hooks_path_for(file)).to eq(lpath)
        end
      end
    end
  end

  describe "::goalie_allows_footer?" do
    it "returns true when subject starts with any non-comment prefix in goalie file" do
      Dir.mktmpdir("hooks") do |dir|
        allow(described_class).to receive(:commit_goalie_path).and_return(File.join(dir, "commit-subjects-goalie.txt"))
        File.write(File.join(dir, "commit-subjects-goalie.txt"), <<~TXT)
          # comment
          
          feat:
          chore:
        TXT
        expect(described_class.goalie_allows_footer?("feat: add X")).to be true
        expect(described_class.goalie_allows_footer?("chore: tidy")).to be true
        expect(described_class.goalie_allows_footer?("fix: bug")).to be false
      end
    end

    it "returns false when goalie file missing or has no usable prefixes" do
      allow(described_class).to receive(:commit_goalie_path).and_return("/nonexistent/path")
      expect(described_class.goalie_allows_footer?("feat: x")).to be false
      Dir.mktmpdir("hooks") do |dir|
        allow(described_class).to receive(:commit_goalie_path).and_return(File.join(dir, "commit-subjects-goalie.txt"))
        File.write(File.join(dir, "commit-subjects-goalie.txt"), "# only comments\n")
        expect(described_class.goalie_allows_footer?("feat: x")).to be false
      end
    end
  end
end
