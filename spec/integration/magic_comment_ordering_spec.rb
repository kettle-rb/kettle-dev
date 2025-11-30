# frozen_string_literal: true

RSpec.describe "Magic Comment Ordering and Freeze Block Protection" do
  describe "Kettle::Dev::SourceMerger" do
    context "when processing magic comments" do
      it "preserves the original order of magic comments" do
        input = <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem "foo"
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.rb",
        )

        lines = result.lines
        expect(lines[0]).to include("coding:")
        expect(lines[1]).to include("frozen_string_literal:")
      end

      it "does not insert blank lines between magic comments" do
        input = <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem "foo"
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.rb",
        )

        lines = result.lines
        # Lines 0 and 1 should be magic comments with no blank line between
        expect(lines[0].strip).to start_with("#")
        expect(lines[1].strip).to start_with("#")
        expect(lines[2].strip).to eq("") # Blank line after magic comments
      end

      it "inserts single blank line after all magic comments" do
        input = <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem "foo"
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.rb",
        )

        lines = result.lines
        expect(lines[2].strip).to eq("") # Single blank line after magic comments
      end

      it "recognizes 'coding:' as a magic comment using Prism" do
        input = <<~RUBY
          # coding: utf-8

          gem "foo"
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.rb",
        )

        lines = result.lines
        expect(lines[0]).to include("coding:")
        expect(lines[1].strip).to eq("") # Blank line after magic comment
      end
    end

    context "when processing freeze reminder blocks" do
      it "keeps the freeze reminder block intact as a single unit" do
        input = <<~RUBY
          # frozen_string_literal: true

          gem "foo"
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.rb",
        )

        # Find the freeze block lines
        lines = result.lines
        freeze_idx = lines.index { |l| l.include?("kettle-dev:freeze") }
        unfreeze_idx = lines.index { |l| l.include?("kettle-dev:unfreeze") }

        expect(freeze_idx).not_to be_nil
        expect(unfreeze_idx).not_to be_nil
        expect(unfreeze_idx - freeze_idx).to eq(2) # Should be 3 consecutive lines
      end

      it "does not merge freeze reminder with magic comments" do
        input = <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem "foo"
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.rb",
        )

        lines = result.lines
        # Magic comments should be lines 0-1
        expect(lines[0]).to include("coding:")
        expect(lines[1]).to include("frozen_string_literal:")

        # Blank line separator
        expect(lines[2].strip).to eq("")

        # Freeze reminder should start at line 3
        expect(lines[3]).to include("To retain during kettle-dev templating")
      end

      it "treats kettle-dev:freeze and unfreeze as file-level comments, not magic" do
        input = <<~RUBY
          # frozen_string_literal: true

          gem "foo"
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.rb",
        )

        # The freeze/unfreeze markers should not be treated as Ruby magic comments
        # and should stay with the freeze reminder block
        lines = result.lines
        freeze_header_idx = lines.index { |l| l.include?("To retain during kettle-dev templating") }
        freeze_idx = lines.index { |l| l.include?("kettle-dev:freeze") }

        expect(freeze_header_idx).not_to be_nil
        expect(freeze_idx).not_to be_nil
        expect(freeze_idx - freeze_header_idx).to eq(1) # freeze marker right after header
      end
    end

    context "when running complete integration test for reported bug" do
      it "fixes all three reported problems" do
        input = <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "example"
          end
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.gemspec",
        )

        lines = result.lines

        # Problem 1: Magic comments should NOT be re-ordered
        expect(lines[0]).to include("coding:")
        expect(lines[1]).to include("frozen_string_literal:")

        # Problem 2: Magic comments should NOT be separated by a blank line
        # (lines 0 and 1 are consecutive magic comments)
        expect(lines[0].strip).to start_with("#")
        expect(lines[1].strip).to start_with("#")

        # Problem 3: Freeze reminder should NOT be merged with last magic comment
        # There should be a blank line (line 2) separating them
        expect(lines[2].strip).to eq("")
        expect(lines[3]).to include("To retain during kettle-dev templating")

        # Verify freeze block integrity
        freeze_idx = lines.index { |l| l.include?("kettle-dev:freeze") }
        unfreeze_idx = lines.index { |l| l.include?("kettle-dev:unfreeze") }
        expect(unfreeze_idx - freeze_idx).to eq(2) # 3 lines in freeze block
      end
    end
  end
end
