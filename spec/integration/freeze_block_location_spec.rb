# frozen_string_literal: true

RSpec.describe "Freeze Block Location Preservation" do
  describe "Kettle::Dev::SourceMerger" do
    context "when file has existing freeze blocks" do
      it "preserves freeze block location inside Gem::Specification block" do
        input = <<~RUBY
          # frozen_string_literal: true

          gem_version = "1.0.0"

          Gem::Specification.new do |spec|
            spec.name = "test-gem"
            spec.bindir = "exe"
            
            # kettle-dev:freeze
            # Custom dependencies
            # spec.add_dependency("custom-gem")
            # kettle-dev:unfreeze
            
            spec.require_paths = ["lib"]
          end
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.gemspec"
        )

        lines = result.lines

        # Verify freeze block stays inside Gem::Specification block
        gem_spec_line = lines.find_index { |l| l.include?("Gem::Specification.new") }
        freeze_line = lines.find_index { |l| l.include?("# kettle-dev:freeze") }
        end_line = lines.find_index { |l| l.strip == "end" }

        expect(gem_spec_line).not_to be_nil
        expect(freeze_line).not_to be_nil
        expect(freeze_line).to be > gem_spec_line
        expect(freeze_line).to be < end_line

        # Verify no freeze reminder was added
        expect(result).not_to include("To retain during kettle-dev templating")
      end

      it "does not capture unrelated comments before freeze block" do
        input = <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "test"
            spec.executables = []
            # Listed files are relative paths
            spec.files = []

            # kettle-dev:freeze
            # Custom content
            # kettle-dev:unfreeze
          end
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.gemspec"
        )

        lines = result.lines

        # "Listed files" comment should appear before freeze block
        listed_line = lines.find_index { |l| l.include?("Listed files are relative paths") }
        freeze_line = lines.find_index { |l| l.include?("# kettle-dev:freeze") }

        expect(listed_line).not_to be_nil
        expect(freeze_line).not_to be_nil
        expect(listed_line).to be < freeze_line

        # Should not be captured as part of freeze block range
        # (verify by checking they're separated by other content)
        expect(freeze_line - listed_line).to be > 2
      end

      it "preserves multiple freeze blocks at different locations" do
        input = <<~RUBY
          # frozen_string_literal: true
          
          # kettle-dev:freeze
          # Top-level frozen content
          # kettle-dev:unfreeze

          Gem::Specification.new do |spec|
            spec.name = "test"
            
            # kettle-dev:freeze
            # Block-level frozen content
            # kettle-dev:unfreeze
            
            spec.require_paths = ["lib"]
          end
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.gemspec"
        )

        lines = result.lines

        # Find both freeze blocks
        freeze_indices = lines.each_index.select { |i| lines[i].include?("# kettle-dev:freeze") }

        expect(freeze_indices.length).to eq(2)

        # First freeze block should be near top
        expect(freeze_indices[0]).to be < 10

        # Second freeze block should be after Gem::Specification
        gem_spec_line = lines.find_index { |l| l.include?("Gem::Specification.new") }
        expect(freeze_indices[1]).to be > gem_spec_line

        # No freeze reminder added
        expect(result).not_to include("To retain during kettle-dev templating")
      end

      it "preserves contiguous header comments with freeze block" do
        input = <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            # Important context comment
            # More context about dependencies
            # kettle-dev:freeze
            # Frozen dependencies
            # kettle-dev:unfreeze
          end
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.gemspec"
        )

        lines = result.lines

        # Header comments should be preserved with freeze block
        important_line = lines.find_index { |l| l.include?("Important context comment") }
        more_context_line = lines.find_index { |l| l.include?("More context about dependencies") }
        freeze_line = lines.find_index { |l| l.include?("# kettle-dev:freeze") }

        expect(important_line).not_to be_nil
        expect(more_context_line).not_to be_nil
        expect(freeze_line).not_to be_nil

        # Should be contiguous (within 1 line of each other)
        expect(more_context_line - important_line).to eq(1)
        expect(freeze_line - more_context_line).to eq(1)
      end

      it "does not capture comments separated by blank lines" do
        input = <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            # Unrelated comment
            
            # kettle-dev:freeze
            # Frozen content
            # kettle-dev:unfreeze
          end
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.gemspec"
        )

        lines = result.lines

        # Unrelated comment should appear before blank line, not part of freeze block
        unrelated_line = lines.find_index { |l| l.include?("Unrelated comment") }
        freeze_line = lines.find_index { |l| l.include?("# kettle-dev:freeze") }

        expect(unrelated_line).not_to be_nil
        expect(freeze_line).not_to be_nil

        # Should be separated by blank line
        expect(freeze_line - unrelated_line).to be > 1
        expect(lines[unrelated_line + 1].strip).to be_empty
      end

      it "does not capture comments separated by code" do
        input = <<~RUBY
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            # Comment about name
            spec.name = "test"
            # kettle-dev:freeze
            # Frozen content
            # kettle-dev:unfreeze
          end
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.gemspec"
        )

        lines = result.lines

        # Comment about name should not be part of freeze block
        name_comment_line = lines.find_index { |l| l.include?("Comment about name") }
        spec_name_line = lines.find_index { |l| l.include?('spec.name = "test"') }
        freeze_line = lines.find_index { |l| l.include?("# kettle-dev:freeze") }

        expect(name_comment_line).not_to be_nil
        expect(spec_name_line).not_to be_nil
        expect(freeze_line).not_to be_nil

        # Code should separate the comments
        expect(spec_name_line).to be > name_comment_line
        expect(freeze_line).to be > spec_name_line
      end

      it "preserves file structure when file has complex nesting" do
        input = <<~RUBY
          # coding: utf-8
          # frozen_string_literal: true

          gem_version =
            if RUBY_VERSION >= "3.1"
              require "kettle/dev/version"
              Kettle::Dev::Version::VERSION
            else
              "1.0.0"
            end

          Gem::Specification.new do |spec|
            spec.name = "test-gem"
            spec.version = gem_version
            
            spec.bindir = "exe"
            # Configuration comment
            spec.executables = []
            
            # kettle-dev:freeze
            # Frozen dependencies
            # spec.add_dependency("frozen-gem")
            # kettle-dev:unfreeze
            
            spec.require_paths = ["lib"]
          end
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "test.gemspec"
        )

        lines = result.lines

        # Verify magic comments at top
        expect(lines[0]).to include("# coding:")
        expect(lines[1]).to include("# frozen_string_literal:")

        # Verify gem_version before Gem::Specification
        gem_version_line = lines.find_index { |l| l.include?("gem_version =") }
        gem_spec_line = lines.find_index { |l| l.include?("Gem::Specification.new") }
        expect(gem_version_line).to be < gem_spec_line

        # Verify configuration comment before freeze block
        config_line = lines.find_index { |l| l.include?("Configuration comment") }
        freeze_line = lines.find_index { |l| l.include?("# kettle-dev:freeze") }
        expect(config_line).to be < freeze_line

        # Verify freeze block inside Gem::Specification
        expect(freeze_line).to be > gem_spec_line

        # No freeze reminder
        expect(result).not_to include("To retain during kettle-dev templating")
      end
    end

    context "when file has only freeze reminder (no actual freeze blocks)" do
      it "keeps the freeze reminder in place" do
        input = <<~RUBY
          # frozen_string_literal: true

          # To retain during kettle-dev templating:
          #     kettle-dev:freeze
          #     # ... your code
          #     kettle-dev:unfreeze
          #

          gem "foo"
        RUBY

        result = Kettle::Dev::SourceMerger.apply(
          strategy: :skip,
          src: input,
          dest: "",
          path: "Gemfile"
        )

        # Should not duplicate the reminder
        reminder_count = result.lines.count { |l| l.include?("To retain during kettle-dev templating") }
        expect(reminder_count).to eq(1)
      end
    end
  end
end

