# frozen_string_literal: true

require "set"

module Kettle
  module Dev
    # AST-driven merger for Appraisals files using Prism.
    # Preserves all comments: preamble headers, block headers, and inline comments.
    # Uses PrismUtils for shared Prism AST operations.
    module PrismAppraisals
      TRACKED_METHODS = [:gem, :eval_gemfile, :gemfile].freeze

      module_function

      # Merge template and destination Appraisals files preserving comments
      def merge(template_content, dest_content)
        template_content ||= ""
        dest_content ||= ""

        return template_content if dest_content.strip.empty?
        return dest_content if template_content.strip.empty?

        tmpl_result = PrismUtils.parse_with_comments(template_content)
        dest_result = PrismUtils.parse_with_comments(dest_content)

        tmpl_preamble_comments, tmpl_blocks = extract_blocks(tmpl_result, template_content)
        dest_preamble_comments, dest_blocks = extract_blocks(dest_result, dest_content)

        tmpl_preamble = preamble_lines_from_comments(tmpl_preamble_comments, template_content.lines)
        dest_preamble = preamble_lines_from_comments(dest_preamble_comments, dest_content.lines)

        merged_preamble = merge_preambles(tmpl_preamble, dest_preamble)
        merged_blocks = merge_blocks(tmpl_blocks, dest_blocks, tmpl_result, dest_result)

        build_output(merged_preamble, merged_blocks)
      end

      def preamble_lines_from_comments(comments, source_lines)
        return [] if comments.empty?

        covered = Set.new
        comments.each do |comment|
          ((comment.location.start_line - 1)..(comment.location.end_line - 1)).each do |idx|
            covered << idx
          end
        end

        return [] if covered.empty?

        extracted = []
        sorted = covered.sort
        cursor = sorted.first

        sorted.each do |line_idx|
          while cursor < line_idx
            line = source_lines[cursor]
            extracted << "" if line&.strip&.empty?
            cursor += 1
          end
          line = source_lines[line_idx]
          extracted << line.to_s.chomp if line
          cursor = line_idx + 1
        end

        while cursor < source_lines.length && source_lines[cursor]&.strip&.empty?
          extracted << ""
          cursor += 1
        end

        extracted
      end

      # ...existing helper methods copied from original AppraisalsAstMerger...
      def extract_blocks(parse_result, source_content)
        root = parse_result.value
        return [[], []] unless root&.statements&.body

        source_lines = source_content.lines
        source_line_types = classify_source_lines(source_lines)
        blocks = []
        first_appraise_line = nil

        root.statements.body.each do |node|
          if appraise_call?(node)
            first_appraise_line ||= node.location.start_line
            name = extract_appraise_name(node)
            next unless name

            block_header = extract_block_header(node, source_lines, source_line_types, blocks)

            blocks << {
              node: node,
              name: name,
              header: block_header,
            }
          end
        end

        preamble_comments = if first_appraise_line
          parse_result.comments.select { |c| c.location.start_line < first_appraise_line }
        else
          parse_result.comments
        end

        block_header_lines = blocks.flat_map { |b| b[:header].lines.map { |l| l.strip } }.to_set
        preamble_comments = preamble_comments.reject { |c| block_header_lines.include?(c.slice.strip) }

        [preamble_comments, blocks]
      end

      def appraise_call?(node)
        PrismUtils.block_call_to?(node, :appraise)
      end

      def extract_appraise_name(node)
        return unless node.is_a?(Prism::CallNode)
        PrismUtils.extract_literal_value(node.arguments&.arguments&.first)
      end

      def merge_preambles(tmpl_lines, dest_lines)
        return tmpl_lines.dup if dest_lines.empty?
        return dest_lines.dup if tmpl_lines.empty?

        merged = []
        seen = Set.new

        [tmpl_lines, dest_lines].each do |source|
          source.each do |line|
            append_structural_line(merged, line, seen)
          end
        end

        merged << "" unless merged.empty? || merged.last.empty?
        merged
      end

      def classify_source_lines(source_lines)
        source_lines.map do |line|
          stripped = line.to_s.strip
          if stripped.empty?
            :blank
          elsif stripped.start_with?("#")
            body = stripped.sub(/^#/, "").strip
            body.empty? ? :empty_comment : :comment
          else
            :code
          end
        end
      end

      def extract_block_header(node, source_lines, source_line_types, previous_blocks)
        begin_line = node.location.start_line
        min_line = previous_blocks.empty? ? 1 : previous_blocks.last[:node].location.end_line + 1
        check_line = begin_line - 2
        header_lines = []

        while check_line >= 0 && (check_line + 1) >= min_line
          line = source_lines[check_line]
          break unless line

          case source_line_types[check_line]
          when :comment, :empty_comment
            header_lines.unshift(line)
          when :blank
            # Skip a blank gap immediately above the block, but use it as a hard
            # boundary once we have already collected comment lines.
            if header_lines.empty?
              check_line -= 1
              next
            end
            break
          else
            break
          end

          check_line -= 1
        end

        header_lines.join
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__) if defined?(Kettle::Dev.debug_error)
        ""
      end

      def merge_blocks(template_blocks, dest_blocks, tmpl_result, dest_result)
        merged = []
        dest_by_name = dest_blocks.each_with_object({}) { |b, h| h[b[:name]] = b }
        template_names = template_blocks.map { |b| b[:name] }.to_set
        placed_dest = Set.new

        template_blocks.each_with_index do |tmpl_block, idx|
          name = tmpl_block[:name]
          if idx == 0 || dest_by_name[name]
            dest_blocks.each do |db|
              next if template_names.include?(db[:name])
              next if placed_dest.include?(db[:name])
              dest_idx_of_shared = dest_blocks.index { |b| b[:name] == name }
              dest_idx_of_only = dest_blocks.index { |b| b[:name] == db[:name] }
              if dest_idx_of_only && dest_idx_of_shared && dest_idx_of_only < dest_idx_of_shared
                merged << db
                placed_dest << db[:name]
              end
            end
          end

          dest_block = dest_by_name[name]
          if dest_block
            merged_header = merge_block_headers(tmpl_block[:header], dest_block[:header])
            merged_statements = merge_block_statements(
              tmpl_block[:node].block.body,
              dest_block[:node].block.body,
              dest_result,
            )
            merged << {
              name: name,
              header: merged_header,
              node: tmpl_block[:node],
              statements: merged_statements,
            }
            placed_dest << name
          else
            merged << tmpl_block
          end
        end

        dest_blocks.each do |dest_block|
          next if placed_dest.include?(dest_block[:name])
          next if template_names.include?(dest_block[:name])
          merged << dest_block
        end

        merged
      end

      def merge_block_headers(tmpl_header, dest_header)
        merged = []
        seen = Set.new

        [tmpl_header, dest_header].each do |header|
          structured_lines(header).each do |line|
            append_structural_line(merged, line, seen)
          end
        end

        return "" if merged.empty?
        merged.join("\n") + "\n"
      end

      def merge_block_statements(tmpl_body, dest_body, dest_result)
        tmpl_stmts = PrismUtils.extract_statements(tmpl_body)
        dest_stmts = PrismUtils.extract_statements(dest_body)

        tmpl_keys = Set.new
        tmpl_key_to_node = {}
        tmpl_stmts.each do |stmt|
          key = statement_key(stmt)
          if key
            tmpl_keys << key
            tmpl_key_to_node[key] = stmt
          end
        end

        dest_keys = Set.new
        dest_stmts.each do |stmt|
          key = statement_key(stmt)
          dest_keys << key if key
        end

        merged = []
        dest_stmts.each_with_index do |dest_stmt, idx|
          dest_key = statement_key(dest_stmt)

          if dest_key && tmpl_keys.include?(dest_key)
            merged << {node: tmpl_key_to_node[dest_key], inline_comments: [], leading_comments: [], shared: true, key: dest_key}
          else
            inline_comments = PrismUtils.inline_comments_for_node(dest_result, dest_stmt)
            prev_stmt = (idx > 0) ? dest_stmts[idx - 1] : nil
            leading_comments = PrismUtils.find_leading_comments(dest_result, dest_stmt, prev_stmt, dest_body)
            merged << {node: dest_stmt, inline_comments: inline_comments, leading_comments: leading_comments, shared: false}
          end
        end

        tmpl_stmts.each do |tmpl_stmt|
          tmpl_key = statement_key(tmpl_stmt)
          unless tmpl_key && dest_keys.include?(tmpl_key)
            merged << {node: tmpl_stmt, inline_comments: [], leading_comments: [], shared: false}
          end
        end

        merged.each do |item|
          item.delete(:shared)
          item.delete(:key)
        end

        merged
      end

      def structured_lines(header)
        header.to_s.each_line.map { |line| line.chomp }
      end

      def append_structural_line(buffer, line, seen)
        return if line.nil?

        if line.strip.empty?
          buffer << "" unless buffer.last&.empty?
        else
          key = line.strip.downcase
          return if seen.include?(key)
          buffer << line
          seen << key
        end
      end

      def statement_key(node)
        PrismUtils.statement_key(node, tracked_methods: TRACKED_METHODS)
      end

      def build_output(preamble_lines, blocks)
        output = []
        output.concat(preamble_lines)

        blocks.each do |block|
          header_lines = structured_lines(block[:header])
          header_lines.each { |line| output << line }

          output << "appraise(\"#{block[:name]}\") {"

          statements = block[:statements] || extract_original_statements(block[:node])
          statements.each do |stmt_info|
            leading = stmt_info[:leading_comments] || []
            leading.each do |comment|
              output << "  #{comment.slice.rstrip}"
            end

            node = stmt_info[:node]
            line = normalize_statement(node)
            line = line.to_s.sub(/\A\s+/, "")

            inline = stmt_info[:inline_comments] || []
            inline_str = inline.map { |c| c.slice.strip }.join(" ")
            output << ["  #{line}", (inline_str.empty? ? nil : inline_str)].compact.join(" ")
          end

          output << "}"
          output << ""
        end

        output.join("\n").gsub(/\n{3,}/, "\n\n").sub(/\n+\z/, "\n")
      end

      def normalize_statement(node)
        return PrismUtils.node_to_source(node) unless node.is_a?(Prism::CallNode)
        PrismUtils.normalize_call_node(node)
      end

      def normalize_argument(arg)
        PrismUtils.normalize_argument(arg)
      end

      def extract_original_statements(node)
        body = node.block&.body
        return [] unless body
        statements = body.is_a?(Prism::StatementsNode) ? body.body : [body]
        statements.compact.map { |stmt| {node: stmt, inline_comments: [], leading_comments: []} }
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
    end
  end
end
