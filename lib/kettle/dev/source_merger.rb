# frozen_string_literal: true

require "yaml"
require "set"

module Kettle
  module Dev
    # Prism-based AST merging for templated Ruby files.
    # Handles strategy dispatch (skip/replace/append/merge).
    #
    # Uses Prism for parsing with first-class comment support, enabling
    # preservation of inline and leading comments throughout the merge process.
    # Freeze blocks are handled natively by prism-merge.
    module SourceMerger
      BUG_URL = "https://github.com/kettle-rb/kettle-dev/issues"

      RUBY_MAGIC_COMMENT_KEYS = %w[frozen_string_literal encoding coding].freeze
      MAGIC_COMMENT_REGEXES = [
        /#\s*frozen_string_literal:/,
        /#\s*encoding:/,
        /#\s*coding:/,
        /#.*-\*-.+coding:.+-\*-/,
      ].freeze

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

        content =
          case strategy
          when :skip
            # For skip, if no destination just normalize the source
            if dest_content.empty?
              normalize_source(src_content)
            else
              # If destination exists, merge to preserve freeze blocks
              # Trust prism-merge's output without additional normalization
              result = apply_merge(src_content, dest_content)
              return ensure_trailing_newline(result)
            end
          when :replace
            # For replace, always use merge (even with empty dest) to ensure consistent behavior
            # Trust prism-merge's output without additional normalization
            result = apply_merge(src_content, dest_content)
            return ensure_trailing_newline(result)
          when :append
            # Prism::Merge handles freeze blocks automatically
            # Trust prism-merge's output without additional normalization
            result = apply_append(src_content, dest_content)
            return ensure_trailing_newline(result)
          when :merge
            # Prism::Merge handles freeze blocks automatically
            # Trust prism-merge's output without additional normalization
            result = apply_merge(src_content, dest_content)
            return ensure_trailing_newline(result)
          else
            raise Kettle::Dev::Error, "Unknown templating strategy '#{strategy}' for #{path}."
          end
        
        content = normalize_newlines(content)
        ensure_trailing_newline(content)
      rescue StandardError => error
        warn_bug(path, error)
        raise Kettle::Dev::Error, "Template merge failed for #{path}: #{error.message}"
      end

      # Normalize source code by parsing and rebuilding to deduplicate comments
      #
      # @param source [String] Ruby source code
      # @return [String] Normalized source with trailing newline and deduplicated comments
      # @api private
      def normalize_source(source)
        parse_result = PrismUtils.parse_with_comments(source)
        return ensure_trailing_newline(source) unless parse_result.success?

        # Extract and deduplicate comments
        magic_comments = extract_magic_comments(parse_result)
        file_leading_comments = extract_file_leading_comments(parse_result)
        node_infos = extract_nodes_with_comments(parse_result)

        # Rebuild source with deduplicated comments
        build_source_from_nodes(node_infos, magic_comments: magic_comments, file_leading_comments: file_leading_comments)
      end

      def shebang?(line)
        line.start_with?("#!")
      end

      def magic_comment?(line)
        return false unless line
        MAGIC_COMMENT_REGEXES.any? { |regex| line.match?(regex) }
      end

      def ruby_magic_comment_key?(key)
        RUBY_MAGIC_COMMENT_KEYS.include?(key)
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

      # Normalize newlines in the content according to templating rules:
      # 1. Magic comments followed by single blank line
      # 2. No more than single blank line anywhere
      # 3. Single blank line at end of file (handled by ensure_trailing_newline)
      #
      # @param content [String] Ruby source content
      # @return [String] Content with normalized newlines
      # @api private
      def normalize_newlines(content)
        return content if content.nil? || content.empty?

        lines = content.lines(chomp: true)
        result = []
        i = 0

        # Process magic comments (shebang and various Ruby magic comments)
        while i < lines.length && (shebang?(lines[i] + "\n") || magic_comment?(lines[i] + "\n"))
          result << lines[i]
          i += 1
        end

        # Ensure single blank line after magic comments if there are any and more content follows
        if result.any? && i < lines.length
          result << ""
          # Skip any existing blank lines
          i += 1 while i < lines.length && lines[i].strip.empty?
        end

        # Process remaining lines, collapsing multiple blank lines to single
        prev_blank = false
        while i < lines.length
          line = lines[i]
          is_blank = line.strip.empty?

          if is_blank
            # Only add blank line if previous wasn't blank
            unless prev_blank
              result << ""
              prev_blank = true
            end
          else
            result << line
            prev_blank = false
          end

          i += 1
        end

        # Remove trailing blank lines (ensure_trailing_newline will add exactly one newline)
        result.pop while result.any? && result.last.strip.empty?

        result.join("\n") + "\n"
      end

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
          freeze_token: "kettle-dev"
        )
        merger.merge
      rescue Prism::Merge::Error => e
        puts "WARNING: Prism::Merge failed for append strategy: #{e.message}"
        src_content
      end

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
          freeze_token: "kettle-dev"
        )
        merger.merge
      rescue Prism::Merge::Error => e
        puts "WARNING: Prism::Merge failed for merge strategy: #{e.message}"
        src_content
      end

      # Create a signature generator that handles various Ruby node types
      # This ensures proper matching during merge/append operations
      def create_signature_generator
        ->(node) do
          case node
          when Prism::CallNode
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

            # For non-assignment methods, include the first argument for matching
            # e.g. spec.add_dependency("gem_name", "~> 1.0") -> [:add_dependency, "gem_name"]
            first_arg = node.arguments&.arguments&.first
            arg_value = case first_arg
                        when Prism::StringNode
                          first_arg.unescaped.to_s
                        when Prism::SymbolNode
                          first_arg.unescaped.to_sym
                        else
                          nil
                        end

            arg_value ? [node.name, arg_value] : [:call, node.name, receiver_name]

          when Prism::IfNode
            # Match if statements by their predicate
            predicate_source = node.predicate.slice.strip
            [:if, predicate_source]

          when Prism::UnlessNode
            # Match unless statements by their predicate
            predicate_source = node.predicate.slice.strip
            [:unless, predicate_source]

          when Prism::CaseNode
            # Match case statements by their predicate
            predicate_source = node.predicate ? node.predicate.slice.strip : nil
            [:case, predicate_source]

          when Prism::LocalVariableWriteNode
            # Match local variable assignments by variable name
            [:local_var, node.name]

          when Prism::ConstantWriteNode
            # Match constant assignments by constant name
            [:constant, node.name]

          when Prism::ConstantPathWriteNode
            # Match constant path assignments (like Foo::Bar = ...)
            [:constant_path, node.target.slice]

          else
            # For other node types, use a generic signature based on node type
            # This allows matching of similar structures
            [node.class.name.split("::").last.to_sym, node.slice.strip[0..50]]
          end
        end
      end

      def extract_magic_comments(parse_result)
        return [] unless parse_result.success?

        tuples = create_comment_tuples(parse_result)
        deduplicated = deduplicate_comment_sequences(tuples)

        # Filter to only magic comments and return their text
        deduplicated
          .select { |tuple| tuple[1] == :magic }
          .map { |tuple| tuple[2] }
      end

      def extract_file_leading_comments(parse_result)
        return [] unless parse_result.success?

        tuples = create_comment_tuples(parse_result)
        deduplicated = deduplicate_comment_sequences(tuples)

        # Filter to only file-level comments and return their text
        deduplicated
          .select { |tuple| tuple[1] == :file_level }
          .map { |tuple| tuple[2] }
      end

      # Create a tuple for each comment: [hash, type, text, line_number]
      # where type is one of: :magic, :file_level, :leading
      # (inline comments are handled with their associated statements)
      def create_comment_tuples(parse_result)
        return [] unless parse_result.success?

        statements = PrismUtils.extract_statements(parse_result.value.statements)
        first_stmt_line = statements.any? ? statements.first.location.start_line : Float::INFINITY

        # Build set of magic comment line numbers from Prism's magic_comments
        # Filter to only actual Ruby magic comments (not kettle-dev directives)
        magic_comment_lines = Set.new
        parse_result.magic_comments.each do |magic_comment|
          key = magic_comment.key
          if ruby_magic_comment_key?(key)
            magic_comment_lines << magic_comment.key_loc.start_line
          end
        end

        tuples = []

        parse_result.comments.each do |comment|
          comment_line = comment.location.start_line
          comment_text = comment.slice.strip

          # Determine comment type
          type = if magic_comment_lines.include?(comment_line)
            :magic
          elsif comment_line < first_stmt_line
            :file_level
          else
            # This will be handled as a leading or inline comment for a statement
            :leading
          end

          # Create hash from normalized comment text (ignoring trailing whitespace)
          comment_hash = comment_text.hash

          tuples << [comment_hash, type, comment.slice.rstrip, comment_line]
        end

        tuples
      end

      # Two-pass deduplication:
      # Pass 1: Deduplicate multi-line sequences
      # Pass 2: Deduplicate single-line duplicates
      def deduplicate_comment_sequences(tuples)
        return [] if tuples.empty?

        # Group tuples by type
        by_type = tuples.group_by { |tuple| tuple[1] }

        result = []

        [:magic, :file_level, :leading].each do |type|
          type_tuples = by_type[type] || []
          next if type_tuples.empty?

          # Pass 1: Remove duplicate sequences
          after_pass1 = deduplicate_sequences_pass1(type_tuples)

          # Pass 2: Remove single-line duplicates
          after_pass2 = deduplicate_singles_pass2(after_pass1)

          result.concat(after_pass2)
        end

        result
      end

      # Pass 1: Find and remove duplicate multi-line comment sequences
      # A sequence is defined by consecutive comments (ignoring blank lines in between)
      def deduplicate_sequences_pass1(tuples)
        return tuples if tuples.length <= 1

        # Group tuples into sequences (consecutive comments, allowing gaps for blank lines)
        sequences = []
        current_seq = []
        prev_line = nil

        tuples.each do |tuple|
          line_num = tuple[3]

          # If this is consecutive with previous (allowing reasonable gaps for blank lines)
          if prev_line.nil? || (line_num - prev_line) <= 3
            current_seq << tuple
          else
            # Start new sequence
            sequences << current_seq if current_seq.any?
            current_seq = [tuple]
          end

          prev_line = line_num
        end
        sequences << current_seq if current_seq.any?

        # Find duplicate sequences by comparing hash signatures
        seen_seq_signatures = Set.new
        unique_tuples = []

        sequences.each do |seq|
          # Create signature from hashes and sequence length
          seq_signature = seq.map { |t| t[0] }.join(",")

          unless seen_seq_signatures.include?(seq_signature)
            seen_seq_signatures << seq_signature
            unique_tuples.concat(seq)
          end
        end

        unique_tuples
      end

      # Pass 2: Remove single-line duplicates from already sequence-deduplicated tuples
      def deduplicate_singles_pass2(tuples)
        return tuples if tuples.length <= 1

        seen_hashes = Set.new
        unique_tuples = []

        tuples.each do |tuple|
          comment_hash = tuple[0]

          unless seen_hashes.include?(comment_hash)
            seen_hashes << comment_hash
            unique_tuples << tuple
          end
        end

        unique_tuples
      end

      def extract_file_leading_comments(parse_result)
        return [] unless parse_result.success?

        tuples = create_comment_tuples(parse_result)
        deduplicated = deduplicate_comment_sequences(tuples)

        # Filter to only file-level comments and return their text
        deduplicated
          .select { |tuple| tuple[1] == :file_level }
          .map { |tuple| tuple[2] }
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

      def extract_magic_comments(parse_result)
        return [] unless parse_result.success?

        tuples = create_comment_tuples(parse_result)
        deduplicated = deduplicate_comment_sequences(tuples)

        # Filter to only magic comments and return their text
        deduplicated
          .select { |tuple| tuple[1] == :magic }
          .map { |tuple| tuple[2] }
      end

      def extract_file_leading_comments(parse_result)
        return [] unless parse_result.success?

        tuples = create_comment_tuples(parse_result)
        deduplicated = deduplicate_comment_sequences(tuples)

        # Filter to only file-level comments and return their text
        deduplicated
          .select { |tuple| tuple[1] == :file_level }
          .map { |tuple| tuple[2] }
      end

      def build_source_from_nodes(node_infos, magic_comments: [], file_leading_comments: [])
        lines = []

        # Add magic comments at the top (frozen_string_literal, etc.)
        if magic_comments.any?
          lines.concat(magic_comments)
          lines << "" # Add blank line after magic comments
        end

        # Add file-level leading comments (comments before first statement)
        if file_leading_comments.any?
          lines.concat(file_leading_comments)
          # Only add blank line if there are statements following
          lines << "" if node_infos.any?
        end

        # If there are no statements and no comments, return empty string
        return "" if node_infos.empty? && lines.empty?

        # If there are only comments and no statements, return the comments
        return lines.join("\n") if node_infos.empty?

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

      def restore_custom_leading_comments(dest_content, merged_content)
        # Extract and deduplicate leading comments from dest
        dest_block = leading_comment_block(dest_content)
        return merged_content if dest_block.strip.empty?

        # Parse and deduplicate the dest leading comments
        dest_deduplicated = deduplicate_leading_comment_block(dest_block)
        return merged_content if dest_deduplicated.strip.empty?

        # Get the merged content's leading comments
        merged_leading = leading_comment_block(merged_content)

        # Parse both blocks to compare individual comments
        dest_comments = extract_comment_lines(dest_deduplicated)
        merged_comments = extract_comment_lines(merged_leading)

        # Find comments in dest that aren't in merged (by normalized text)
        merged_set = Set.new(merged_comments.map { |c| normalize_comment(c) })
        unique_dest_comments = dest_comments.reject { |c| merged_set.include?(normalize_comment(c)) }

        return merged_content if unique_dest_comments.empty?

        # Add unique dest comments after the insertion point
        insertion_index = reminder_insertion_index(merged_content)
        new_comments = unique_dest_comments.join + "\n"
        merged_content.dup.insert(insertion_index, new_comments)
      end

      def deduplicate_leading_comment_block(block)
        # Parse the block as if it were a Ruby file with just comments
        # This allows us to use the same deduplication logic
        parse_result = PrismUtils.parse_with_comments(block)
        return block unless parse_result.success?

        tuples = create_comment_tuples(parse_result)
        deduplicated_tuples = deduplicate_comment_sequences(tuples)

        # Rebuild the comment block from deduplicated tuples
        deduplicated_tuples.map { |tuple| tuple[2] + "\n" }.join
      end

      def extract_comment_lines(block)
        lines = block.to_s.lines
        lines.select { |line| line.strip.start_with?("#") }
      end

      def normalize_comment(comment)
        # Normalize by removing trailing whitespace and standardizing spacing
        comment.strip
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
