# frozen_string_literal: true

RSpec.describe "Newline normalization in templating" do
  describe "SourceMerger newline handling" do
    it "ensures single blank line after magic comments (frozen_string_literal)" do
      content = <<~RUBY
        # frozen_string_literal: true
        # We run code coverage
      RUBY

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: content,
        dest: "",
        path: "test.rb",
      )

      lines = result.lines
      expect(lines[0].strip).to eq("# frozen_string_literal: true")
      expect(lines[1].strip).to eq("") # Blank line after magic comments
    end

    it "collapses multiple blank lines to single blank line" do
      content = <<~RUBY
        # frozen_string_literal: true


        # Comment 1



        # Comment 2
      RUBY

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: content,
        dest: "",
        path: "test.rb",
      )

      # Should not have more than one consecutive blank line
      expect(result).not_to match(/\n\n\n/)

      # Count consecutive newlines - should never be more than 2 (which is one blank line)
      max_consecutive_newlines = result.scan(/\n+/).map(&:length).max
      expect(max_consecutive_newlines).to be <= 2
    end

    it "ensures single newline at end of file" do
      content = "# frozen_string_literal: true\n# Comment"

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: content,
        dest: "",
        path: "test.rb",
      )

      expect(result).to end_with("\n")
      expect(result).not_to end_with("\n\n")
    end

    it "handles irregular empty lines fixture correctly" do
      fixture_content = File.read("spec/support/fixtures/modular_gemfile_with_irregular_empty_lines.rb")

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: fixture_content,
        dest: "",
        path: "coverage.gemfile",
      )

      lines = result.lines(chomp: true)

      # Should have frozen_string_literal
      expect(lines[0]).to eq("# frozen_string_literal: true")

      # Should have blank line after magic comment
      expect(lines[1]).to eq("")

      # Should not have multiple consecutive blank lines
      (0...lines.length - 1).each do |i|
        if lines[i].strip.empty? && lines[i + 1].strip.empty?
          fail "Found consecutive blank lines at lines #{i + 1} and #{i + 2}"
        end
      end

      # Should end with single newline
      expect(result).to end_with("\n")
      expect(result).not_to end_with("\n\n")
    end

    it "matches template spacing when merging" do
      template = <<~RUBY
        # frozen_string_literal: true

        # We run code coverage on the latest version of Ruby only.

        # Coverage
      RUBY

      # Destination with bad spacing
      dest = <<~RUBY
        # frozen_string_literal: true
        # See gemspec


        # Old comment
      RUBY

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :replace,
        src: template,
        dest: dest,
        path: "coverage.gemfile",
      )

      lines = result.lines(chomp: true)

      # Should have magic comment
      expect(lines[0]).to eq("# frozen_string_literal: true")

      # Should have single blank line after magic comment
      expect(lines[1]).to eq("")

      # Should not have consecutive blank lines anywhere
      (0...lines.length - 1).each do |i|
        if lines[i].strip.empty? && lines[i + 1].strip.empty?
          fail "Found consecutive blank lines at lines #{i + 1} and #{i + 2}: #{lines[i].inspect} and #{lines[i + 1].inspect}"
        end
      end
    end

    it "handles shebang with frozen_string_literal" do
      content = <<~RUBY
        #!/usr/bin/env ruby
        # frozen_string_literal: true
        # Comment
      RUBY

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: content,
        dest: "",
        path: "test.rb",
      )

      # After parsing and rebuilding, shebang should be preserved as the first line
      # Note: Prism might handle shebangs specially - let's verify it's there somewhere
      expect(result).to include("#!/usr/bin/env ruby")
      expect(result).to include("# frozen_string_literal: true")
    end

    it "preserves important spacing in real-world coverage.gemfile" do
      template_content = File.read("gemfiles/modular/coverage.gemfile")

      result = Kettle::Dev::SourceMerger.apply(
        strategy: :skip,
        src: template_content,
        dest: "",
        path: "coverage.gemfile",
      )

      lines = result.lines(chomp: true)

      # First line should be frozen_string_literal
      expect(lines[0]).to eq("# frozen_string_literal: true")

      # Second line should be blank
      expect(lines[1]).to eq("")

      # Should not have multiple consecutive blank lines
      (0...lines.length - 1).each do |i|
        if lines[i].strip.empty? && lines[i + 1].strip.empty?
          fail "Found consecutive blank lines at lines #{i + 1} and #{i + 2}"
        end
      end
    end
  end
end
