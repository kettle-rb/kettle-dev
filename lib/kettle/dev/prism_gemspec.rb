# frozen_string_literal: true

module Kettle
  module Dev
    # Prism helpers for gemspec manipulation.
    module PrismGemspec
      module_function

      # Emit a debug warning for rescued errors when kettle-dev debugging is enabled.
      # Controlled by KETTLE_DEV_DEBUG=true (or DEBUG=true as fallback).
      # @param error [Exception]
      # @param context [String, Symbol, nil] optional label, often __method__
      # @return [void]
      def debug_error(error, context = nil)
        Kettle::Dev.debug_error(error, context)
      end

      # Extract leading emoji from text using Unicode grapheme clusters
      # @param text [String, nil] Text to extract emoji from
      # @return [String, nil] The first emoji grapheme cluster, or nil if none found
      def extract_leading_emoji(text)
        return nil unless text && text.respond_to?(:scan)
        return nil if text.empty?

        # Get first grapheme cluster
        first = text.scan(/\X/u).first
        return nil unless first

        # Check if it's an emoji using Unicode emoji property
        begin
          emoji_re = Kettle::EmojiRegex::REGEX
          first if first.match?(/\A#{emoji_re.source}/u)
        rescue StandardError => e
          debug_error(e, __method__)
          # Fallback: check if it's non-ASCII (simple heuristic)
          first if first.match?(/[^\x00-\x7F]/)
        end
      end

      # Extract emoji from README H1 heading
      # @param readme_content [String, nil] README content
      # @return [String, nil] The emoji from the first H1, or nil if none found
      def extract_readme_h1_emoji(readme_content)
        return nil unless readme_content && !readme_content.empty?

        lines = readme_content.lines
        h1_line = lines.find { |ln| ln =~ /^#\s+/ }
        return nil unless h1_line

        # Extract text after "# "
        text = h1_line.sub(/^#\s+/, "")
        extract_leading_emoji(text)
      end

      # Extract emoji from gemspec summary or description
      # @param gemspec_content [String] Gemspec content
      # @return [String, nil] The emoji from summary/description, or nil if none found
      def extract_gemspec_emoji(gemspec_content)
        return nil unless gemspec_content

        # Try to extract from summary first, then description
        if gemspec_content =~ /spec\.summary\s*=\s*["']([^"']+)["']/
          emoji = extract_leading_emoji(Regexp.last_match(1))
          return emoji if emoji
        end

        if gemspec_content =~ /spec\.description\s*=\s*["']([^"']+)["']/
          emoji = extract_leading_emoji(Regexp.last_match(1))
          return emoji if emoji
        end

        nil
      end

      # Synchronize README H1 emoji with gemspec emoji
      # @param readme_content [String] README content
      # @param gemspec_content [String] Gemspec content
      # @return [String] Updated README content
      def sync_readme_h1_emoji(readme_content:, gemspec_content:)
        return readme_content unless readme_content && gemspec_content

        gemspec_emoji = extract_gemspec_emoji(gemspec_content)
        return readme_content unless gemspec_emoji

        lines = readme_content.lines
        h1_idx = lines.index { |ln| ln =~ /^#\s+/ }
        return readme_content unless h1_idx

        h1_line = lines[h1_idx]
        text = h1_line.sub(/^#\s+/, "")

        # Remove any existing leading emoji(s)
        begin
          emoji_re = Kettle::EmojiRegex::REGEX
          while text =~ /\A#{emoji_re.source}/u
            cluster = text[/\A\X/u]
            text = text[cluster.length..-1].to_s
          end
          text = text.sub(/\A\s+/, "")
        rescue StandardError => e
          debug_error(e, __method__)
          # Simple fallback
          text = text.sub(/\A[^\x00-\x7F]+\s*/, "")
        end

        # Build new H1 with gemspec emoji
        new_h1 = "# #{gemspec_emoji} #{text}"
        new_h1 += "\n" unless new_h1.end_with?("\n")

        lines[h1_idx] = new_h1
        lines.join
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
          blk_param = (hdr_m && hdr_m[1]) ? hdr_m[1].strip.split(/,\s*/).first : "spec"
        end
        blk_param = "spec" if blk_param.nil? || blk_param.empty?

        # Extract AST-level statements inside the block body when available
        body_node = gemspec_call.block&.body
        return content unless body_node

        # Get the actual body content using Prism's slice
        body_src = body_node.slice
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

        # Helper: check if a value is a placeholder (just emoji + space or just emoji)
        is_placeholder = lambda do |v|
          return false unless v.is_a?(String)
          # Match emoji followed by optional space and nothing else
          # Simple heuristic: 1-4 bytes of non-ASCII followed by optional space
          v.strip.match?(/\A[^\x00-\x7F]{1,4}\s*\z/)
        end

        # Extract existing statement nodes for more precise matching
        stmt_nodes = PrismUtils.extract_statements(body_node)

        # Build a list of edits as (offset, length, replacement_text) tuples
        # We'll apply them in reverse order to avoid offset shifts
        edits = []

        replacements.each do |field_sym, value|
          # Skip special internal keys that are not actual gemspec fields
          next if field_sym == :_remove_self_dependency
          # Skip nil values
          next if value.nil?

          field = field_sym.to_s

          # Find an existing assignment node for this field
          found_node = stmt_nodes.find do |n|
            next false unless n.is_a?(Prism::CallNode)
            begin
              recv = n.receiver
              recv_name = recv ? recv.slice.strip : nil
              recv_name && recv_name.end_with?(blk_param) && n.name.to_s.start_with?(field)
            rescue StandardError
              false
            end
          end

          if found_node
            # Extract existing value to check if we should skip replacement
            existing_arg = found_node.arguments&.arguments&.first
            existing_literal = begin
              PrismUtils.extract_literal_value(existing_arg)
            rescue
              nil
            end

            # For summary and description fields: don't replace real content with placeholders
            if [:summary, :description].include?(field_sym)
              if is_placeholder.call(value) && existing_literal && !is_placeholder.call(existing_literal)
                next
              end
            end

            # Do not replace if the existing RHS is non-literal (e.g., computed expression)
            if existing_literal.nil? && !value.nil?
              debug_error(StandardError.new("Skipping replacement for #{field} because existing RHS is non-literal"), __method__)
            else
              # Schedule replacement using location offsets
              loc = found_node.location
              indent = begin
                found_node.slice.lines.first.match(/^(\s*)/)[1]
              rescue
                "  "
              end
              rhs = build_literal.call(value)
              replacement = "#{indent}#{blk_param}.#{field} = #{rhs}"
              edits << [loc.start_offset - body_node.location.start_offset, loc.end_offset - loc.start_offset, replacement]
            end
          else
            # No existing assignment; we'll insert after spec.version if present
            # But skip inserting placeholders for summary/description if not present
            if [:summary, :description].include?(field_sym) && is_placeholder.call(value)
              next
            end

            version_node = stmt_nodes.find do |n|
              n.is_a?(Prism::CallNode) && n.name.to_s.start_with?("version", "version=") && n.receiver && n.receiver.slice.strip.end_with?(blk_param)
            end

            insert_line = "  #{blk_param}.#{field} = #{build_literal.call(value)}\n"
            if version_node
              # Insert after version node
              insert_offset = version_node.location.end_offset - body_node.location.start_offset
              edits << [insert_offset, 0, "\n" + insert_line]
            else
              # Append at end of body
              insert_offset = body_src.rstrip.length
              edits << [insert_offset, 0, "\n" + insert_line]
            end
          end
        end

        # Handle removal of self-dependency
        if replacements[:_remove_self_dependency]
          name_to_remove = replacements[:_remove_self_dependency].to_s
          dep_nodes = stmt_nodes.select do |n|
            next false unless n.is_a?(Prism::CallNode)
            recv = begin
              n.receiver
            rescue
              nil
            end
            next false unless recv && recv.slice.strip.end_with?(blk_param)
            [:add_dependency, :add_development_dependency].include?(n.name)
          end

          dep_nodes.each do |dn|
            first_arg = dn.arguments&.arguments&.first
            arg_val = begin
              PrismUtils.extract_literal_value(first_arg)
            rescue
              nil
            end
            if arg_val && arg_val.to_s == name_to_remove
              loc = dn.location
              # Remove entire line including newline if present
              relative_start = loc.start_offset - body_node.location.start_offset
              relative_end = loc.end_offset - body_node.location.start_offset

              line_start = body_src.rindex("\n", relative_start)
              line_start = line_start ? line_start + 1 : 0

              line_end = body_src.index("\n", relative_end)
              line_end = line_end ? line_end + 1 : body_src.length

              edits << [line_start, line_end - line_start, ""]
            end
          end
        end

        # Apply edits in reverse order by offset to avoid offset shifts
        edits.sort_by! { |offset, _len, _repl| -offset }
        new_body = body_src.dup
        edits.each do |offset, length, replacement|
          # Validate offset, length, and replacement
          next if offset.nil? || length.nil? || offset < 0 || length < 0
          next if offset > new_body.length
          next if replacement.nil?

          new_body[offset, length] = replacement
        end

        # Reassemble the gemspec call by replacing just the body
        call_start = gemspec_call.location.start_offset
        call_end = gemspec_call.location.end_offset
        body_start = body_node.location.start_offset
        body_end = body_node.location.end_offset

        # Validate all offsets before string operations
        if call_start.nil? || call_end.nil? || body_start.nil? || body_end.nil?
          debug_error(StandardError.new("Nil offset detected: call_start=#{call_start.inspect}, call_end=#{call_end.inspect}, body_start=#{body_start.inspect}, body_end=#{body_end.inspect}"), __method__)
          return content
        end

        # Validate offset relationships
        if call_start > call_end || body_start > body_end || call_start > body_start || body_end > call_end
          debug_error(StandardError.new("Invalid offset relationships: call[#{call_start}...#{call_end}], body[#{body_start}...#{body_end}]"), __method__)
          return content
        end

        # Validate content length (Prism uses byte offsets, not character offsets)
        content_length = content.bytesize
        if call_end > content_length || body_end > content_length
          debug_error(StandardError.new("Offsets exceed content bytesize (#{content_length}): call_end=#{call_end}, body_end=#{body_end}, char_length=#{content.length}"), __method__)
          debug_error(StandardError.new("Content snippet: #{content[-50..-1].inspect}"), __method__)
          return content
        end

        # Build the new gemspec call with safe string slicing using byte offsets
        # Note: We need to use byteslice for byte offsets, not regular slicing
        prefix = content.byteslice(call_start...body_start) || ""
        suffix = content.byteslice(body_end...call_end) || ""
        new_call = prefix + new_body + suffix

        # Replace in original content using byte offsets
        result_prefix = content.byteslice(0...call_start) || ""
        result_suffix = content.byteslice(call_end..-1) || ""
        result_prefix + new_call + result_suffix
      rescue StandardError => e
        debug_error(e, __method__)
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
            debug_error(e, __method__)
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
            val = begin
              PrismUtils.extract_literal_value(first_arg)
            rescue
              nil
            end
            val && val.to_s == gem_name
          end

          if found
            # Replace existing node slice with desired_line, preserving indent
            indent = begin
              found.slice.lines.first.match(/^(\s*)/)[1]
            rescue
              "  "
            end
            replacement = indent + desired_line.strip + "\n"
            new_body = new_body.sub(found.slice, replacement)
          else
            # Insert after version_node if present, else append before end
            insert_line = "  " + desired_line.strip + "\n"
            new_body = if version_node
              new_body.sub(version_node.slice, version_node.slice + "\n" + insert_line)
            else
              new_body.rstrip + "\n" + insert_line
            end
          end
        end

        new_call_src = call_src.sub(body_src, new_body)
        content.sub(call_src, new_call_src)
      rescue StandardError => e
        debug_error(e, __method__)
        content
      end
    end
  end
end
