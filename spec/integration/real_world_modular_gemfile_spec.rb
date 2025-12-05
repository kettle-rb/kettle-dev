# frozen_string_literal: true

RSpec.describe "Real-world modular gemfile deduplication" do
  let(:fixture_content) do
    File.read("spec/support/fixtures/modular_gemfile_with_duplicates.gemfile")
  end

  let(:template_source_content) do
    <<~GEMFILE
      # frozen_string_literal: true

      # We run code coverage on the latest version of Ruby only.

      # Coverage
    GEMFILE
  end

  describe "Simulating kettle-dev-setup flow" do
    it "deduplicates magic comments but preserves all other content when merging" do
      # This simulates what happens when kettle-dev-setup runs:
      # 1. Source (template) is the simple coverage.gemfile from kettle-dev
      # 2. Dest is the existing file in the target project with accumulated duplicates
      # prism-merge deduplicates magic comments but preserves all other content

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :replace,
        src: template_source_content,
        dest: fixture_content,
        path: "gemfiles/modular/coverage.gemfile",
      )

      # Should have exactly 1 frozen_string_literal (magic comments are deduplicated)
      frozen_count = result.scan("# frozen_string_literal: true").count
      expect(frozen_count).to eq(1), "Expected 1 frozen_string_literal, got #{frozen_count}\nResult:\n#{result}"

      # Regular comments are NOT deduplicated - prism-merge preserves all content
      # The fixture has 4 instances and they should all be preserved
      coverage_count = result.scan("# We run code coverage").count
      expect(coverage_count).to eq(4), "Expected 4 coverage comments (preserved from fixture), got #{coverage_count}\nResult:\n#{result}"

      # Running again should be idempotent
      second_result = Kettle::Dev::SourceMerger.apply(
        strategy: :replace,
        src: template_source_content,
        dest: result,
        path: "gemfiles/modular/coverage.gemfile",
      )

      expect(second_result).to eq(result), "Second run should produce identical output"
    end

    it "removes duplicated frozen_string_literal comments, but not other duplicate comments" do
      # User reported running kettle-dev-setup --allowed=true --force
      # which uses --force to set allow_replace: true
      # This means it uses :replace strategy

      # Starting state: file with 4 frozen_string_literal comments
      starting_dest = <<~GEMFILE
        # frozen_string_literal: true
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
      GEMFILE

      # Template source is simple
      template = <<~GEMFILE
        # frozen_string_literal: true

        # We run code coverage on the latest version of Ruby only.

        # Coverage
      GEMFILE

      # First run
      first_run = Kettle::Dev::SourceMerger.apply(
        strategy: :replace,
        src: template,
        dest: starting_dest,
        path: "gemfiles/modular/coverage.gemfile",
      )

      frozen_count = first_run.scan("# frozen_string_literal: true").count
      expect(frozen_count).to eq(1), "First run should deduplicate to 1 frozen_string_literal, got #{frozen_count}\nResult:\n#{first_run}"

      # Second run (simulating running kettle-dev-setup again)
      second_run = Kettle::Dev::SourceMerger.apply(
        strategy: :replace,
        src: template,
        dest: first_run,
        path: "gemfiles/modular/coverage.gemfile",
      )

      frozen_count_2 = second_run.scan("# frozen_string_literal: true").count
      expect(frozen_count_2).to eq(1), "Second run should maintain 1 frozen_string_literal, got #{frozen_count_2}\nResult:\n#{second_run}"

      # Should be idempotent
      expect(second_run).to eq(first_run), "Second run should not add more duplicates"
    end
  end
end
