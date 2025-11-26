# frozen_string_literal: true

require "spec_helper"
require "kettle/dev/appraisals_ast_merger"

RSpec.describe Kettle::Dev::AppraisalsAstMerger do
  describe ".merge" do
    subject(:merged) { described_class.merge(template, dest) }

    let(:template) do
      <<~TPL
        # preamble from template
        # a second line

        # Header for unlocked
        appraise "unlocked" do
          eval_gemfile "a.gemfile"
          eval_gemfile "b.gemfile"
        end

        # Header for current
        appraise "current" do
          eval_gemfile "x.gemfile"
        end

        # Header for pre-existing
        appraise "pre-existing" do
          eval_gemfile "pre-existing.gemfile"
        end
      TPL
    end

    let(:dest) do
      <<~DST
        # preamble from dest

        # Old header for unlocked
        appraise "unlocked" do
          eval_gemfile "a.gemfile"
          # keep this custom line
          eval_gemfile "custom.gemfile"
        end

        appraise "custom" do
          gem "my_custom", "~> 1"
        end

        # Header for pre-existing
        appraise "pre-existing" do
          eval_gemfile "old-pre-existing.gemfile"
        end
      DST
    end

    let(:result) do
      <<~RESULT
        # preamble from template
        # a second line
        # preamble from dest

        # Header for unlocked
        # Old header for unlocked
        appraise("unlocked") {
          eval_gemfile("a.gemfile")
          # keep this custom line
          eval_gemfile("custom.gemfile")
          eval_gemfile("b.gemfile")
        }

        # Header for current
        appraise("current") {
          eval_gemfile("x.gemfile")
        }

        appraise("custom") {
          gem("my_custom", "~> 1")
        }

        # Header for pre-existing
        appraise("pre-existing") {
          eval_gemfile("old-pre-existing.gemfile")
          eval_gemfile("pre-existing.gemfile")
        }
      RESULT
    end

    context "with AST-based merge" do
      it "merges matching appraise blocks and preserves destination-only ones" do
        expect(merged).to start_with("# preamble from template\n# a second line\n")
        expect(merged).to include("# preamble from dest")

        unlocked_block = merged[/# Header for unlocked[\s\S]*?appraise\("unlocked"\) \{[\s\S]*?\}\s*/]
        expect(unlocked_block).to include("# Header for unlocked")
        expect(unlocked_block).to include('eval_gemfile("a.gemfile")')
        expect(unlocked_block).to include('eval_gemfile("custom.gemfile")')
        expect(unlocked_block).to include('eval_gemfile("b.gemfile")')

        expect(merged).to match(/appraise\("current"\) \{[\s\S]*eval_gemfile\("x\.gemfile"\)[\s\S]*\}/)
        expect(merged).to include('appraise("custom") {')
        expect(merged).to include('gem("my_custom", "~> 1")')
        expect(merged).to eq(result)
      end

      it "prefers destination header when template omits one" do
        template = <<~TPL
          appraise "unlocked" do
            eval_gemfile "a.gemfile"
          end
        TPL
        dest = <<~DST
          # Existing header
          appraise "unlocked" do
            eval_gemfile "a.gemfile"
          end
        DST
        result = <<~RESULT
          # Existing header
          appraise("unlocked") {
            eval_gemfile("a.gemfile")
          }
        RESULT

        merged = described_class.merge(template, dest)
        expect(merged).to include("# Existing header\nappraise(\"unlocked\") {")
        expect(merged).to eq(result)
      end

      it "is idempotent" do
        template = <<~TPL
          appraise "unlocked" do
            eval_gemfile "a.gemfile"
            eval_gemfile "b.gemfile"
          end
        TPL
        dest = <<~DST
          appraise "unlocked" do
            eval_gemfile "a.gemfile"
          end
        DST
        result = <<~RESULT
          appraise("unlocked") {
            eval_gemfile("a.gemfile")
            eval_gemfile("b.gemfile")
          }
        RESULT

        once = described_class.merge(template, dest)
        twice = described_class.merge(template, once)
        expect(twice).to eq(once)
        expect(once).to eq(result)
      end

      it "keeps a single header copy when template and destination already match" do
        template = <<~TPL
          # frozen_string_literal: true
          # Template header line

          appraise "foo" do
            gem "a"
          end
        TPL

        dest = <<~DST
          # frozen_string_literal: true
          # Template header line

          appraise "foo" do
            gem "a"
          end
        DST

        result = <<~RESULT
          # frozen_string_literal: true
          # Template header line

          appraise("foo") {
            gem("a")
          }
        RESULT

        merged = described_class.merge(template, dest)
        expect(merged.scan("# Template header line").size).to eq(1)
        expect(merged).to eq(result)
      end

      it "appends destination header, without duplicating the magic comment, when template provides one" do
        template = <<~TPL
          # frozen_string_literal: true
          # Template header

          appraise "foo" do
            gem "a"
          end
        TPL

        dest = <<~DST
          # frozen_string_literal: true
          # old header line 1
          # old header line 2

          appraise "foo" do
            gem "a"
          end
        DST

        result = <<~RESULT
          # frozen_string_literal: true
          # Template header
          # old header line 1
          # old header line 2

          appraise("foo") {
            gem("a")
          }
        RESULT

        merged = described_class.merge(template, dest)
        expect(merged).to start_with("# frozen_string_literal: true\n# Template header\n# old header line 1\n")
        expect(merged).to include("# old header line 2")
        expect(merged).to eq(result)
      end

      it "preserves template magic comments, and appends destination header" do
        template = <<~TPL
          # frozen_string_literal: true
          # template-only comment

          appraise "foo" do
            eval_gemfile "a.gemfile"
          end
        TPL

        dest = <<~DST
          # some legacy header

          appraise "foo" do
            eval_gemfile "a.gemfile"
          end
        DST

        result = <<~RESULT
          # frozen_string_literal: true
          # template-only comment
          # some legacy header

          appraise("foo") {
            eval_gemfile("a.gemfile")
          }
        RESULT

        merged = described_class.merge(template, dest)
        expect(merged).to start_with("# frozen_string_literal: true\n# template-only comment\n# some legacy header\n")
        expect(merged).to eq(result)
      end
    end
  end
end
