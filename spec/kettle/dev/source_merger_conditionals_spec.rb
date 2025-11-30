# frozen_string_literal: true

RSpec.describe Kettle::Dev::SourceMerger do
  describe ".apply with conditional statements" do
    let(:path) { "test.gemfile" }

    context "when merging if/else blocks" do
      it "replaces if/else block with same predicate during merge" do
        src = <<~RUBY
          gem "foo"
          if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
            home = ENV["HOME"] || Dir.home
            gem "rubocop-lts", path: "\#{home}/src/rubocop-lts/rubocop-lts"
            gem "rubocop-ruby2_3", path: "\#{home}/src/rubocop-lts/rubocop-ruby2_3"
          else
            gem "rubocop-lts", "~> 10.0"
            gem "rubocop-ruby2_3"
          end
        RUBY

        dest = <<~RUBY
          gem "foo"
          if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
            home = ENV["HOME"]
            gem "rubocop-lts", path: "\#{home}/src/rubocop-lts/rubocop-lts"
            gem "rubocop-ruby2_3", path: "\#{home}/src/rubocop-lts/rubocop-ruby2_3"
          else
            gem "rubocop-lts", "~> 10.0"
            gem "rubocop-ruby2_3", "~> 2.0"
          end
        RUBY

        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)

        # Count occurrences of the if statement
        if_count = merged.scan('if ENV.fetch("RUBOCOP_LTS_LOCAL"').size
        expect(if_count).to eq(1), "Expected 1 if block, got #{if_count}. Content:\n#{merged}"

        # Should have the source version (with || Dir.home)
        expect(merged).to include('ENV["HOME"] || Dir.home')
        expect(merged).not_to include('gem "rubocop-ruby2_3", "~> 2.0"')
      end

      it "does not duplicate if blocks with same condition in append mode" do
        src = <<~RUBY
          if ENV["DEBUG"] == "true"
            gem "debug-gem", "~> 1.0"
          end
        RUBY

        dest = <<~RUBY
          if ENV["DEBUG"] == "true"
            gem "debug-gem", "~> 0.5"
          end
        RUBY

        merged = described_class.apply(strategy: :append, src: src, dest: dest, path: path)
        if_count = merged.scan('if ENV["DEBUG"]').size
        expect(if_count).to eq(1)
      end

      it "keeps both if blocks when predicates are different" do
        src = <<~RUBY
          if ENV["FOO"] == "true"
            gem "foo"
          end
        RUBY

        dest = <<~RUBY
          if ENV["BAR"] == "true"
            gem "bar"
          end
        RUBY

        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        expect(merged).to include('if ENV["FOO"]')
        expect(merged).to include('if ENV["BAR"]')
        expect(merged).to include('gem "foo"')
        expect(merged).to include('gem "bar"')
      end

      it "handles nested if blocks correctly" do
        src = <<~RUBY
          if ENV["OUTER"] == "true"
            if ENV["INNER"] == "true"
              gem "nested"
            end
          end
        RUBY

        dest = <<~RUBY
          if ENV["OUTER"] == "true"
            gem "outer-only"
          end
        RUBY

        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        outer_count = merged.scan('if ENV["OUTER"]').size
        expect(outer_count).to eq(1)
        expect(merged).to include("gem \"nested\"")
      end
    end

    context "when merging unless blocks" do
      it "replaces unless block with same predicate" do
        src = <<~RUBY
          unless ENV["SKIP"] == "true"
            gem "included", "~> 2.0"
          end
        RUBY

        dest = <<~RUBY
          unless ENV["SKIP"] == "true"
            gem "included", "~> 1.0"
          end
        RUBY

        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        unless_count = merged.scan('unless ENV["SKIP"]').size
        expect(unless_count).to eq(1)
        expect(merged).to include('"~> 2.0"')
        expect(merged).not_to include('"~> 1.0"')
      end
    end

    context "when merging case statements" do
      it "replaces case statement with same predicate" do
        src = <<~RUBY
          case ENV["MODE"]
          when "dev"
            gem "dev-gem"
          when "prod"
            gem "prod-gem"
          end
        RUBY

        dest = <<~RUBY
          case ENV["MODE"]
          when "dev"
            gem "old-dev-gem"
          end
        RUBY

        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        case_count = merged.scan('case ENV["MODE"]').size
        expect(case_count).to eq(1)
        expect(merged).to include('gem "dev-gem"')
        expect(merged).to include('gem "prod-gem"')
        expect(merged).not_to include('gem "old-dev-gem"')
      end

      it "keeps both case statements when predicates differ" do
        src = <<~RUBY
          case ENV["FOO"]
          when "a"
            gem "foo-a"
          end
        RUBY

        dest = <<~RUBY
          case ENV["BAR"]
          when "b"
            gem "bar-b"
          end
        RUBY

        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        expect(merged).to include('case ENV["FOO"]')
        expect(merged).to include('case ENV["BAR"]')
        expect(merged).to include('gem "foo-a"')
        expect(merged).to include('gem "bar-b"')
      end
    end

    context "with edge cases" do
      it "handles if statements with complex predicates" do
        src = <<~RUBY
          if ENV.fetch("A", "false") == "true" && ENV["B"] != "false"
            gem "complex"
          end
        RUBY

        dest = <<~RUBY
          if ENV.fetch("A", "false") == "true" && ENV["B"] != "false"
            gem "old-complex"
          end
        RUBY

        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        if_count = merged.scan('if ENV.fetch("A"').size
        expect(if_count).to eq(1)
        expect(merged).to include('gem "complex"')
        expect(merged).not_to include('gem "old-complex"')
      end

      it "maintains idempotency with conditional blocks" do
        src = <<~RUBY
          if ENV["TEST"] == "true"
            gem "test-gem"
          end
        RUBY

        dest = src

        merged1 = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        merged2 = described_class.apply(strategy: :merge, src: src, dest: merged1, path: path)

        expect(merged1).to eq(merged2)
        if_count = merged2.scan('if ENV["TEST"]').size
        expect(if_count).to eq(1)
      end
    end
  end
end
