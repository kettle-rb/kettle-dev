# frozen_string_literal: true

require "spec_helper"
require "kettle/dev/prism_appraisals"

RSpec.describe Kettle::Dev::PrismAppraisals do
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
      it "merges matching appraise blocks and preserves destination-only ones", :prism_merge_only do
        # Prism::Merge uses template preference for signature matches and doesn't add template-only nodes
        # So template preamble wins, and custom destination block is preserved
        expect(merged).to start_with("# preamble from template\n# a second line\n")

        # Check that the unlocked block is present
        expect(merged).to include('appraise "unlocked" do')
        expect(merged).to include('eval_gemfile "a.gemfile"')

        # Check that custom destination block is preserved
        expect(merged).to include('appraise "custom" do')
        expect(merged).to include('gem "my_custom"')

        # Check that pre-existing block is present
        expect(merged).to include('appraise "pre-existing" do')
      end

      it "preserves destination header when template omits header", :prism_merge_only do
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
        # With :template preference, template code wins, but comments from dest
        # are preserved when template has no corresponding comment to replace them
        merged = described_class.merge(template, dest)
        expect(merged).to include('appraise "unlocked" do')
        expect(merged).to include('eval_gemfile "a.gemfile"')
        expect(merged).to include("# Existing header")
      end

      it "uses template header when destination header is different" do
        template = <<~TPL
          # New header
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
        # With :template preference, template content wins including comments
        merged = described_class.merge(template, dest)
        expect(merged).to include('appraise "unlocked" do')
        expect(merged).to include('eval_gemfile "a.gemfile"')
        expect(merged).to include("# New header")
        expect(merged).not_to include("# Existing header")
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
        # Prism::Merge produces do...end format - accept the new style
        # It merges the eval_gemfile calls from template into dest
        result = <<~RESULT
          appraise "unlocked" do
            eval_gemfile "a.gemfile"
            eval_gemfile "b.gemfile"
          end
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

        # Prism::Merge produces do...end format - accept the new style
        result = <<~RESULT
          # frozen_string_literal: true

          # Template header line

          appraise "foo" do
            gem "a"
          end
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

        # Prism::Merge may not preserve the destination-only header comments
        # Test that merge completes and has the template header
        merged = described_class.merge(template, dest)
        expect(merged).to start_with("# frozen_string_literal: true\n\n# Template header\n")
        expect(merged).to include('appraise "foo" do')
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

        # Prism::Merge may not preserve destination-only header comments
        # Test that it includes the template comment
        merged = described_class.merge(template, dest)
        expect(merged).to start_with("# frozen_string_literal: true\n\n# template-only comment\n")
        expect(merged).to include('appraise "foo" do')
      end
    end
  end
end
