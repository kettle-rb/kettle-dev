# frozen_string_literal: true

module Kettle
  module Dev
    # Prism helpers for Gemfile-like merging.
    module PrismGemfile
      module_function

      # Merge gem calls from src_content into dest_content.
      # - Replaces dest `source` call with src's if present.
      # - Replaces or inserts non-comment `git_source` definitions.
      # - Appends missing `gem` calls (by name) from src to dest preserving dest content and newlines.
      # Uses Prism::Merge with pre-filtering to only merge top-level statements.
      def merge_gem_calls(src_content, dest_content)
        # Lazy load prism-merge (Ruby 2.7+ requirement)
        begin
          require "prism/merge" unless defined?(Prism::Merge)
        rescue LoadError
          Kernel.warn("[#{__method__}] prism-merge gem not available, returning dest_content")
          return dest_content
        end

        # Pre-filter: Extract only top-level gem-related calls from src
        # This prevents nested gems (in groups, conditionals) from being added
        src_filtered = filter_to_top_level_gems(src_content)

        # Always remove :github git_source from dest as it's built-in to Bundler
        dest_processed = remove_github_git_source(dest_content)

        # Custom signature generator that normalizes string quotes to prevent
        # duplicates when gem "foo" and gem 'foo' are present.
        signature_generator = ->(node) do
          return unless node.is_a?(Prism::CallNode)
          return unless [:gem, :source, :git_source].include?(node.name)

          # For source(), there should only be one, so signature is just [:source]
          return [:source] if node.name == :source

          first_arg = node.arguments&.arguments&.first

          # Normalize string quotes using unescaped value
          arg_value = case first_arg
          when Prism::StringNode
            first_arg.unescaped.to_s
          when Prism::SymbolNode
            first_arg.unescaped.to_sym
          end

          arg_value ? [node.name, arg_value] : nil
        end

        # Use Prism::Merge with template preference for source/git_source replacement
        merger = Prism::Merge::SmartMerger.new(
          src_filtered,
          dest_processed,
          signature_match_preference: :template,
          add_template_only_nodes: true,
          signature_generator: signature_generator,
        )
        merger.merge
      rescue Prism::Merge::Error => e
        # Use debug_log if available, otherwise Kettle::Dev.debug_error
        if defined?(Kettle::Dev) && Kettle::Dev.respond_to?(:debug_error)
          Kettle::Dev.debug_error(e, __method__)
        else
          Kernel.warn("[#{__method__}] Prism::Merge failed: #{e.class}: #{e.message}")
        end
        dest_content
      end

      # Filter source content to only include top-level gem-related calls
      # Excludes gems inside groups, conditionals, blocks, etc.
      def filter_to_top_level_gems(content)
        parse_result = PrismUtils.parse_with_comments(content)
        return content unless parse_result.success?

        # Extract only top-level statements (not nested in blocks)
        top_level_stmts = PrismUtils.extract_statements(parse_result.value.statements)

        # Filter to only SIMPLE gem-related calls (not blocks, conditionals, etc.)
        # We want to exclude:
        # - group { ... } blocks (CallNode with a block)
        # - if/unless conditionals (IfNode, UnlessNode)
        # - any other compound structures
        filtered_stmts = top_level_stmts.select do |stmt|
          # Skip blocks (group, if, unless, etc.)
          next false if stmt.is_a?(Prism::IfNode) || stmt.is_a?(Prism::UnlessNode)

          # Only process CallNodes
          next false unless stmt.is_a?(Prism::CallNode)

          # Skip calls that have blocks (like `group :development do ... end`),
          # but allow `git_source` which is commonly defined with a block.
          next false if stmt.block && stmt.name != :git_source

          # Only include gem-related methods
          [:gem, :source, :git_source, :eval_gemfile].include?(stmt.name)
        end

        return "" if filtered_stmts.empty?

        # Build filtered content by extracting slices with proper newlines.
        # Preserve inline comments that Prism separates into comment nodes.
        filtered_stmts.map do |stmt|
          src = stmt.slice.rstrip
          inline = begin
            PrismUtils.inline_comments_for_node(parse_result, stmt)
          rescue
            []
          end
          if inline && inline.any?
            # append inline comments (they already include leading `#` and spacing)
            src + " " + inline.map(&:slice).map(&:strip).join(" ")
          else
            src
          end
        end.join("\n") + "\n"
      rescue StandardError => e
        # If filtering fails, return original content
        if defined?(Kettle::Dev) && Kettle::Dev.respond_to?(:debug_error)
          Kettle::Dev.debug_error(e, __method__)
        end
        content
      end

      # Remove git_source(:github) from content to allow template git_sources to replace it.
      # This is special handling because :github is the default and templates typically
      # want to replace it with their own git_source definitions.
      # @param content [String] Gemfile-like content
      # @return [String] content with git_source(:github) removed
      def remove_github_git_source(content)
        result = PrismUtils.parse_with_comments(content)
        return content unless result.success?

        stmts = PrismUtils.extract_statements(result.value.statements)

        # Find git_source(:github) node
        github_node = stmts.find do |n|
          next false unless n.is_a?(Prism::CallNode) && n.name == :git_source

          first_arg = n.arguments&.arguments&.first
          first_arg.is_a?(Prism::SymbolNode) && first_arg.unescaped == "github"
        end

        return content unless github_node

        # Remove the node's slice from content
        content.sub(github_node.slice, "")
      rescue StandardError => e
        if defined?(Kettle::Dev) && Kettle::Dev.respond_to?(:debug_error)
          Kettle::Dev.debug_error(e, __method__)
        end
        content
      end

      # Remove gem calls that reference the given gem name (to prevent self-dependency).
      # Works by locating gem() call nodes where the first argument matches gem_name.
      # @param content [String] Gemfile-like content
      # @param gem_name [String] the gem name to remove
      # @return [String] modified content with self-referential gem calls removed
      def remove_gem_dependency(content, gem_name)
        return content if gem_name.to_s.strip.empty?

        result = PrismUtils.parse_with_comments(content)
        stmts = PrismUtils.extract_statements(result.value.statements)

        # Find gem call nodes where first argument matches gem_name
        gem_nodes = stmts.select do |n|
          next false unless n.is_a?(Prism::CallNode) && n.name == :gem

          first_arg = n.arguments&.arguments&.first
          arg_val = begin
            PrismUtils.extract_literal_value(first_arg)
          rescue StandardError
            nil
          end
          arg_val && arg_val.to_s == gem_name.to_s
        end

        # Remove each matching gem call from content
        out = content.dup
        gem_nodes.each do |gn|
          # Remove the entire line(s) containing this node
          out = out.sub(gn.slice, "")
        end

        out
      rescue StandardError => e
        if defined?(Kettle::Dev) && Kettle::Dev.respond_to?(:debug_error)
          Kettle::Dev.debug_error(e, __method__)
        else
          Kernel.warn("[#{__method__}] #{e.class}: #{e.message}")
        end
        content
      end
    end
  end
end
