# frozen_string_literal: true

RSpec.describe "Gemfile parsing idempotency" do
  describe "SourceMerger idempotency with duplicate sections" do
    let(:initial_gemfile_with_duplicates) do
      <<~GEMFILE
        # frozen_string_literal: true
        # frozen_string_literal: true
        # frozen_string_literal: true

        # We run code coverage on the latest version of Ruby only.

        # Coverage
        # See gemspec
        # To retain during kettle-dev templating:
        #     kettle-dev:freeze
        #     # ... your code
        #     kettle-dev:unfreeze


        # We run code coverage on the latest version of Ruby only.

        # Coverage

        # To retain during kettle-dev templating:
        #     kettle-dev:freeze
        #     # ... your code
        #     kettle-dev:unfreeze


        # We run code coverage on the latest version of Ruby only.

        # Coverage
      GEMFILE
    end

    let(:expected_deduplicated_content) do
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

    it "consolidates duplicates on first run and makes no changes on subsequent runs" do
      path = "gemfiles/modular/coverage.gemfile"

      # First run - should consolidate duplicates
      first_result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: initial_gemfile_with_duplicates,
        dest: "",
        path: path,
      )

      # Second run - should be idempotent (no changes)
      second_result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: first_result,
        dest: "",
        path: path,
      )

      # Third run for good measure
      third_result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: second_result,
        dest: "",
        path: path,
      )

      # Verify results are stable after first consolidation
      expect(second_result).to eq(first_result), "Second run should not change the file"
      expect(third_result).to eq(second_result), "Third run should not change the file"

      # Verify duplicate frozen_string_literal comments are consolidated
      frozen_literal_count = first_result.scan("# frozen_string_literal: true").count
      expect(frozen_literal_count).to eq(1), "Should have exactly one frozen_string_literal comment"

      # Verify duplicate comment sections are consolidated
      coverage_comment_count = first_result.scan("# We run code coverage on the latest version of Ruby only.").count
      expect(coverage_comment_count).to eq(1), "Should have exactly one coverage comment"
    end

    it "handles merge strategy with duplicate sections idempotently" do
      path = "gemfiles/modular/coverage.gemfile"

      # Simulate multiple merge operations
      first_merge = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: initial_gemfile_with_duplicates,
        dest: "",
        path: path,
      )

      second_merge = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: first_merge,
        dest: first_merge,
        path: path,
      )

      third_merge = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: second_merge,
        dest: second_merge,
        path: path,
      )

      # Results should stabilize
      expect(second_merge).to eq(first_merge), "Merging with self should not duplicate content"
      expect(third_merge).to eq(second_merge), "Third merge should not change content"
    end

    it "removes duplicate frozen_string_literal comments" do
      path = "Gemfile"
      content = <<~GEMFILE
        # frozen_string_literal: true
        # frozen_string_literal: true
        # frozen_string_literal: true

        gem "foo"
      GEMFILE

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: content,
        dest: "",
        path: path,
      )

      frozen_count = result.scan("# frozen_string_literal: true").count
      expect(frozen_count).to eq(1), "Should consolidate to single frozen_string_literal comment"
    end

    it "removes duplicate comment sections ignoring trailing whitespace differences" do
      path = "Gemfile"
      content_with_whitespace_variations = <<~GEMFILE
        # frozen_string_literal: true

        # Important comment  
        # Second line

        # Important comment
        # Second line  

        # Important comment
        # Second line
      GEMFILE

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: content_with_whitespace_variations,
        dest: "",
        path: path,
      )

      # Should only have one occurrence of the comment block
      important_comment_count = result.scan("# Important comment").count
      expect(important_comment_count).to eq(1), "Should consolidate duplicate comment blocks"

      second_line_count = result.scan("# Second line").count
      expect(second_line_count).to eq(1), "Should consolidate second line of comment block"
    end

    it "consolidates duplicate freeze reminder blocks" do
      path = "Gemfile"
      content = <<~GEMFILE
        # frozen_string_literal: true

        # To retain during kettle-dev templating:
        #     kettle-dev:freeze
        #     # ... your code
        #     kettle-dev:unfreeze

        # To retain during kettle-dev templating:
        #     kettle-dev:freeze
        #     # ... your code
        #     kettle-dev:unfreeze

        gem "foo"
      GEMFILE

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: content,
        dest: "",
        path: path,
      )

      reminder_count = result.scan("# To retain during kettle-dev templating:").count
      expect(reminder_count).to eq(1), "Should have exactly one freeze reminder"
    end

    it "handles complex duplicated sections with mixed content" do
      path = "gemfiles/modular/coverage.gemfile"
      complex_content = <<~GEMFILE
        # frozen_string_literal: true
        # frozen_string_literal: true

        # Section A
        # More info

        gem "foo"

        # Section A
        # More info

        gem "bar"

        # Section A
        # More info

        gem "baz"
      GEMFILE

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: complex_content,
        dest: "",
        path: path,
      )

      # Frozen literal should be consolidated
      frozen_count = result.scan("# frozen_string_literal: true").count
      expect(frozen_count).to eq(1)

      # Section A comment appears before each gem (leading comments are preserved per statement)
      section_a_count = result.scan("# Section A").count
      expect(section_a_count).to eq(3), "Leading comments for each statement should be preserved"

      # All gems should still be present
      expect(result).to include('gem "foo"')
      expect(result).to include('gem "bar"')
      expect(result).to include('gem "baz"')
    end

    it "preserves leading comments attached to different statements (does NOT deduplicate)" do
      path = "Gemfile"
      content = <<~GEMFILE
        # frozen_string_literal: true

        # This comment describes foo
        gem "foo"

        # This comment describes foo
        gem "bar"

        # Common comment
        # More details
        gem "baz"

        # Common comment
        # More details
        gem "qux"
      GEMFILE

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: content,
        dest: "",
        path: path,
      )

      # Leading comments are attached to their statements and should NOT be deduplicated
      expect(result.scan("# This comment describes foo").count).to eq(2),
        "Each statement keeps its own leading comment even if text is identical"

      expect(result.scan("# Common comment").count).to eq(2),
        "Multi-line leading comments are preserved per statement"

      # All gems should be present
      expect(result).to include('gem "foo"')
      expect(result).to include('gem "bar"')
      expect(result).to include('gem "baz"')
      expect(result).to include('gem "qux"')
    end

    it "deduplicates statements AND their comments when using merge strategy" do
      path = "Gemfile"
      content = <<~GEMFILE
        # frozen_string_literal: true

        # This is the first foo
        gem "foo"

        # This is the second foo
        gem "foo"

        # This is bar
        gem "bar"

        # Another bar comment
        gem "bar"
      GEMFILE

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: content,
        dest: "",
        path: path,
      )

      # Duplicate statements should be deduplicated (only first occurrence kept)
      expect(result.scan(/gem ["']foo["']/).count).to eq(1),
        "Duplicate gem statements should be deduplicated"

      expect(result.scan(/gem ["']bar["']/).count).to eq(1),
        "Duplicate gem statements should be deduplicated"

      # Only the first occurrence's comment should remain
      expect(result).to include("# This is the first foo"),
        "First occurrence's comment should be preserved"
      expect(result).not_to include("# This is the second foo"),
        "Duplicate statement's comment should be removed with the statement"

      expect(result).to include("# This is bar"),
        "First occurrence's comment should be preserved"
      expect(result).not_to include("# Another bar comment"),
        "Duplicate statement's comment should be removed with the statement"
    end

    it "skip strategy does NOT deduplicate statements (only deduplicates file-level comments)" do
      path = "Gemfile"
      content = <<~GEMFILE
        # frozen_string_literal: true

        # Comment for first foo
        gem "foo"

        # Comment for second foo
        gem "foo"
      GEMFILE

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: content,
        dest: "",
        path: path,
      )

      # Skip strategy only normalizes and deduplicates file-level comments
      # It does NOT deduplicate statements
      expect(result.scan(/gem ["']foo["']/).count).to eq(2),
        "Skip strategy preserves all statements, even duplicates"

      expect(result).to include("# Comment for first foo")
      expect(result).to include("# Comment for second foo")
    end

    it "append strategy deduplicates duplicate statements from source" do
      path = "Gemfile"
      src_with_dupes = <<~GEMFILE
        # frozen_string_literal: true

        # First foo
        gem "foo"

        # Second foo (duplicate)
        gem "foo"

        gem "bar"
      GEMFILE

      dest = <<~GEMFILE
        # frozen_string_literal: true

        gem "baz"
      GEMFILE

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :append,
        src: src_with_dupes,
        dest: dest,
        path: path,
      )

      # Should have deduplicated foo in src, then appended to dest
      expect(result.scan(/gem ["']foo["']/).count).to eq(1),
        "Append strategy should deduplicate source before appending"

      expect(result.scan(/gem ["']bar["']/).count).to eq(1)
      expect(result.scan(/gem ["']baz["']/).count).to eq(1)

      # Only first foo's comment should remain
      expect(result).to include("# First foo")
      expect(result).not_to include("# Second foo (duplicate)")
    end
  end

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

      # All runs after the first should produce identical output
      expect(second_run).to eq(first_run), "Second template run should not modify stable file"
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
