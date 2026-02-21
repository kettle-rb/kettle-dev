# frozen_string_literal: true

require "spec_helper"
require "kettle/dev/prism_utils"

RSpec.describe Kettle::Dev::PrismUtils do
  describe ".parse_with_comments" do
    it "parses Ruby source and returns parse result" do
      source = "gem 'foo'\n"
      result = described_class.parse_with_comments(source)
      expect(result).to be_a(Prism::ParseResult)
      expect(result.value).to be_a(Prism::ProgramNode)
    end

    it "captures comments in the parse result" do
      source = <<~RUBY
        # This is a comment
        gem 'foo'
      RUBY
      result = described_class.parse_with_comments(source)
      expect(result.comments.length).to eq(1)
      expect(result.comments.first.slice).to include("This is a comment")
    end
  end

  describe ".extract_statements" do
    it "extracts statements from a StatementsNode" do
      source = <<~RUBY
        gem 'foo'
        gem 'bar'
      RUBY
      result = described_class.parse_with_comments(source)
      body = result.value.statements
      statements = described_class.extract_statements(body)
      expect(statements.length).to eq(2)
      expect(statements).to all(be_a(Prism::CallNode))
    end

    it "returns empty array for nil body" do
      statements = described_class.extract_statements(nil)
      expect(statements).to eq([])
    end

    it "wraps single non-StatementsNode in array" do
      source = "gem 'foo'"
      result = described_class.parse_with_comments(source)
      # A single statement might be wrapped in a StatementsNode or be standalone
      body = result.value.statements.body.first if result.value.statements
      statements = described_class.extract_statements(body)
      expect(statements).to be_an(Array)
    end
  end

  describe ".statement_key" do
    it "generates key for gem call with string argument" do
      source = 'gem "foo"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      key = described_class.statement_key(node)
      expect(key).to eq([:gem, "foo"])
    end

    it "generates key for gem call with symbol argument" do
      source = "gem :foo"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      key = described_class.statement_key(node)
      expect(key).to eq([:gem, "foo"])
    end

    it "generates key for source call" do
      source = 'source "https://gem.coop"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      key = described_class.statement_key(node)
      expect(key).to eq([:source, "https://gem.coop"])
    end

    it "returns nil for non-call nodes" do
      source = "x = 1"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      key = described_class.statement_key(node)
      expect(key).to be_nil
    end

    it "returns nil for untracked method calls" do
      source = 'puts "hello"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      key = described_class.statement_key(node)
      expect(key).to be_nil
    end

    it "respects custom tracked_methods" do
      source = 'foo "bar"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      key = described_class.statement_key(node, tracked_methods: [:foo])
      expect(key).to eq([:foo, "bar"])
    end
  end

  describe ".extract_literal_value" do
    it "extracts value from StringNode" do
      source = '"hello"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      value = described_class.extract_literal_value(node)
      expect(value).to eq("hello")
    end

    it "extracts value from SymbolNode" do
      source = ":foo"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      value = described_class.extract_literal_value(node)
      expect(value).to eq("foo")
    end

    it "returns nil for non-literal nodes" do
      source = "1 + 2"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      value = described_class.extract_literal_value(node)
      expect(value).to be_nil
    end

    it "returns nil for nil node" do
      value = described_class.extract_literal_value(nil)
      expect(value).to be_nil
    end
  end

  describe ".extract_const_name" do
    it "extracts simple constant name" do
      source = "Foo"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      name = described_class.extract_const_name(node)
      expect(name).to eq("Foo")
    end

    it "extracts qualified constant name" do
      source = "Gem::Specification"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      name = described_class.extract_const_name(node)
      expect(name).to eq("Gem::Specification")
    end

    it "extracts deeply nested constant name" do
      source = "A::B::C"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      name = described_class.extract_const_name(node)
      expect(name).to eq("A::B::C")
    end

    it "returns nil for non-constant nodes" do
      source = '"string"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      name = described_class.extract_const_name(node)
      expect(name).to be_nil
    end
  end

  describe ".find_leading_comments" do
    it "finds comments before a statement" do
      source = <<~RUBY
        gem 'foo'
        # Leading comment
        gem 'bar'
      RUBY
      result = described_class.parse_with_comments(source)
      statements = result.value.statements.body
      body_node = result.value.statements

      leading = described_class.find_leading_comments(result, statements[1], statements[0], body_node)
      expect(leading.length).to eq(1)
      expect(leading.first.slice).to include("Leading comment")
    end

    it "finds multiple leading comments" do
      source = <<~RUBY
        gem 'foo'
        # Comment 1
        # Comment 2
        gem 'bar'
      RUBY
      result = described_class.parse_with_comments(source)
      statements = result.value.statements.body
      body_node = result.value.statements

      leading = described_class.find_leading_comments(result, statements[1], statements[0], body_node)
      expect(leading.length).to eq(2)
    end

    it "returns empty array when no leading comments" do
      source = <<~RUBY
        gem 'foo'
        gem 'bar'
      RUBY
      result = described_class.parse_with_comments(source)
      statements = result.value.statements.body
      body_node = result.value.statements

      leading = described_class.find_leading_comments(result, statements[1], statements[0], body_node)
      expect(leading).to be_empty
    end
  end

  describe ".inline_comments_for_node" do
    it "finds inline comment on same line" do
      source = 'gem "foo" # production dep'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      inline = described_class.inline_comments_for_node(result, node)
      expect(inline.length).to eq(1)
      expect(inline.first.slice).to include("production dep")
    end

    it "returns empty array when no inline comment" do
      source = 'gem "foo"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      inline = described_class.inline_comments_for_node(result, node)
      expect(inline).to be_empty
    end
  end

  describe ".node_to_source" do
    it "converts CallNode to source using Unparser" do
      source = 'gem "foo", "~> 1.0"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      output = described_class.node_to_source(node)
      # Unparser preserves original formatting for Prism nodes
      expect(output).to include("gem")
      expect(output).to include("foo")
      expect(output).to include("1.0")
    end

    it "returns empty string for nil node" do
      output = described_class.node_to_source(nil)
      expect(output).to eq("")
    end

    it "falls back to original source if unparsing fails" do
      source = 'gem "foo"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first

      # Even if Unparser has issues, we get something
      output = described_class.node_to_source(node)
      expect(output).not_to be_empty
    end
  end

  describe ".normalize_call_node" do
    it "normalizes gem call with string arguments" do
      source = 'gem "foo", "~> 1.0"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      normalized = described_class.normalize_call_node(node)
      expect(normalized).to eq('gem("foo", "~> 1.0")')
    end

    it "normalizes gem call with symbol argument" do
      source = "gem :foo"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      normalized = described_class.normalize_call_node(node)
      expect(normalized).to eq("gem(:foo)")
    end

    it "normalizes call with no arguments" do
      source = "foo()"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      normalized = described_class.normalize_call_node(node)
      expect(normalized).to eq("foo()")
    end

    it "handles hash arguments" do
      source = 'gem "foo", require: false'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      normalized = described_class.normalize_call_node(node)
      expect(normalized).to include("gem(")
      expect(normalized).to include("foo")
      expect(normalized).to include("require:")
    end
  end

  describe ".normalize_argument" do
    it "normalizes string argument" do
      source = '"hello"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      normalized = described_class.normalize_argument(node)
      expect(normalized).to eq('"hello"')
    end

    it "normalizes symbol argument" do
      source = ":foo"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      normalized = described_class.normalize_argument(node)
      expect(normalized).to eq(":foo")
    end

    it "normalizes integer argument" do
      source = "42"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      normalized = described_class.normalize_argument(node)
      expect(normalized).to eq("42")
    end
  end

  describe ".call_to?" do
    it "returns true for matching method call" do
      source = 'gem "foo"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      expect(described_class.call_to?(node, :gem)).to be true
    end

    it "returns false for non-matching method call" do
      source = 'gem "foo"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      expect(described_class.call_to?(node, :source)).to be false
    end

    it "returns false for non-call nodes" do
      source = "42"
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      expect(described_class.call_to?(node, :gem)).to be false
    end
  end

  describe ".block_call_to?" do
    it "returns true for block call to matching method" do
      source = <<~RUBY
        task :default do
          puts "hi"
        end
      RUBY
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      expect(described_class.block_call_to?(node, :task)).to be true
    end

    it "returns false for non-block call" do
      source = 'gem "foo"'
      result = described_class.parse_with_comments(source)
      node = result.value.statements.body.first
      expect(described_class.block_call_to?(node, :gem)).to be false
    end
  end
end
