# frozen_string_literal: true

require "kettle/dev/template_helpers"

RSpec.describe Kettle::Dev::TemplateHelpers do
  describe ".merge_gemfile_dependencies" do
    it "replaces source line and github git_source with template values" do
      src = <<~'SRC'
        source "https://gem.coop"
        git_source(:codeberg) { |repo_name| "https://codeberg.org/#{repo_name}" }
      SRC

      dest = <<~'DEST'
        # frozen_string_literal: true

        source "https://rubygems.org"

        git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

        gem "rake"
      DEST

      out = described_class.merge_gemfile_dependencies(src, dest)
      expect(out).to include("source \"https://gem.coop\"")
      expect(out).to include("git_source(:codeberg)")
      # ensure github was replaced (no lingering github url)
      expect(out).not_to include("github.com")
      # existing gem lines are preserved
      expect(out).to include('gem "rake"')
    end

    it "inserts git_source below source when no github present" do
      src = <<~'SRC'
        source "https://gem.coop"
        git_source(:codeberg) { |repo_name| "https://codeberg.org/#{repo_name}" }
      SRC

      dest = <<~DEST
        # frozen_string_literal: true

        # some comment
        gemspec
      DEST

      out = described_class.merge_gemfile_dependencies(src, dest)
      # git_source should appear near the top (after source)
      expect(out).to match(/source .*\n.*git_source/m)
    end

    it "replaces github and inserts additional git_source lines in order" do
      src = <<~'SRC'
        source "https://gem.coop"
        git_source(:codeberg) { |repo_name| "https://codeberg.org/#{repo_name}" }
        git_source(:gitlab)  { |repo_name| "https://gitlab.com/#{repo_name}" }
      SRC

      dest = <<~'DEST'
        # frozen_string_literal: true

        # header comment
        source "https://rubygems.org"
        # an unrelated comment
        git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }
        git_source(:bitbucket) { |repo_name| "https://bitbucket.org/#{repo_name}" }

        gem "a"
      DEST

      out = described_class.merge_gemfile_dependencies(src, dest)
      # Source replaced
      expect(out).to include("source \"https://gem.coop\"")
      expect(out).not_to include("rubygems.org")
      # github replaced with codeberg, bitbucket preserved, gitlab inserted
      expect(out).to include("git_source(:codeberg)")
      expect(out).to include("git_source(:gitlab)")
      expect(out).to include("git_source(:bitbucket)")
      expect(out).not_to include("github.com")

      # Ensure order: source, codeberg, then gitlab should appear (relative order preserved)
      lines = out.lines
      src_i = lines.index { |l| l =~ /\Asource\s+\"https:\/\/gem\.coop\"/ }
      codeberg_i = lines.index { |l| l.include?("git_source(:codeberg)") }
      gitlab_i = lines.index { |l| l.include?("git_source(:gitlab)") }
      expect(src_i).to be < codeberg_i
      expect(codeberg_i).to be < gitlab_i
    end

    it "inserts source at top if destination has none, then inserts git_source below it" do
      src = <<~'SRC'
        source "https://gem.coop"
        git_source(:codeberg) { |repo_name| "https://codeberg.org/#{repo_name}" }
      SRC

      dest = <<~DEST
        # Top comment block
        # Another comment

        gemspec
        gem "a"
      DEST

      out = described_class.merge_gemfile_dependencies(src, dest)
      lines = out.lines
      # First non-comment non-blank line should be the source line
      first_code_line_idx = lines.index { |l| l !~ /^\s*#/ && !l.strip.empty? }
      expect(lines[first_code_line_idx]).to match(/\Asource\s+\"https:\/\/gem\.coop\"/)
      # Next line should be git_source
      expect(lines[first_code_line_idx + 1]).to include("git_source(:codeberg)")
    end

    it "appends missing gem lines from template but does not duplicate existing ones" do
      src = <<~SRC
        source "https://gem.coop"
        gem "foo"
        gem "bar", "~> 1.2"
      SRC

      dest = <<~DEST
        source "https://rubygems.org"
        gem "foo"
      DEST

      out = described_class.merge_gemfile_dependencies(src, dest)
      # foo should appear only once, bar should be appended
      expect(out.scan(/^\s*gem\s+['"]foo['"]/).size).to eq(1)
      expect(out).to match(/^\s*gem\s+['"]bar['"].*~> 1\.2/m)
    end

    it "replaces same-named git_source if present (no github fallback)" do
      src = <<~'SRC'
        source "https://gem.coop"
        git_source(:bitbucket) { |repo_name| "https://bitbucket.org/#{repo_name}" }
      SRC

      dest = <<~'DEST'
        # Header
        source "https://rubygems.org"
        git_source(:bitbucket) { |repo_name| "https://bb.org/#{repo_name}" }
      DEST

      out = described_class.merge_gemfile_dependencies(src, dest)
      expect(out).to include('git_source(:bitbucket) { |repo_name| "https://bitbucket.org/#{repo_name}" }')
      expect(out).not_to include("https://bb.org/")
    end
  end
end
