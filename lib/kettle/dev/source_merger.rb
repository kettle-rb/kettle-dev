# frozen_string_literal: true

module Kettle
  module Dev
    # Prism-based AST merging for templated Ruby files.
    # Handles strategy dispatch (skip/replace/append/merge).
    #
    # Uses prism-merge for AST-aware merging with support for:
    # - Freeze blocks (kettle-dev:freeze / kettle-dev:unfreeze)
    # - Comment preservation
    # - Signature-based node matching
    module SourceMerger
      BUG_URL = "https://github.com/kettle-rb/kettle-dev/issues"

      module_function

      # Apply a templating strategy to merge source and destination Ruby files
      #
      # @param strategy [Symbol] Merge strategy - :skip, :replace, :append, or :merge
      # @param src [String] Template source content
      # @param dest [String] Destination file content
      # @param path [String] File path (for error messages)
      # @return [String] Merged content with comments preserved
      # @raise [Kettle::Dev::Error] If strategy is unknown or merge fails
      # @example
      #   SourceMerger.apply(
      #     strategy: :merge,
      #     src: 'gem "foo"',
      #     dest: 'gem "bar"',
      #     path: "Gemfile"
      #   )
      def apply(strategy:, src:, dest:, path:)
        strategy = normalize_strategy(strategy)
        dest ||= ""
        src_content = src.to_s
        dest_content = dest

        result =
          case strategy
          when :skip
            # For skip, use merge to preserve freeze blocks (works with empty dest too)
            apply_merge(src_content, dest_content)
          when :replace
            # For replace, use merge with template preference
            apply_merge(src_content, dest_content)
          when :append
            # For append, use merge with destination preference
            apply_append(src_content, dest_content)
          when :merge
            # For merge, use merge with template preference
            apply_merge(src_content, dest_content)
          else
            raise Kettle::Dev::Error, "Unknown templating strategy '#{strategy}' for #{path}."
          end

        ensure_trailing_newline(result)
      rescue StandardError => error
        warn_bug(path, error)
        raise Kettle::Dev::Error, "Template merge failed for #{path}: #{error.message}"
      end

      # Normalize strategy to a symbol
      #
      # @param strategy [Symbol, String, nil] Strategy to normalize
      # @return [Symbol] Normalized strategy (:skip if nil)
      # @api private
      def normalize_strategy(strategy)
        return :skip if strategy.nil?
        strategy.to_s.downcase.strip.to_sym
      end

      # Log error information for debugging
      #
      # @param path [String] File path that caused the error
      # @param error [StandardError] The error that occurred
      # @return [void]
      # @api private
      def warn_bug(path, error)
        puts "ERROR: kettle-dev templating failed for #{path}: #{error.message}"
        puts "Please file a bug at #{BUG_URL} with the file contents so we can improve the AST merger."
      end

      # Ensure text ends with exactly one newline
      #
      # @param text [String, nil] Text to process
      # @return [String] Text with trailing newline (empty string if nil)
      # @api private
      def ensure_trailing_newline(text)
        return "" if text.nil?
        text.end_with?("\n") ? text : text + "\n"
      end

      # Apply append strategy using prism-merge
      #
      # Uses destination preference for signature matching, which means
      # existing nodes in dest are preferred over template nodes.
      #
      # @param src_content [String] Template source content
      # @param dest_content [String] Destination content
      # @return [String] Merged content
      # @api private
      def apply_append(src_content, dest_content)
        # Lazy load prism-merge (Ruby 2.7+ requirement)
        begin
          require "prism/merge" unless defined?(Prism::Merge)
        rescue LoadError
          puts "WARNING: prism-merge gem not available, falling back to source content"
          return src_content
        end

        # Custom signature generator that handles various Ruby constructs
        signature_generator = create_signature_generator

        merger = Prism::Merge::SmartMerger.new(
          src_content,
          dest_content,
          signature_match_preference: :destination,
          add_template_only_nodes: true,
          signature_generator: signature_generator,
          freeze_token: "kettle-dev",
        )
        merger.merge
      rescue Prism::Merge::Error => e
        puts "WARNING: Prism::Merge failed for append strategy: #{e.message}"
        src_content
      end

      # Apply merge strategy using prism-merge
      #
      # Uses template preference for signature matching, which means
      # template nodes take precedence over existing destination nodes.
      #
      # @param src_content [String] Template source content
      # @param dest_content [String] Destination content
      # @return [String] Merged content
      # @api private
      def apply_merge(src_content, dest_content)
        # Lazy load prism-merge (Ruby 2.7+ requirement)
        begin
          require "prism/merge" unless defined?(Prism::Merge)
        rescue LoadError
          puts "WARNING: prism-merge gem not available, falling back to source content"
          return src_content
        end

        # Custom signature generator that handles various Ruby constructs
        signature_generator = create_signature_generator

        merger = Prism::Merge::SmartMerger.new(
          src_content,
          dest_content,
          signature_match_preference: :template,
          add_template_only_nodes: true,
          signature_generator: signature_generator,
          freeze_token: "kettle-dev",
        )
        merger.merge
      rescue Prism::Merge::Error => e
        puts "WARNING: Prism::Merge failed for merge strategy: #{e.message}"
        src_content
      end

      # Create a signature generator for prism-merge
      #
      # The signature generator customizes how nodes are matched during merge:
      # - `source()` calls: Match by method name only (singleton)
      # - Assignment methods (`spec.foo =`): Match by receiver and method name
      # - `gem()` calls: Match by gem name (first argument)
      # - Other calls with arguments: Match by method name and first argument
      #
      # @return [Proc] Lambda that generates signatures for Prism nodes
      # @api private
      def create_signature_generator
        ->(node) do
          # Only customize CallNode signatures
          if node.is_a?(Prism::CallNode)
            # For source(), there should only be one, so signature is just [:source]
            return [:source] if node.name == :source

            method_name = node.name.to_s
            receiver_name = node.receiver.is_a?(Prism::CallNode) ? node.receiver.name.to_s : node.receiver&.slice

            # For assignment methods (like spec.homepage = "url"), match by receiver
            # and method name only - don't include the value being assigned.
            # This ensures spec.homepage = "url1" matches spec.homepage = "url2"
            if method_name.end_with?("=")
              return [:call, node.name, receiver_name]
            end

            # For gem() calls, match by first argument (gem name)
            if node.name == :gem
              first_arg = node.arguments&.arguments&.first
              if first_arg.is_a?(Prism::StringNode)
                return [:gem, first_arg.unescaped]
              end
            end

            # For other methods with arguments, include the first argument for matching
            # e.g. spec.add_dependency("gem_name", "~> 1.0") -> [:add_dependency, "gem_name"]
            first_arg = node.arguments&.arguments&.first
            arg_value = case first_arg
            when Prism::StringNode
              first_arg.unescaped.to_s
            when Prism::SymbolNode
              first_arg.unescaped.to_sym
            end

            return [node.name, arg_value] if arg_value
          end

          # Return the node to fall through to default signature computation
          node
        end
      end
    end
  end
end
