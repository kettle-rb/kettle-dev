# frozen_string_literal: true

require "prism"

module Kettle
  module Dev
    # Shared utilities for working with Prism AST nodes.
    # Provides parsing, node inspection, and source generation helpers
    # used by both PrismMerger and AppraisalsAstMerger.
    #
    # Uses Prism's native methods for source generation (via .slice) to preserve
    # original formatting and comments. For normalized output (e.g., adding parentheses),
    # use normalize_call_node instead.
    module PrismUtils
      module_function

      # Parse Ruby source code and return Prism parse result with comments
      # @param source [String] Ruby source code
      # @return [Prism::ParseResult] Parse result containing AST and comments
      def parse_with_comments(source)
        Prism.parse(source)
      end

      # Extract statements from a Prism body node
      # @param body_node [Prism::Node, nil] Body node (typically StatementsNode)
      # @return [Array<Prism::Node>] Array of statement nodes
      def extract_statements(body_node)
        return [] unless body_node

        if body_node.is_a?(Prism::StatementsNode)
          body_node.body.compact
        else
          [body_node].compact
        end
      end

      # Generate a unique key for a statement node to identify equivalent statements
      # Used for merge/append operations to detect duplicates
      # @param node [Prism::Node] Statement node
      # @param tracked_methods [Array<Symbol>] Methods to track (default: gem, source, eval_gemfile, git_source)
      # @return [Array, nil] Key array like [:gem, "foo"] or nil if not trackable
      def statement_key(node, tracked_methods: %i[gem source eval_gemfile git_source])
        return unless node.is_a?(Prism::CallNode)
        return unless tracked_methods.include?(node.name)

        first_arg = node.arguments&.arguments&.first
        arg_value = extract_literal_value(first_arg)

        [node.name, arg_value] if arg_value
      end

      # Extract literal value from string or symbol nodes
      # @param node [Prism::Node, nil] Node to extract from
      # @return [String, Symbol, nil] Literal value or nil
      def extract_literal_value(node)
        return unless node
        case node
        when Prism::StringNode then node.unescaped
        when Prism::SymbolNode then node.unescaped
        else
          # Attempt to handle array literals
          if node.respond_to?(:elements) && node.elements
            arr = node.elements.map do |el|
              case el
              when Prism::StringNode then el.unescaped
              when Prism::SymbolNode then el.unescaped
              end
            end
            return arr if arr.all?
          end
          nil
        end
      end

      # Extract qualified constant name from a constant node
      # @param node [Prism::Node, nil] Constant node
      # @return [String, nil] Qualified name like "Gem::Specification" or nil
      def extract_const_name(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          parent = extract_const_name(node.parent)
          child = node.name || node.child&.name
          (parent && child) ? "#{parent}::#{child}" : child.to_s
        end
      end

      # Find leading comments for a statement node
      # Leading comments are those that appear after the previous statement
      # and before the current statement
      # @param parse_result [Prism::ParseResult] Parse result with comments
      # @param current_stmt [Prism::Node] Current statement node
      # @param prev_stmt [Prism::Node, nil] Previous statement node
      # @param body_node [Prism::Node] Body containing the statements
      # @return [Array<Prism::Comment>] Leading comments
      def find_leading_comments(parse_result, current_stmt, prev_stmt, body_node)
        start_line = prev_stmt ? prev_stmt.location.end_line : body_node.location.start_line
        end_line = current_stmt.location.start_line

        parse_result.comments.select do |comment|
          comment.location.start_line > start_line &&
            comment.location.start_line < end_line
        end
      end

      # Find inline comments for a statement node
      # Inline comments are those that appear on the same line as the statement's end
      # @param parse_result [Prism::ParseResult] Parse result with comments
      # @param stmt [Prism::Node] Statement node
      # @return [Array<Prism::Comment>] Inline comments
      def inline_comments_for_node(parse_result, stmt)
        parse_result.comments.select do |comment|
          comment.location.start_line == stmt.location.end_line &&
            comment.location.start_offset > stmt.location.end_offset
        end
      end

      # Convert a Prism AST node to Ruby source code
      # Uses Prism's native slice method which preserves the original source exactly.
      # This is preferable to Unparser for Prism nodes as it maintains original formatting
      # and comments without requiring transformation.
      # @param node [Prism::Node] AST node
      # @return [String] Ruby source code
      def node_to_source(node)
        return "" unless node
        # Prism nodes have a slice method that returns the original source
        node.slice
      end

      # Normalize a call node to use parentheses format
      # Converts `gem "foo"` to `gem("foo")` style
      # @param node [Prism::CallNode] Call node
      # @return [String] Normalized source code
      def normalize_call_node(node)
        return node.slice.strip unless node.is_a?(Prism::CallNode)

        method_name = node.name
        args = node.arguments&.arguments || []

        if args.empty?
          "#{method_name}()"
        else
          arg_strings = args.map { |arg| normalize_argument(arg) }
          "#{method_name}(#{arg_strings.join(", ")})"
        end
      end

      # Normalize an argument node to canonical format
      # @param arg [Prism::Node] Argument node
      # @return [String] Normalized argument source
      def normalize_argument(arg)
        case arg
        when Prism::StringNode
          "\"#{arg.unescaped}\""
        when Prism::SymbolNode
          ":#{arg.unescaped}"
        when Prism::KeywordHashNode
          # Handle hash arguments like {key: value}
          pairs = arg.elements.map do |assoc|
            key = case assoc.key
            when Prism::SymbolNode then "#{assoc.key.unescaped}:"
            when Prism::StringNode then "\"#{assoc.key.unescaped}\" =>"
            else "#{assoc.key.slice} =>"
            end
            value = normalize_argument(assoc.value)
            "#{key} #{value}"
          end.join(", ")
          pairs
        when Prism::HashNode
          # Handle explicit hash syntax
          pairs = arg.elements.map do |assoc|
            key_part = normalize_argument(assoc.key)
            value_part = normalize_argument(assoc.value)
            "#{key_part} => #{value_part}"
          end.join(", ")
          "{#{pairs}}"
        else
          # For other types (numbers, arrays, etc.), use the original source
          arg.slice.strip
        end
      end

      # Check if a node is a specific method call
      # @param node [Prism::Node] Node to check
      # @param method_name [Symbol] Method name to check for
      # @return [Boolean] True if node is a call to the specified method
      def call_to?(node, method_name)
        node.is_a?(Prism::CallNode) && node.name == method_name
      end

      # Check if a node is a block call to a specific method
      # @param node [Prism::Node] Node to check
      # @param method_name [Symbol] Method name to check for
      # @return [Boolean] True if node is a block call to the specified method
      def block_call_to?(node, method_name)
        node.is_a?(Prism::CallNode) && node.name == method_name && !node.block.nil?
      end
    end
  end
end
