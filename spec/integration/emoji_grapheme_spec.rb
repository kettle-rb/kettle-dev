# frozen_string_literal: true

RSpec.describe "Emoji/Grapheme Extraction and Synchronization" do
  describe "Kettle::Dev::PrismGemspec.extract_leading_emoji" do
    it "extracts a single emoji from the beginning of text" do
      expect(Kettle::Dev::PrismGemspec.extract_leading_emoji("🍲 Some text")).to eq("🍲")
    end

    it "extracts a complex emoji (multi-codepoint) from the beginning" do
      expect(Kettle::Dev::PrismGemspec.extract_leading_emoji("👨‍💻 Developer")).to eq("👨‍💻")
    end

    it "returns nil when text doesn't start with emoji" do
      expect(Kettle::Dev::PrismGemspec.extract_leading_emoji("No emoji here")).to be_nil
    end

    it "returns nil for empty or nil text" do
      expect(Kettle::Dev::PrismGemspec.extract_leading_emoji("")).to be_nil
      expect(Kettle::Dev::PrismGemspec.extract_leading_emoji(nil)).to be_nil
    end

    it "extracts emoji even if followed immediately by text (no space)" do
      expect(Kettle::Dev::PrismGemspec.extract_leading_emoji("🎉Party")).to eq("🎉")
    end
  end

  describe "Kettle::Dev::PrismGemspec.extract_readme_h1_emoji" do
    it "extracts emoji from README H1 heading" do
      readme = <<~MD
        # 🍲 My Amazing Project

        Some description here.
      MD

      expect(Kettle::Dev::PrismGemspec.extract_readme_h1_emoji(readme)).to eq("🍲")
    end

    it "returns nil when README H1 has no emoji" do
      readme = <<~MD
        # My Project Without Emoji

        Description.
      MD

      expect(Kettle::Dev::PrismGemspec.extract_readme_h1_emoji(readme)).to be_nil
    end

    it "handles README with multiple headings (uses first H1)" do
      readme = <<~MD
        # 🚀 First Project

        ## 🎯 Second Heading

        Some content.
      MD

      expect(Kettle::Dev::PrismGemspec.extract_readme_h1_emoji(readme)).to eq("🚀")
    end

    it "returns nil for empty or nil README" do
      expect(Kettle::Dev::PrismGemspec.extract_readme_h1_emoji("")).to be_nil
      expect(Kettle::Dev::PrismGemspec.extract_readme_h1_emoji(nil)).to be_nil
    end

    it "handles README with no H1 heading" do
      readme = "Just some text without headings"
      expect(Kettle::Dev::PrismGemspec.extract_readme_h1_emoji(readme)).to be_nil
    end
  end

  # Emoji normalization is tested through replace_gemspec_fields below
  # These tests document the expected behavior without a separate normalize_with_emoji method

  describe "Integration: full gemspec templating with emoji sync" do
    let(:fixture_path) { File.expand_path("../support/fixtures/example-kettle-soup-cover.gemspec", __dir__) }
    let(:fixture_content) { File.read(fixture_path) }
    let(:readme_with_matching_emoji) do
      <<~MD
        # 🍲 Kettle Soup Cover

        A Covered Kettle of Test Coverage.
      MD
    end
    let(:readme_with_different_emoji) do
      <<~MD
        # 🥘 Different Emoji Project

        Description.
      MD
    end

    it "preserves destination content when template has placeholders" do
      result = Kettle::Dev::PrismGemspec.replace_gemspec_fields(
        fixture_content,
        {
          summary: "🥘 ",
          description: "🥘 "
        }
      )

      # Should preserve the actual content from fixture
      expect(result).to include("🍲 kettle-rb OOTB SimpleCov config")
      expect(result).to match(/A Covered Kettle of Test Coverage SOUP/)

      # Verify valid syntax
      parse_result = Prism.parse(result)
      expect(parse_result.success?).to be(true)
    end

    it "extracts emoji from README H1" do
      emoji = Kettle::Dev::PrismGemspec.extract_readme_h1_emoji(readme_with_matching_emoji)
      expect(emoji).to eq("🍲")
    end

    it "syncs README H1 emoji with gemspec" do
      readme_no_emoji = "# Project Title\n\nDescription"

      result = Kettle::Dev::PrismGemspec.sync_readme_h1_emoji(
        readme_content: readme_no_emoji,
        gemspec_content: fixture_content
      )

      expect(result).to include("# 🍲 Project Title")
    end
  end

  describe "README H1 synchronization" do
    it "updates README H1 to match gemspec emoji when README lacks emoji" do
      readme_without_emoji = "# My Project\n\nDescription"
      gemspec_with_emoji = <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "my-gem"
          spec.summary = "🍲 Summary"
          spec.description = "🍲 Description"
        end
      RUBY

      result = Kettle::Dev::PrismGemspec.sync_readme_h1_emoji(
        readme_content: readme_without_emoji,
        gemspec_content: gemspec_with_emoji
      )

      expect(result).to include("# 🍲 My Project")
      expect(result).not_to include("# My Project\n")
    end

    it "does not change README when it already has correct emoji" do
      readme_with_emoji = "# 🍲 My Project\n\nDescription"
      gemspec_with_emoji = <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "my-gem"
          spec.summary = "🍲 Summary"
        end
      RUBY

      result = Kettle::Dev::PrismGemspec.sync_readme_h1_emoji(
        readme_content: readme_with_emoji,
        gemspec_content: gemspec_with_emoji
      )

      expect(result).to eq(readme_with_emoji)
    end

    it "updates README when it has different emoji than gemspec" do
      readme_different_emoji = "# 🥘 My Project\n\nDescription"
      gemspec_with_emoji = <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.summary = "🍲 Summary"
        end
      RUBY

      result = Kettle::Dev::PrismGemspec.sync_readme_h1_emoji(
        readme_content: readme_different_emoji,
        gemspec_content: gemspec_with_emoji
      )

      expect(result).to include("# 🍲 My Project")
      expect(result).not_to include("# 🥘 My Project")
    end
  end
end

