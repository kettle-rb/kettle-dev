# frozen_string_literal: true

require "spec_helper"
require "kettle/dev/template_helpers"

RSpec.describe Kettle::Dev::TemplateHelpers do
  let(:helpers) { described_class }

  describe "#merge_appraisals" do
    it "merges matching appraisals, preserves destination-only blocks, and keeps appropriate headers and preamble" do
      template = <<~TPL
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
      TPL

      dest = <<~DST
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
      DST

      merged = helpers.merge_appraisals(template, dest)

      # Preamble should come from template when present
      expect(merged).to start_with("# preamble from template\n# a second line\n")
      expect(merged).not_to include("# preamble from dest")

      # The 'unlocked' block should:
      # - Use the template header
      # - Contain existing dest lines and appended missing b.gemfile
      unlocked_block = merged[/# Header for unlocked[\s\S]*?appraise \"unlocked\" do[\s\S]*?end\s*/]
      expect(unlocked_block).to include("# Header for unlocked")
      expect(unlocked_block).to include('eval_gemfile "a.gemfile"')
      expect(unlocked_block).to include('eval_gemfile "custom.gemfile"')
      expect(unlocked_block).to include('eval_gemfile "b.gemfile"')

      # The 'current' block from template should be present
      expect(merged).to match(/appraise \"current\" do[\s\S]*eval_gemfile \"x\.gemfile\"[\s\S]*end/)

      # Destination-only 'custom' block should be preserved
      expect(merged).to match(/appraise \"custom\" do[\s\S]*gem \"my_custom\"/)
    end

    it "retains destination header when template has none for a matching block" do
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

      merged = helpers.merge_appraisals(template, dest)
      unlocked_block = merged[/appraise \"unlocked\" do[\s\S]*?end\s*/]
      # ensure the dest header remains adjacent before the appraise line
      expect(merged).to include("# Existing header\nappraise \"unlocked\" do")
      expect(unlocked_block).to include('eval_gemfile "a.gemfile"')
    end

    it "is idempotent when run twice" do
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

      once = helpers.merge_appraisals(template, dest)
      twice = helpers.merge_appraisals(template, once)
      expect(twice).to eq(once)
    end
  end
end

