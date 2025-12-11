# frozen_string_literal: true

RSpec.describe "style.gemfile conditional block duplication fix", :prism_merge_only do
  describe "merging style.gemfile with if/else blocks" do
    let(:source_template) do
      <<~'GEMFILE'
        # frozen_string_literal: true

        # We run rubocop on the latest version of Ruby,
        #   but in support of the oldest supported version of Ruby

        gem "reek", "~> 6.5"
        # gem "rubocop", "~> 1.73", ">= 1.73.2" # constrained by standard
        gem "rubocop-packaging", "~> 0.6", ">= 0.6.0"
        gem "standard", ">= 1.50"
        gem "rubocop-on-rbs", "~> 1.8"                    # ruby >= 3.1.0

        # Std Lib extractions
        gem "benchmark", "~> 0.4", ">= 0.4.1" # Removed from Std Lib in Ruby 3.5

        if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
          home = ENV["HOME"] || Dir.home
          gem "rubocop-lts", path: "#{home}/src/rubocop-lts/rubocop-lts"
          gem "rubocop-lts-rspec", path: "#{home}/src/rubocop-lts/rubocop-lts-rspec"
          gem "rubocop-ruby2_3", path: "#{home}/src/rubocop-lts/rubocop-ruby2_3"
          gem "standard-rubocop-lts", path: "#{home}/src/rubocop-lts/standard-rubocop-lts"
        else
          gem "rubocop-lts", "~> 10.0"
          gem "rubocop-ruby2_3"
          gem "rubocop-rspec", "~> 3.6"
        end
      GEMFILE
    end

    let(:destination_existing) do
      <<~'GEMFILE'
        # frozen_string_literal: true

        # We run rubocop on the latest version of Ruby,
        #   but in support of the oldest supported version of Ruby

        gem "reek", "~> 6.5"
        # gem "rubocop", "~> 1.80", ">= 1.80.2" # constrained by standard
        gem "rubocop-packaging", "~> 0.6", ">= 0.6.0"
        gem "standard", ">= 1.50"
        gem "rubocop-on-rbs", "~> 1.8"                    # ruby >= 3.1.0

        # Std Lib extractions
        gem "benchmark", "~> 0.4", ">= 0.4.1" # Removed from Std Lib in Ruby 3.5

        if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
          home = ENV["HOME"]
          gem "rubocop-lts", path: "#{home}/src/rubocop-lts/rubocop-lts"
          gem "rubocop-lts-rspec", path: "#{home}/src/rubocop-lts/rubocop-lts-rspec"
          gem "rubocop-ruby2_3", path: "#{home}/src/rubocop-lts/rubocop-ruby2_3"
          gem "standard-rubocop-lts", path: "#{home}/src/rubocop-lts/standard-rubocop-lts"
        else
          gem "rubocop-lts", "~> 10.0"
          gem "rubocop-ruby2_3", "~> 2.0"
          gem "rubocop-rspec", "~> 3.6"
        end
      GEMFILE
    end

    it "does not duplicate the if/else block when merging" do
      result = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: source_template,
        dest: destination_existing,
        path: "gemfiles/modular/style.gemfile",
      )

      # Count occurrences of the if statement
      if_count = result.scan('if ENV.fetch("RUBOCOP_LTS_LOCAL"').size

      expect(if_count).to eq(1),
        "Expected exactly 1 if block, got #{if_count}.\n\nResult:\n#{result}"

      # Verify the source version is used (with || Dir.home)
      expect(result).to include('ENV["HOME"] || Dir.home'),
        "Expected source version with '|| Dir.home' to be present"

      # Verify the old destination-specific content is replaced
      expect(result).not_to include('gem "rubocop-ruby2_3", "~> 2.0"'),
        "Old destination content should be replaced"

      # Verify template version without version constraint is used
      expect(result).to include('gem "rubocop-ruby2_3"'),
        "Template version of rubocop-ruby2_3 should be present"
    end

    it "maintains idempotency when merging multiple times" do
      first_merge = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: source_template,
        dest: destination_existing,
        path: "gemfiles/modular/style.gemfile",
      )

      second_merge = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: source_template,
        dest: first_merge,
        path: "gemfiles/modular/style.gemfile",
      )

      third_merge = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: source_template,
        dest: second_merge,
        path: "gemfiles/modular/style.gemfile",
      )

      # All merges should produce the same result
      expect(second_merge).to eq(first_merge),
        "Second merge should be identical to first"
      expect(third_merge).to eq(first_merge),
        "Third merge should be identical to first"

      # Verify no duplication
      if_count = third_merge.scan('if ENV.fetch("RUBOCOP_LTS_LOCAL"').size
      expect(if_count).to eq(1),
        "Expected exactly 1 if block after multiple merges, got #{if_count}"
    end

    it "reproduces the exact user-reported bug scenario" do
      # This is what the user reported:
      # The file ended up with DUPLICATE if/else blocks after running
      # bin/kettle-dev-setup --allowed=true --force

      buggy_result = <<~'GEMFILE'
        # frozen_string_literal: true

        # To retain during kettle-dev templating:
        #     kettle-dev:freeze
        #     # ... your code
        #     kettle-dev:unfreeze
        #
        # We run rubocop on the latest version of Ruby,
        #   but in support of the oldest supported version of Ruby

        gem "reek", "~> 6.5"
        # gem "rubocop", "~> 1.73", ">= 1.73.2" # constrained by standard
        gem "rubocop-packaging", "~> 0.6", ">= 0.6.0"
        gem "standard", ">= 1.50"
        gem "rubocop-on-rbs", "~> 1.8" # ruby >= 3.1.0

        # Std Lib extractions
        gem "benchmark", "~> 0.4", ">= 0.4.1" # Removed from Std Lib in Ruby 3.5

        if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
          home = ENV["HOME"]
          gem "rubocop-lts", path: "#{home}/src/rubocop-lts/rubocop-lts"
          gem "rubocop-lts-rspec", path: "#{home}/src/rubocop-lts/rubocop-lts-rspec"
          gem "rubocop-ruby2_3", path: "#{home}/src/rubocop-lts/rubocop-ruby2_3"
          gem "standard-rubocop-lts", path: "#{home}/src/rubocop-lts/standard-rubocop-lts"
        else
          gem "rubocop-lts", "~> 10.0"
          gem "rubocop-ruby2_3", "~> 2.0"
          gem "rubocop-rspec", "~> 3.6"
        end

        if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
          home = ENV["HOME"] || Dir.home
          gem "rubocop-lts", path: "#{home}/src/rubocop-lts/rubocop-lts"
          gem "rubocop-lts-rspec", path: "#{home}/src/rubocop-lts/rubocop-lts-rspec"
          gem "rubocop-ruby2_3", path: "#{home}/src/rubocop-lts/rubocop-ruby2_3"
          gem "standard-rubocop-lts", path: "#{home}/src/rubocop-lts/standard-rubocop-lts"
        else
          gem "rubocop-lts", "~> 10.0"
          gem "rubocop-ruby2_3"
          gem "rubocop-rspec", "~> 3.6"
        end
      GEMFILE

      # Our fix should prevent this duplication
      result = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: source_template,
        dest: destination_existing,
        path: "gemfiles/modular/style.gemfile",
      )

      # The buggy result has 2 if blocks - our fix should only produce 1
      buggy_if_count = buggy_result.scan('if ENV.fetch("RUBOCOP_LTS_LOCAL"').size
      fixed_if_count = result.scan('if ENV.fetch("RUBOCOP_LTS_LOCAL"').size

      expect(buggy_if_count).to eq(2), "Sanity check: buggy result should have 2 if blocks"
      expect(fixed_if_count).to eq(1), "Fixed result should have only 1 if block"
      expect(result).not_to eq(buggy_result), "Fixed result should differ from buggy output"
    end
  end
end
