# frozen_string_literal: true

RSpec.describe "Gemspec templating duplication bug" do
  describe "replace_gemspec_fields followed by SourceMerger" do
    let(:template_with_placeholders) do
      <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "template-gem"
          spec.version = "1.0.0"
          spec.authors = ["Template Author"]
          spec.email = ["template@example.com"]
          spec.summary = "🍲 "
          spec.description = "🍲 "
          spec.homepage = "https://github.com/org/template-gem"
          spec.licenses = ["MIT"]
          spec.required_ruby_version = ">= 2.3.0"
          spec.require_paths = ["lib"]
          spec.bindir = "exe"
          spec.executables = []
          spec.add_dependency("some-dep", "~> 1.0")
          spec.add_development_dependency("template-gem", "~> 1.0")
        end
      RUBY
    end

    let(:destination_existing) do
      <<~RUBY
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "my-gem"
          spec.version = "2.0.0"
          spec.authors = ["My Name"]
          spec.email = ["me@example.com"]
          spec.summary = "My awesome gem"
          spec.description = "This gem does amazing things"
          spec.homepage = "https://github.com/me/my-gem"
          spec.licenses = ["Apache-2.0"]
          spec.required_ruby_version = ">= 2.5.0"
          spec.require_paths = ["lib"]
          spec.bindir = "exe"
          spec.executables = ["my-command"]
          spec.add_dependency("some-dep", "~> 1.0")
        end
      RUBY
    end

    it "does not duplicate the Gem::Specification block" do
      # Step 1: Replace template placeholders with dest values (simulate replace_gemspec_fields)
      replacements = {
        name: "my-gem",
        version: "2.0.0",
        authors: ["My Name"],
        email: ["me@example.com"],
        summary: "My awesome gem",
        description: "This gem does amazing things",
        licenses: ["Apache-2.0"],
        required_ruby_version: ">= 2.5.0",
        executables: ["my-command"],
        _remove_self_dependency: "my-gem",
      }

      after_field_replacement = Kettle::Dev::PrismGemspec.replace_gemspec_fields(
        template_with_placeholders,
        replacements,
      )

      # Verify the output is valid Ruby
      result = Prism.parse(after_field_replacement)
      expect(result.success?).to be(true),
        "After replace_gemspec_fields, Ruby should be valid.\nErrors: #{result.errors.map(&:message).join(", ")}\n\nContent:\n#{after_field_replacement}"

      # Count Gem::Specification blocks
      statements = Kettle::Dev::PrismUtils.extract_statements(result.value.statements)
      gemspec_blocks = statements.count do |stmt|
        stmt.is_a?(Prism::CallNode) &&
          stmt.block &&
          Kettle::Dev::PrismUtils.extract_const_name(stmt.receiver) == "Gem::Specification" &&
          stmt.name == :new
      end

      expect(gemspec_blocks).to eq(1),
        "After replace_gemspec_fields, should have exactly 1 Gem::Specification block.\nContent:\n#{after_field_replacement}"

      # Step 2: Apply AST merge strategy
      merged = Kettle::Dev::SourceMerger.apply(
        strategy: :merge,
        src: after_field_replacement,
        dest: destination_existing,
        path: "test.gemspec",
      )

      # Verify merged output is valid Ruby
      merged_result = Prism.parse(merged)
      expect(merged_result.success?).to be(true),
        "After SourceMerger.apply, Ruby should be valid.\nErrors: #{merged_result.errors.map(&:message).join(", ")}\n\nContent:\n#{merged}"

      # Count Gem::Specification blocks in merged output
      merged_statements = Kettle::Dev::PrismUtils.extract_statements(merged_result.value.statements)
      merged_gemspec_blocks = merged_statements.count do |stmt|
        stmt.is_a?(Prism::CallNode) &&
          stmt.block &&
          Kettle::Dev::PrismUtils.extract_const_name(stmt.receiver) == "Gem::Specification" &&
          stmt.name == :new
      end

      expect(merged_gemspec_blocks).to eq(1),
        "After merge, should have exactly 1 Gem::Specification block, got #{merged_gemspec_blocks}.\nContent:\n#{merged}"

      # Verify no orphaned spec.* statements outside the block
      expect(merged).not_to match(/^spec\./),
        "Should not have orphaned spec.* statements at top level"
    end

    it "handles the exact kettle-dev gemspec scenario with emojis" do
      # This reproduces the exact bug from the user report where emojis in summary/description
      # combined with byte vs character offset confusion caused massive duplication
      template = <<~RUBY
        # coding: utf-8
        # frozen_string_literal: true

        Gem::Specification.new do |spec|
          spec.name = "kettle-dev"
          spec.version = "1.0.0"
          spec.authors = ["Template Author"]
          spec.email = ["template@example.com"]
          spec.summary = "🍲 "
          spec.description = "🍲 "
          spec.homepage = "https://github.com/kettle-rb/kettle-dev"
          spec.licenses = ["MIT"]
          spec.required_ruby_version = ">= 2.3.0"
          spec.require_paths = ["lib"]
          spec.bindir = "exe"
          spec.executables = []
          spec.add_development_dependency("rake", "~> 13.0")
          spec.add_development_dependency("gitmoji-regex", "~> 1.0")
        end
      RUBY

      replacements = {
        summary: "🍲 A kettle-rb meta tool",
        description: "🍲 Kettle::Dev is a meta tool from kettle-rb to streamline development",
        executables: ["kettle-changelog", "kettle-commit-msg", "kettle-dev-setup"],
      }

      result = Kettle::Dev::PrismGemspec.replace_gemspec_fields(template, replacements)

      # Parse and verify structure
      parse_result = Prism.parse(result)
      expect(parse_result.success?).to be(true),
        "Should produce valid Ruby.\nErrors: #{parse_result.errors.map(&:message).join(", ")}\n\nContent:\n#{result}"

      # Count spec.name occurrences - should be exactly 1
      name_count = result.scan(/^\s*spec\.name\s*=/).size
      expect(name_count).to eq(1),
        "Should have exactly 1 spec.name assignment, got #{name_count}.\n\nContent:\n#{result}"

      # Verify emojis are present and summary was updated
      expect(result).to include("🍲 A kettle-rb meta tool")
      expect(result).to include("kettle-changelog")

      # Verify no mangled lines like "# Hence.executables = ..."
      expect(result).not_to match(/# Hence\./),
        "Should not have mangled comment+assignment concatenations"

      # Count Gem::Specification blocks
      statements = Kettle::Dev::PrismUtils.extract_statements(parse_result.value.statements)
      gemspec_blocks = statements.count do |stmt|
        stmt.is_a?(Prism::CallNode) &&
          stmt.block &&
          Kettle::Dev::PrismUtils.extract_const_name(stmt.receiver) == "Gem::Specification" &&
          stmt.name == :new
      end

      expect(gemspec_blocks).to eq(1),
        "Should have exactly 1 Gem::Specification block, got #{gemspec_blocks}"
    end
  end
end
