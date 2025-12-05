# frozen_string_literal: true

require "set"

module Kettle
  module Dev
    # AST-driven merger for Appraisals files using Prism.
    # Delegates to Prism::Merge for the heavy lifting.
    # Uses PrismUtils for shared Prism AST operations.
    module PrismAppraisals
      module_function

      # Merge template and destination Appraisals files preserving comments
      def merge(template_content, dest_content)
        template_content ||= ""
        dest_content ||= ""

        return template_content if dest_content.strip.empty?
        return dest_content if template_content.strip.empty?

        # Lazy load prism-merge (Ruby 2.7+ requirement)
        begin
          require "prism/merge" unless defined?(Prism::Merge)
        rescue LoadError
          puts "WARNING: prism-merge gem not available, returning template_content"
          return template_content
        end

        # For Appraisals files:
        # - Use :template preference so template's appraise blocks (with all their contents) win
        # - Set add_template_only_nodes to true to include new appraise blocks from template
        # - This ensures eval_gemfile and gem calls from template are included
        merger = Prism::Merge::SmartMerger.new(
          template_content,
          dest_content,
          signature_match_preference: :template,
          add_template_only_nodes: true,
        )
        merger.merge
      rescue Prism::Merge::Error => e
        puts "WARNING: Prism::Merge failed for Appraisals merge: #{e.message}"
        template_content
      end

      # Remove gem calls that reference the given gem name (to prevent self-dependency).
      # Works by locating gem() call nodes within appraise blocks where the first argument matches gem_name.
      # @param content [String] Appraisals content
      # @param gem_name [String] the gem name to remove
      # @return [String] modified content with self-referential gem calls removed
      def remove_gem_dependency(content, gem_name)
        return content if gem_name.to_s.strip.empty?

        result = PrismUtils.parse_with_comments(content)
        root = result.value
        return content unless root&.statements&.body

        out = content.dup

        # Iterate through all appraise blocks
        root.statements.body.each do |node|
          next unless appraise_call?(node)
          next unless node.block&.body

          body_stmts = PrismUtils.extract_statements(node.block.body)

          # Find gem call nodes within this appraise block where first argument matches gem_name
          body_stmts.each do |stmt|
            next unless stmt.is_a?(Prism::CallNode) && stmt.name == :gem

            first_arg = stmt.arguments&.arguments&.first
            arg_val = begin
              PrismUtils.extract_literal_value(first_arg)
            rescue StandardError
              nil
            end

            if arg_val && arg_val.to_s == gem_name.to_s
              # Remove this gem call from content
              out = out.sub(stmt.slice, "")
            end
          end
        end

        out
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__) if defined?(Kettle::Dev.debug_error)
        content
      end

      # Helper: Check if node is an appraise block call
      def appraise_call?(node)
        PrismUtils.block_call_to?(node, :appraise)
      end
    end
  end
end
