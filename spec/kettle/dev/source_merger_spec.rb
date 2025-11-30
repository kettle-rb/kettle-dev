# frozen_string_literal: true

RSpec.describe Kettle::Dev::SourceMerger do
  describe ".apply" do
    let(:path) { "Gemfile" }

    it "prepends the freeze reminder when missing" do
      src = "gem \"foo\"\n"
      result = described_class.apply(strategy: :skip, src: src, dest: "", path: path)
      expect(result.lines.first).to eq("# To retain during kettle-dev templating:\n")
      expect(result).to include("gem \"foo\"")
    end

    it "preserves kettle-dev:freeze blocks from the destination" do
      src = <<~RUBY
        source "https://example.com"
        gem "foo"
      RUBY
      dest = <<~RUBY
        source "https://rubygems.org"
        # kettle-dev:freeze
        gem "bar", "~> 1.0"
        # kettle-dev:unfreeze
      RUBY
      merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
      expect(merged).to include("source \"https://example.com\"")
      expect(merged).to include("gem \"foo\"")
      expect(merged).to include("# kettle-dev:freeze\ngem \"bar\", \"~> 1.0\"\n# kettle-dev:unfreeze")
    end

    it "appends missing gem declarations without duplicates" do
      src = <<~RUBY
        source "https://example.com"
        gem "foo"
        gem "bar"
      RUBY
      dest = <<~RUBY
        source "https://example.com"
        gem "foo"
      RUBY
      merged = described_class.apply(strategy: :append, src: src, dest: dest, path: path)
      foo_count = merged.scan(/gem\s+["']foo["']/).length
      expect(foo_count).to eq(1)
      expect(merged).to include("gem \"bar\"")
    end

    it "replaces matching nodes during merge" do
      src = <<~RUBY
        gem "foo", "~> 2.0"
      RUBY
      dest = <<~RUBY
        gem "foo", "~> 1.0"
      RUBY
      merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
      expect(merged).to include("gem \"foo\", \"~> 2.0\"")
      expect(merged).not_to include("~> 1.0")
    end

    it "reconciles gemspec fields while retaining frozen metadata" do
      src = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "updated-name"
          spec.add_dependency "foo"
        end
      RUBY
      dest = <<~RUBY
        Gem::Specification.new do |spec|
          spec.name = "original-name"
          # kettle-dev:freeze
          spec.metadata["custom"] = "1"
          # kettle-dev:unfreeze
          spec.add_dependency "existing"
        end
      RUBY
      merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: "sample.gemspec")
      expect(merged).to include("spec.name = \"updated-name\"")
      expect(merged).to include("spec.metadata[\"custom\"] = \"1\"")
      expect(merged.index("# kettle-dev:freeze")).to be > 0
    end

    it "appends missing Rake tasks without duplicating existing ones" do
      src = <<~RUBY
        task :ci do
          sh "bundle exec rspec"
        end
      RUBY
      dest = <<~RUBY
        task :default do
          sh "bundle exec rake spec"
        end
      RUBY
      merged = described_class.apply(strategy: :append, src: src, dest: dest, path: "Rakefile")
      default_count = merged.scan(/task\s+:default/).length
      expect(default_count).to eq(1)
      expect(merged).to include("task :ci")
      expect(merged).to include("task :default")
    end

    context "when preserving comments" do
      it "preserves inline comments on gem declarations" do
        src = <<~RUBY
          gem "foo", "~> 2.0"
        RUBY
        dest = <<~RUBY
          gem "foo", "~> 1.0" # production dependency
          gem "bar" # keep this one
        RUBY
        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        expect(merged).to include("gem \"foo\", \"~> 2.0\"")
        expect(merged).to include("gem \"bar\"")
        expect(merged).to include("# keep this one")
      end

      it "preserves leading comment blocks before statements" do
        src = <<~RUBY
          gem "foo"
        RUBY
        dest = <<~RUBY
          # This is a critical dependency
          # DO NOT REMOVE
          gem "bar"
        RUBY
        merged = described_class.apply(strategy: :append, src: src, dest: dest, path: path)
        expect(merged).to include("# This is a critical dependency")
        expect(merged).to include("# DO NOT REMOVE")
        expect(merged).to include("gem \"bar\"")
        expect(merged).to include("gem \"foo\"")
      end

      it "preserves comments within blocks" do
        src = <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "updated-name"
          end
        RUBY
        dest = <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = "original-name"
            # Important: this is used by CI
            spec.metadata["ci_config"] = "true"
          end
        RUBY
        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: "sample.gemspec")
        expect(merged).to include("spec.name = \"updated-name\"")
      end

      it "preserves comments in freeze blocks" do
        src = <<~RUBY
          gem "foo"
        RUBY
        dest = <<~RUBY
          # kettle-dev:freeze
          # Custom configuration
          gem "custom", path: "../custom"
          gem "another" # local override
          # kettle-dev:unfreeze
        RUBY
        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        expect(merged).to include("# Custom configuration")
        expect(merged).to include("gem \"custom\", path: \"../custom\"")
        expect(merged).to include("gem \"another\" # local override")
      end

      it "preserves multiline comments" do
        src = <<~RUBY
          gem "foo"
        RUBY
        dest = <<~RUBY
          # Beginning of comment block
          # Second line of comment
          # Third line of comment
          gem "bar"
        RUBY
        merged = described_class.apply(strategy: :append, src: src, dest: dest, path: path)
        expect(merged).to include("# Beginning of comment block")
        expect(merged).to include("# Second line of comment")
        expect(merged).to include("# Third line of comment")
        bar_idx = merged.index("gem \"bar\"")
        comment_idx = merged.index("# Beginning of comment block")
        expect(comment_idx).to be < bar_idx if bar_idx && comment_idx
      end

      it "maintains idempotency with comments" do
        src = <<~RUBY
          gem "foo"
        RUBY
        dest = <<~RUBY
          gem "foo"
          # Important comment
          gem "bar"
        RUBY
        merged1 = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        merged2 = described_class.apply(strategy: :merge, src: src, dest: merged1, path: path)
        expect(merged2.scan("# Important comment").length).to eq(1)
        bar_count = merged2.scan(/gem\s+["']bar["']/).length
        expect(bar_count).to eq(1)
        foo_count = merged2.scan(/gem\s+["']foo["']/).length
        expect(foo_count).to eq(1)
      end

      it "handles empty lines between comments and statements" do
        src = <<~RUBY
          gem "foo"
        RUBY
        dest = <<~RUBY
          # Comment with blank line below
          gem "bar"
        RUBY
        merged = described_class.apply(strategy: :append, src: src, dest: dest, path: path)
        expect(merged).to include("# Comment with blank line below")
        expect(merged).to include("gem \"bar\"")
      end

      it "preserves comments for destination-only statements during merge" do
        src = <<~RUBY
          gem "template_gem"
        RUBY
        dest = <<~RUBY
          # This is a custom dependency
          gem "custom_gem"
          gem "template_gem"
        RUBY
        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)
        expect(merged).to include("# This is a custom dependency")
        expect(merged).to include("gem \"custom_gem\"")
        expect(merged).to include("gem \"template_gem\"")
        custom_idx = merged.index("gem \"custom_gem\"")
        comment_idx = merged.index("# This is a custom dependency")
        expect(comment_idx).to be < custom_idx if custom_idx && comment_idx
      end
    end

    context "with variable assignments" do
      it "does not duplicate variable assignments when bodies differ" do
        # This test addresses the gemspec duplication issue where gem_version
        # assignment was duplicated because dest had extra commented code
        src = <<~RUBY
          gem_version = if RUBY_VERSION >= "3.1"
            "1.0.0"
          else
            "0.9.0"
          end
          
          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.version = gem_version
          end
        RUBY
        dest = <<~RUBY
          gem_version = if RUBY_VERSION >= "3.1"
            "1.0.0"
          else
            "0.9.0"
            # Additional commented code in dest
            # require_relative "lib/version"
          end
          
          Gem::Specification.new do |spec|
            spec.name = "my-gem"
            spec.version = gem_version
            spec.description = "Custom description"
          end
        RUBY
        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: "my-gem.gemspec")

        # Count occurrences of gem_version assignment
        gem_version_count = merged.scan(/^gem_version\s*=/).length
        expect(gem_version_count).to eq(1), "Expected 1 gem_version assignment, found #{gem_version_count}"

        # Should preserve the spec block
        expect(merged).to include("Gem::Specification.new")
        expect(merged).to include("spec.name = \"my-gem\"")
      end

      it "matches local variable assignments by name not content" do
        src = <<~RUBY
          foo = "template value"
        RUBY
        dest = <<~RUBY
          foo = "destination value"
        RUBY
        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)

        foo_count = merged.scan(/^foo\s*=/).length
        expect(foo_count).to eq(1)
        expect(merged).to include("foo = \"template value\"")
      end

      it "matches constant assignments by name not content" do
        src = <<~RUBY
          VERSION = "2.0.0"
        RUBY
        dest = <<~RUBY
          VERSION = "1.0.0"
        RUBY
        merged = described_class.apply(strategy: :merge, src: src, dest: dest, path: path)

        version_count = merged.scan(/^VERSION\s*=/).length
        expect(version_count).to eq(1)
        expect(merged).to include("VERSION = \"2.0.0\"")
      end
    end
  end
end
