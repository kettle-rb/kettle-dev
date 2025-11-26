# frozen_string_literal: true

require "yaml"
require "set"
require "prism"

module Kettle
  module Dev
    # Prism-based AST merging for templated Ruby files.
    # Handles universal freeze reminders, kettle-dev:freeze blocks, and
    # strategy dispatch (skip/replace/append/merge).
    #
    # Uses Prism for parsing with first-class comment support, enabling
    # preservation of inline and leading comments throughout the merge process.
    module SourceMerger
      FREEZE_START = /#\s*kettle-dev:freeze/i
      FREEZE_END = /#\s*kettle-dev:unfreeze/i
      FREEZE_BLOCK = Regexp.new("(#{FREEZE_START.source}).*?(#{FREEZE_END.source})", Regexp::IGNORECASE | Regexp::MULTILINE)
      FREEZE_REMINDER = <<~RUBY
        # To retain during kettle-dev templating:
        #     kettle-dev:freeze
        #     # ... your code
        #     kettle-dev:unfreeze
      RUBY
      BUG_URL = "https://github.com/kettle-rb/kettle-dev/issues"

      module_function

      # Apply a templating strategy to merge source and destination Ruby files
      #
      # @param strategy [Symbol] Merge strategy - :skip, :replace, :append, or :merge
      # @param src [String] Template source content
      # @param dest [String] Destination file content
      # @param path [String] File path (for error messages)
      # @return [String] Merged content with freeze blocks and comments preserved
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
        src_with_reminder = ensure_reminder(src)
        content =
          case strategy
          when :skip
            src_with_reminder
          when :replace
            normalize_source(src_with_reminder)
          when :append
            apply_append(src_with_reminder, dest)
          when :merge
            apply_merge(src_with_reminder, dest)
          else
            raise Kettle::Dev::Error, "Unknown templating strategy '#{strategy}' for #{path}."
          end
        content = merge_freeze_blocks(content, dest)
        content = restore_custom_leading_comments(dest, content)
        ensure_trailing_newline(content)
      rescue StandardError => error
        warn_bug(path, error)
        raise Kettle::Dev::Error, "Template merge failed for #{path}: #{error.message}"
      end

      # Ensure freeze reminder comment is present at the top of content
      #
      # @param content [String] Ruby source content
      # @return [String] Content with freeze reminder prepended if missing
      # @api private
      def ensure_reminder(content)
        return content if reminder_present?(content)
        insertion_index = reminder_insertion_index(content)
        before = content[0...insertion_index]
        after = content[insertion_index..-1]
        snippet = FREEZE_REMINDER
        snippet += "\n" unless snippet.end_with?("\n\n")
        [before, snippet, after].join
      end

      # Normalize source code while preserving formatting
      #
      # @param source [String] Ruby source code
      # @return [String] Normalized source with trailing newline
      # @api private
      def normalize_source(source)
        parse_result = PrismUtils.parse_with_comments(source)
        return ensure_trailing_newline(source) unless parse_result.success?

        # Use Prism's slice to preserve original formatting
        ensure_trailing_newline(source)
      end

      def reminder_present?(content)
        content.include?(FREEZE_REMINDER.lines.first.strip)
      end

      def reminder_insertion_index(content)
        cursor = 0
        lines = content.lines
        lines.each do |line|
          break unless shebang?(line) || frozen_comment?(line)
          cursor += line.length
        end
        cursor
      end

      def shebang?(line)
        line.start_with?("#!")
      end

      def frozen_comment?(line)
        line.match?(/#\s*frozen_string_literal:/)
      end

      # Merge kettle-dev:freeze blocks from destination into source content
      # Preserves user customizations wrapped in freeze/unfreeze markers
      #
      # @param src_content [String] Template source content
      # @param dest_content [String] Destination file content
      # @return [String] Merged content with freeze blocks from destination
      # @api private
      def merge_freeze_blocks(src_content, dest_content)
        dest_blocks = freeze_blocks(dest_content)
        return src_content if dest_blocks.empty?
        src_blocks = freeze_blocks(src_content)
        updated = src_content.dup
        # Replace matching freeze sections by textual markers rather than index ranges
        dest_blocks.each do |dest_block|
          marker = dest_block[:text]
          next if updated.include?(marker)
          # If the template had a placeholder block, replace the first occurrence of a freeze stub
          placeholder = src_blocks.find { |blk| blk[:start_marker] == dest_block[:start_marker] }
          if placeholder
            updated.sub!(placeholder[:text], marker)
          else
            updated << "\n" unless updated.end_with?("\n")
            updated << marker
          end
        end
        updated
      end

      def freeze_blocks(text)
        return [] unless text&.match?(FREEZE_START)
        blocks = []
        text.to_enum(:scan, FREEZE_BLOCK).each do
          match = Regexp.last_match
          start_idx = match&.begin(0)
          end_idx = match&.end(0)
          next unless start_idx && end_idx
          segment = match[0]
          start_marker = segment.lines.first&.strip
          blocks << {range: start_idx...end_idx, text: segment, start_marker: start_marker}
        end
        blocks
      end

      def normalize_strategy(strategy)
        return :skip if strategy.nil?
        strategy.to_s.downcase.strip.to_sym
      end

      def warn_bug(path, error)
        puts "ERROR: kettle-dev templating failed for #{path}: #{error.message}"
        puts "Please file a bug at #{BUG_URL} with the file contents so we can improve the AST merger."
      end

      def ensure_trailing_newline(text)
        return "" if text.nil?
        text.end_with?("\n") ? text : text + "\n"
      end

      def apply_append(src_content, dest_content)
        prism_merge(src_content, dest_content) do |src_nodes, dest_nodes, _src_result, _dest_result|
          existing = Set.new(dest_nodes.map { |node| node_signature(node[:node]) })
          appended = dest_nodes.dup
          src_nodes.each do |node_info|
            sig = node_signature(node_info[:node])
            next if existing.include?(sig)
            appended << node_info
            existing << sig
          end
          appended
        end
      end

      def apply_merge(src_content, dest_content)
        prism_merge(src_content, dest_content) do |src_nodes, dest_nodes, _src_result, _dest_result|
          src_map = src_nodes.each_with_object({}) do |node_info, memo|
            sig = node_signature(node_info[:node])
            memo[sig] ||= node_info
          end
          merged = dest_nodes.map do |node_info|
            sig = node_signature(node_info[:node])
            if (src_node_info = src_map[sig])
              merge_node_info(sig, node_info, src_node_info)
            else
              node_info
            end
          end
          existing = merged.map { |ni| node_signature(ni[:node]) }.to_set
          src_nodes.each do |node_info|
            sig = node_signature(node_info[:node])
            next if existing.include?(sig)
            merged << node_info
            existing << sig
          end
          merged
        end
      end

      def merge_node_info(signature, _dest_node_info, src_node_info)
        return src_node_info unless signature.is_a?(Array)
        case signature[1]
        when :gem_specification
          merge_block_node_info(src_node_info)
        else
          src_node_info
        end
      end

      def merge_block_node_info(src_node_info)
        # For block merging, we need to merge the statements within the block
        # This is complex - for now, prefer template version
        # TODO: Implement deep block statement merging with comment preservation
        src_node_info
      end

      def prism_merge(src_content, dest_content)
        src_result = PrismUtils.parse_with_comments(src_content)
        dest_result = PrismUtils.parse_with_comments(dest_content)

        # If src parsing failed, return src unchanged to avoid losing content
        unless src_result.success?
          puts "WARNING: Source content parse failed, returning unchanged"
          return src_content
        end

        src_nodes = extract_nodes_with_comments(src_result)
        dest_nodes = extract_nodes_with_comments(dest_result)


        merged_nodes = yield(src_nodes, dest_nodes, src_result, dest_result)

        # Extract magic comments from source (frozen_string_literal, etc.)
        magic_comments = extract_magic_comments(src_result)

        # Extract file-level leading comments (comments before first statement)
        file_leading_comments = extract_file_leading_comments(src_result)

        build_source_from_nodes(merged_nodes, magic_comments: magic_comments, file_leading_comments: file_leading_comments)
      end

      def extract_magic_comments(parse_result)
        return [] unless parse_result.success?

        magic_comments = []
        source_lines = parse_result.source.lines

        # Magic comments appear at the very top of the file (possibly after shebang)
        # They must be on the first or second line
        source_lines.first(2).each do |line|
          stripped = line.strip
          # Check for shebang
          if stripped.start_with?("#!")
            magic_comments << line.rstrip
          # Check for magic comments like frozen_string_literal, encoding, etc.
          elsif stripped.start_with?("#") &&
                (stripped.include?("frozen_string_literal:") ||
                 stripped.include?("encoding:") ||
                 stripped.include?("warn_indent:") ||
                 stripped.include?("shareable_constant_value:"))
            magic_comments << line.rstrip
          end
        end

        magic_comments
      end

      def extract_file_leading_comments(parse_result)
        return [] unless parse_result.success?

        statements = PrismUtils.extract_statements(parse_result.value.statements)
        return [] if statements.empty?

        first_stmt = statements.first
        first_stmt_line = first_stmt.location.start_line

        # Extract file-level comments that appear after magic comments (line 1-2)
        # but before the first executable statement. These are typically documentation
        # comments describing the file's purpose.
        parse_result.comments.select do |comment|
          comment.location.start_line > 2 &&
            comment.location.start_line < first_stmt_line
        end.map { |comment| comment.slice.rstrip }
      end

      def extract_nodes_with_comments(parse_result)
        return [] unless parse_result.success?

        statements = PrismUtils.extract_statements(parse_result.value.statements)
        return [] if statements.empty?

        source_lines = parse_result.source.lines

        statements.map.with_index do |stmt, idx|
          prev_stmt = (idx > 0) ? statements[idx - 1] : nil
          body_node = parse_result.value.statements

          # Count blank lines before this statement
          blank_lines_before = count_blank_lines_before(source_lines, stmt, prev_stmt, body_node)

          {
            node: stmt,
            leading_comments: PrismUtils.find_leading_comments(parse_result, stmt, prev_stmt, body_node),
            inline_comments: PrismUtils.inline_comments_for_node(parse_result, stmt),
            blank_lines_before: blank_lines_before,
          }
        end
      end

      def count_blank_lines_before(source_lines, current_stmt, prev_stmt, body_node)
        # Determine the starting line to search from
        start_line = if prev_stmt
          prev_stmt.location.end_line
        else
          # For the first statement, start from the beginning of the body
          body_node.location.start_line
        end

        end_line = current_stmt.location.start_line

        # Count consecutive blank lines before the current statement
        # (after any comments and the previous statement)
        blank_count = 0
        (start_line...end_line).each do |line_num|
          line_idx = line_num - 1
          next if line_idx < 0 || line_idx >= source_lines.length

          line = source_lines[line_idx]
          # Skip comment lines (they're handled separately)
          next if line.strip.start_with?("#")

          # Count blank lines
          if line.strip.empty?
            blank_count += 1
          else
            # Reset count if we hit a non-blank, non-comment line
            # This ensures we only count consecutive blank lines immediately before the statement
            blank_count = 0
          end
        end

        blank_count
      end

      def build_source_from_nodes(node_infos, magic_comments: [], file_leading_comments: [])
        return "" if node_infos.empty?

        lines = []

        # Add magic comments at the top (frozen_string_literal, etc.)
        if magic_comments.any?
          lines.concat(magic_comments)
          lines << "" # Add blank line after magic comments
        end

        # Add file-level leading comments (comments before first statement)
        if file_leading_comments.any?
          lines.concat(file_leading_comments)
          lines << "" # Add blank line after file-level comments
        end

        node_infos.each do |node_info|
          # Add blank lines before this statement (for visual grouping)
          blank_lines = node_info[:blank_lines_before] || 0
          blank_lines.times { lines << "" }

          # Add leading comments
          node_info[:leading_comments].each do |comment|
            lines << comment.slice.rstrip
          end

          # Add the node's source
          node_source = PrismUtils.node_to_source(node_info[:node])

          # Add inline comments on the same line
          if node_info[:inline_comments].any?
            inline = node_info[:inline_comments].map { |c| c.slice.strip }.join(" ")
            node_source = node_source.rstrip + " " + inline
          end

          lines << node_source
        end

        lines.join("\n")
      end

      def node_signature(node)
        return [:nil] unless node

        case node
        when Prism::CallNode
          method_name = node.name
          if node.block
            # Block call
            first_arg = PrismUtils.extract_literal_value(node.arguments&.arguments&.first)
            receiver_name = PrismUtils.extract_const_name(node.receiver)

            if receiver_name == "Gem::Specification" && method_name == :new
              [:block, :gem_specification]
            elsif method_name == :task
              [:block, :task, first_arg]
            elsif method_name == :git_source
              [:block, :git_source, first_arg]
            else
              [:block, method_name, first_arg, node.slice]
            end
          elsif [:source, :git_source, :gem, :eval_gemfile].include?(method_name)
            # Simple call
            first_literal = PrismUtils.extract_literal_value(node.arguments&.arguments&.first)
            [:send, method_name, first_literal]
          else
            [:send, method_name, node.slice]
          end
        else
          # Other node types
          [node.class.name.split("::").last.to_sym, node.slice]
        end
      end

      def restore_custom_leading_comments(dest_content, merged_content)
        block = leading_comment_block(dest_content)
        return merged_content if block.strip.empty?
        return merged_content if merged_content.start_with?(block)

        # Insert after shebang / frozen string literal comments (same place reminder goes)
        insertion_index = reminder_insertion_index(merged_content)
        block = ensure_trailing_newline(block)
        merged_content.dup.insert(insertion_index, block)
      end

      def leading_comment_block(content)
        lines = content.to_s.lines
        collected = []
        lines.each do |line|
          stripped = line.strip
          break unless stripped.empty? || stripped.start_with?("#")
          collected << line
        end
        collected.join
      end
    end
  end
end
