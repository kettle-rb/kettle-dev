# frozen_string_literal: true

RSpec.describe "Gemfile parsing idempotency" do
  describe "PrismGemfile merge idempotency" do
    it "does not duplicate gems when merging repeatedly" do
      src = <<~GEMFILE
        # frozen_string_literal: true

        gem "foo"
        gem "bar"
      GEMFILE

      dest = <<~GEMFILE
        # frozen_string_literal: true

        gem "foo"
      GEMFILE

      # First merge
      first_merge = Kettle::Dev::PrismGemfile.merge_gem_calls(src, dest)

      # Second merge (merging result with itself)
      second_merge = Kettle::Dev::PrismGemfile.merge_gem_calls(first_merge, first_merge)

      # Third merge
      third_merge = Kettle::Dev::PrismGemfile.merge_gem_calls(second_merge, second_merge)

      # Count gems - should not increase
      foo_count_1 = first_merge.scan(/gem ["']foo["']/).count
      foo_count_2 = second_merge.scan(/gem ["']foo["']/).count
      foo_count_3 = third_merge.scan(/gem ["']foo["']/).count

      expect(foo_count_1).to eq(1)
      expect(foo_count_2).to eq(1), "Second merge should not duplicate gem 'foo'"
      expect(foo_count_3).to eq(1), "Third merge should not duplicate gem 'foo'"

      bar_count_1 = first_merge.scan(/gem ["']bar["']/).count
      bar_count_2 = second_merge.scan(/gem ["']bar["']/).count
      bar_count_3 = third_merge.scan(/gem ["']bar["']/).count

      expect(bar_count_1).to eq(1)
      expect(bar_count_2).to eq(1), "Second merge should not duplicate gem 'bar'"
      expect(bar_count_3).to eq(1), "Third merge should not duplicate gem 'bar'"

      expect(first_merge).to eq(second_merge), "Second merge should be identical to first"
      expect(second_merge).to eq(third_merge), "Third merge should be identical to second"
    end

    it "does not duplicate frozen_string_literal comments" do
      src = <<~GEMFILE
        # frozen_string_literal: true
        # frozen_string_literal: true

        gem "foo"
      GEMFILE

      dest = <<~GEMFILE
        # frozen_string_literal: true

        gem "bar"
      GEMFILE

      result = Kettle::Dev::PrismGemfile.merge_gem_calls(src, dest)

      # Note: PrismGemfile doesn't handle comment deduplication - that's SourceMerger's job
      # But we should verify it doesn't make things worse
      frozen_count = result.scan("# frozen_string_literal: true").count
      expect(frozen_count).to be <= 2, "Should not add more frozen_string_literal comments than input"
    end
  end

  describe "Real-world scenario: multiple template runs" do
    let(:template_source) do
      <<~GEMFILE
        # frozen_string_literal: true

        # To retain during kettle-dev templating:
        #     kettle-dev:freeze
        #     # ... your code
        #     kettle-dev:unfreeze

        # We run code coverage on the latest version of Ruby only.

        # Coverage
      GEMFILE
    end

    it "remains stable across multiple template applications with apply_strategy flow" do
      path = "gemfiles/modular/coverage.gemfile"

      # Simulate first template run (initial file creation)
      first_run = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: template_source,
        dest: "",
        path: path,
      )

      # Simulate second template run (file already exists)
      second_run = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: template_source,
        dest: first_run,
        path: path,
      )

      # Simulate third template run
      third_run = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: template_source,
        dest: second_run,
        path: path,
      )

      # Simulate fourth template run
      fourth_run = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: template_source,
        dest: third_run,
        path: path,
      )

      # After the second run, output should stabilize.
      # Note: First->second run may have whitespace normalization due to
      # Comment::Parser grouping behavior, but subsequent runs should be stable.
      expect(third_run).to eq(second_run), "Third template run should not modify stable file"
      expect(fourth_run).to eq(third_run), "Fourth template run should not modify stable file"

      # Verify no accumulation of duplicate content
      frozen_count = fourth_run.scan("# frozen_string_literal: true").count
      expect(frozen_count).to eq(1), "Should maintain single frozen_string_literal after multiple runs"

      coverage_count = fourth_run.scan("# Coverage").count
      expect(coverage_count).to eq(1), "Should maintain single Coverage comment after multiple runs"

      reminder_count = fourth_run.scan("# To retain during kettle-dev templating:").count
      expect(reminder_count).to eq(1), "Should maintain single reminder block after multiple runs"
    end
  end
end
