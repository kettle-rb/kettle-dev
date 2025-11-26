# frozen_string_literal: true

module Kettle
  module Dev
    # Prism helpers for gemspec manipulation.
    module PrismGemspec
      module_function

      # Internal logging helper: prefer Kettle::Dev.debug_error when available,
      # otherwise fall back to Kernel.warn so callers that require this file
      # directly (without loading lib/kettle/dev.rb) still get a useful message.
      def debug_log(error, context = nil)
        if defined?(Kettle::Dev) && Kettle::Dev.respond_to?(:debug_error)
          Kettle::Dev.debug_error(error, context)
        else
          begin
            ctx = context ? context.to_s : "rescue"
            Kernel.warn("[#{ctx}] #{error.class}: #{error.message}")
          rescue Exception
            # never raise from debug logging
          end
        end
      end

      # Replace scalar or array assignments inside a Gem::Specification.new block.
      # `replacements` is a hash mapping symbol field names to string or array values.
      # Operates only inside the Gem::Specification block to avoid accidental matches.
      def replace_gemspec_fields(content, replacements = {})
        return content if replacements.nil? || replacements.empty?

        result = PrismUtils.parse_with_comments(content)
        stmts = PrismUtils.extract_statements(result.value.statements)

        gemspec_call = stmts.find do |s|
          s.is_a?(Prism::CallNode) && s.block && PrismUtils.extract_const_name(s.receiver) == "Gem::Specification" && s.name == :new
        end
        return content unless gemspec_call

        call_src = gemspec_call.slice

        # Try to detect block parameter name (e.g., |spec|)
        blk_param = nil
        begin
          if gemspec_call.block && gemspec_call.block.params
            # Attempt a few defensive ways to extract a param name
            if gemspec_call.block.params.respond_to?(:parameters) && gemspec_call.block.params.parameters.respond_to?(:first)
              p = gemspec_call.block.params.parameters.first
              blk_param = p.name.to_s if p.respond_to?(:name)
            elsif gemspec_call.block.params.respond_to?(:first)
              p = gemspec_call.block.params.first
              blk_param = p.name.to_s if p && p.respond_to?(:name)
            end
          end
        rescue StandardError
          blk_param = nil
        end

        # Fallback to crude parse of the call_src header
        unless blk_param && !blk_param.to_s.empty?
          hdr_m = call_src.match(/do\b[^\n]*\|([^|]+)\|/m)
          blk_param = hdr_m && hdr_m[1] ? hdr_m[1].strip.split(/,\s*/).first : "spec"
        end
        blk_param = "spec" if blk_param.nil? || blk_param.empty?

        # Extract AST-level statements inside the block body when available
        body_node = gemspec_call.block&.body
        body_src = ""
        begin
          # Try to extract the textual body from call_src using the do|...| ... end capture
          if (m = call_src.match(/do\b[^\n]*\|[^|]*\|\s*(.*)end\s*\z/m))
            body_src = m[1]
          else
            # Last resort: attempt to take slice of body node
            body_src = body_node ? body_node.slice : ""
          end
        rescue StandardError
          body_src = body_node ? body_node.slice : ""
        end

        new_body = body_src.dup

        # Helper: build literal text for replacement values
        build_literal = lambda do |v|
          if v.is_a?(Array)
            arr = v.compact.map(&:to_s).map { |e| '"' + e.gsub('"', '\\"') + '"' }
            "[" + arr.join(", ") + "]"
          else
            '"' + v.to_s.gsub('"', '\\"') + '"'
          end
        end

        # Extract existing statement nodes for more precise matching
        stmt_nodes = PrismUtils.extract_statements(body_node)

        replacements.each do |field_sym, value|
          # Skip special internal keys that are not actual gemspec fields
          next if field_sym == :_remove_self_dependency

          field = field_sym.to_s

          # Find an existing assignment node for this field: look for call nodes where
          # receiver slice matches the block param and method name matches assignment
          found_node = stmt_nodes.find do |n|
            next false unless n.is_a?(Prism::CallNode)
            begin
              recv = n.receiver
              recv_name = recv ? recv.slice.strip : nil
              # match receiver variable name or literal slice
              recv_name && recv_name.end_with?(blk_param) && n.name.to_s.start_with?(field)
            rescue StandardError
              false
            end
          end

          if found_node
            # Do not replace if the existing RHS is non-literal (e.g., computed expression)
            existing_arg = found_node.arguments&.arguments&.first
            existing_literal = PrismUtils.extract_literal_value(existing_arg) rescue nil
            if existing_literal.nil? && !value.nil?
              # Skip replacing a non-literal RHS to avoid altering computed expressions.
              debug_log(StandardError.new("Skipping replacement for #{field} because existing RHS is non-literal"), __method__)
            else
              # Replace the found node's slice in the body text with the updated assignment
              indent = found_node.slice.lines.first.match(/^(\s*)/)[1] rescue "  "
              rhs = build_literal.call(value)
              replacement = "#{indent}#{blk_param}.#{field} = #{rhs}"
              new_body = new_body.sub(found_node.slice, replacement)
            end
          else
            # No existing assignment; insert after spec.version if present, else append
            version_node = stmt_nodes.find do |n|
              n.is_a?(Prism::CallNode) && (n.name.to_s.start_with?("version") || n.name.to_s.start_with?("version=")) && n.receiver && n.receiver.slice.strip.end_with?(blk_param)
            end

            insert_line = "  #{blk_param}.#{field} = #{build_literal.call(value)}\n"
            if version_node
              # Insert after the version node slice
              new_body = new_body.sub(version_node.slice, version_node.slice + "\n" + insert_line)
            else
              # Append before the final newline if present, else just append
              if new_body.rstrip.end_with?('\n')
                new_body = new_body.rstrip + "\n" + insert_line
              else
                new_body = new_body.rstrip + "\n" + insert_line
              end
            end
          end
        end

        # Handle removal of self-dependency if requested via :_remove_self_dependency
        if replacements[:_remove_self_dependency]
          name_to_remove = replacements[:_remove_self_dependency].to_s
          # Find dependency call nodes to remove (add_dependency/add_development_dependency)
          dep_nodes = stmt_nodes.select do |n|
            next false unless n.is_a?(Prism::CallNode)
            recv = n.receiver rescue nil
            next false unless recv && recv.slice.strip.end_with?(blk_param)
            [:add_dependency, :add_development_dependency].include?(n.name)
          end
          dep_nodes.each do |dn|
            # Check first argument literal
            first_arg = dn.arguments&.arguments&.first
            arg_val = PrismUtils.extract_literal_value(first_arg) rescue nil
            if arg_val && arg_val.to_s == name_to_remove
              # Remove this node's slice from new_body
              new_body = new_body.sub(dn.slice, "")
            end
          end
        end

        # Reassemble call source by replacing the captured body portion
        new_call_src = call_src.sub(body_src, new_body)
        content.sub(call_src, new_call_src)
      rescue StandardError => e
        debug_log(e, __method__)
        content
      end

      # Remove spec.add_dependency / add_development_dependency calls that name the given gem
      # Works by locating the Gem::Specification block and filtering out matching call lines.
      def remove_spec_dependency(content, gem_name)
        return content if gem_name.to_s.strip.empty?
        replace_gemspec_fields(content, _remove_self_dependency: gem_name)
      end

      # Ensure development dependency lines in a gemspec match the desired lines.
      # `desired` is a hash mapping gem_name => desired_line (string, without leading indentation).
      # Returns the modified gemspec content (or original on error).
      def ensure_development_dependencies(content, desired)
        return content if desired.nil? || desired.empty?
        result = PrismUtils.parse_with_comments(content)
        stmts = PrismUtils.extract_statements(result.value.statements)
        gemspec_call = stmts.find do |s|
          s.is_a?(Prism::CallNode) && s.block && PrismUtils.extract_const_name(s.receiver) == "Gem::Specification" && s.name == :new
        end

        # If we couldn't locate the Gem::Specification.new block (e.g., empty or
        # truncated gemspec), fall back to appending the desired development
        # dependency lines to the end of the file so callers still get the
        # expected dependency declarations.
        unless gemspec_call
          begin
            out = content.dup
            out << "\n" unless out.end_with?("\n") || out.empty?
            desired.each do |_gem, line|
              out << line.strip + "\n"
            end
            return out
          rescue StandardError => e
            debug_log(e, __method__)
            return content
          end
        end

        call_src = gemspec_call.slice
        body_node = gemspec_call.block&.body
        body_src = begin
          if (m = call_src.match(/do\b[^\n]*\|[^|]*\|\s*(.*)end\s*\z/m))
            m[1]
          else
            body_node ? body_node.slice : ""
          end
        rescue StandardError
          body_node ? body_node.slice : ""
        end

        new_body = body_src.dup
        stmt_nodes = PrismUtils.extract_statements(body_node)

        # Find version node to choose insertion point
        version_node = stmt_nodes.find do |n|
          n.is_a?(Prism::CallNode) && n.name.to_s.start_with?("version") && n.receiver && n.receiver.slice.strip.end_with?("spec")
        end

        desired.each do |gem_name, desired_line|
          # Skip commented occurrences - we only act on actual AST nodes
          found = stmt_nodes.find do |n|
            next false unless n.is_a?(Prism::CallNode)
            next false unless [:add_development_dependency, :add_dependency].include?(n.name)
            first_arg = n.arguments&.arguments&.first
            val = PrismUtils.extract_literal_value(first_arg) rescue nil
            val && val.to_s == gem_name
          end

          if found
            # Replace existing node slice with desired_line, preserving indent
            indent = found.slice.lines.first.match(/^(\s*)/)[1] rescue "  "
            replacement = indent + desired_line.strip + "\n"
            new_body = new_body.sub(found.slice, replacement)
          else
            # Insert after version_node if present, else append before end
            insert_line = "  " + desired_line.strip + "\n"
            if version_node
              new_body = new_body.sub(version_node.slice, version_node.slice + "\n" + insert_line)
            else
              new_body = new_body.rstrip + "\n" + insert_line
            end
          end
        end

        new_call_src = call_src.sub(body_src, new_body)
        content.sub(call_src, new_call_src)
      rescue StandardError => e
        debug_log(e, __method__)
        content
      end
    end
  end
end
