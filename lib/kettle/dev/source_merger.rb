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
        src_content = src.to_s
        dest_content = dest

        has_freeze_blocks = src_content.match?(FREEZE_START) && src_content.match?(FREEZE_END)

        content =
          case strategy
          when :skip
            has_freeze_blocks ? src_content : normalize_source(src_content)
          when :replace
            has_freeze_blocks ? src_content : normalize_source(src_content)
          when :append
            apply_append(src_content, dest_content)
          when :merge
            apply_merge(src_content, dest_content)
          else
            raise Kettle::Dev::Error, "Unknown templating strategy '#{strategy}' for #{path}."
          end
        content = merge_freeze_blocks(content, dest_content)
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


      # Merge kettle-dev:freeze blocks from destination into source content
      # Preserves user customizations wrapped in freeze/unfreeze markers
      #
      # @param src_content [String] Template source content
      # @param dest_content [String] Destination file content
      # @return [String] Merged content with freeze blocks from destination
      # @api private
      def merge_freeze_blocks(src_content, dest_content)
        manifests = freeze_block_manifests(dest_content)
        freeze_debug("manifests=#{manifests.length}")
        manifests.each_with_index { |manifest, idx| freeze_debug("manifest[#{idx}]=#{manifest.inspect}") }
        return src_content if manifests.empty?
        src_blocks = freeze_blocks(src_content)
        updated = src_content.dup
        manifests.each_with_index do |manifest, idx|
          freeze_debug("processing manifest[#{idx}]")
          updated_blocks = freeze_blocks(updated)
          if freeze_block_present?(updated_blocks, manifest)
            freeze_debug("manifest[#{idx}] already present; skipping")
            next
          end
          block_text = manifest[:text]
          placeholder = src_blocks.find do |blk|
            blk[:start_marker] == manifest[:start_marker] &&
              (blk[:before_context] == manifest[:before_context] || blk[:after_context] == manifest[:after_context])
          end
          if placeholder
            freeze_debug("manifest[#{idx}] replacing placeholder at #{placeholder[:range]}")
            updated.sub!(placeholder[:text], block_text)
            next
          end
          insertion_result = insert_freeze_block_by_manifest(updated, manifest)
          if insertion_result
            freeze_debug("manifest[#{idx}] inserted via context")
            updated = insertion_result
          elsif (estimated_index = manifest[:original_index]) && estimated_index <= updated.length
            freeze_debug("manifest[#{idx}] inserted via original_index=#{estimated_index}")
            updated.insert([estimated_index, updated.length].min, ensure_trailing_newline(block_text))
          else
            freeze_debug("manifest[#{idx}] appended to EOF")
            updated = append_freeze_block(updated, block_text)
          end
        end
        enforce_unique_freeze_blocks(updated)
      end

      def freeze_block_present?(blocks, manifest)
        blocks.any? do |blk|
          match = blk[:start_marker] == manifest[:start_marker] &&
            (blk[:before_context] == manifest[:before_context] || blk[:after_context] == manifest[:after_context])
          freeze_debug("checking block start=#{blk[:start_marker]} matches=#{match}")
          return true if match
        end
        false
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
          before_context = freeze_block_context_line(text, start_idx, direction: :before)
          after_context = freeze_block_context_line(text, end_idx, direction: :after)
          blocks << {
            range: start_idx...end_idx,
            text: segment,
            start_marker: start_marker,
            before_context: before_context,
            after_context: after_context,
          }
        end
        freeze_debug("freeze_blocks count=#{blocks.length}")
        blocks.each_with_index do |blk, idx|
          freeze_debug("block[#{idx}] start=#{blk[:start_marker]} before=#{blk[:before_context].inspect} after=#{blk[:after_context].inspect}")
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
        src_result = Kettle::Dev::PrismUtils.parse_with_comments(src_content)
        dest_result = Kettle::Dev::PrismUtils.parse_with_comments(dest_content)

        # If src parsing failed, return src unchanged to avoid losing content
        unless src_result.success?
          puts "WARNING: Source content parse failed, returning unchanged"
          return src_content
        end

        src_nodes = extract_nodes_with_comments(src_result)
        dest_nodes = extract_nodes_with_comments(dest_result)

        merged_nodes = yield(src_nodes, dest_nodes, src_result, dest_result)

        # Extract and deduplicate comments from src and dest SEPARATELY
        # This allows sequence detection to work within each source
        src_tuples = create_comment_tuples(src_result)
        src_deduplicated = deduplicate_comment_sequences(src_tuples)

        dest_tuples = dest_result.success? ? create_comment_tuples(dest_result) : []
        dest_deduplicated = deduplicate_comment_sequences(dest_tuples)

        # Now merge the deduplicated tuples by hash+type only (ignore line numbers)
        seen_hash_type = Set.new
        final_tuples = []

        # Add all deduplicated src tuples
        src_deduplicated.each do |tuple|
          hash_val = tuple[0]
          type = tuple[1]
          key = [hash_val, type]
          unless seen_hash_type.include?(key)
            final_tuples << tuple
            seen_hash_type << key
          end
        end

        # Add deduplicated dest tuples that don't duplicate src (by hash+type)
        dest_deduplicated.each do |tuple|
          hash_val = tuple[0]
          type = tuple[1]
          key = [hash_val, type]
          unless seen_hash_type.include?(key)
            final_tuples << tuple
            seen_hash_type << key
          end
        end

        # Extract magic and file-level comments from final merged tuples
        magic_comments = final_tuples
          .select { |tuple| tuple[1] == :magic }
          .map { |tuple| tuple[2] }

        file_leading_comments = final_tuples
          .select { |tuple| tuple[1] == :file_level }
          .map { |tuple| tuple[2] }

        build_source_from_nodes(merged_nodes, magic_comments: magic_comments, file_leading_comments: file_leading_comments)
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

        # Identify kettle-dev freeze/unfreeze blocks using Prism's magic comment detection
        # Comments within these ranges should be treated as file_level to keep them together
        freeze_block_ranges = find_freeze_block_ranges(parse_result)

        tuples = []

        parse_result.comments.each do |comment|
          comment_line = comment.location.start_line
          comment_text = comment.slice.strip

          # Check if this comment is within a freeze block range
          in_freeze_block = freeze_block_ranges.any? { |range| range.cover?(comment_line) }

          # Determine comment type
          type = if in_freeze_block
            # All comments within freeze blocks are file_level to keep them together
            :file_level
          elsif magic_comment_lines.include?(comment_line)
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

      # Find kettle-dev freeze/unfreeze block line ranges using Prism's magic comment detection
      # Returns an array of ranges representing protected freeze blocks
      # Includes comments immediately before the freeze marker (within consecutive comment lines)
      # @param parse_result [Prism::ParseResult] Parse result with magic comments
      # @return [Array<Range>] Array of line number ranges for freeze blocks
      # @api private
      def find_freeze_block_ranges(parse_result)
        return [] unless parse_result.success?

        kettle_dev_magics = parse_result.magic_comments.select { |mc| mc.key == "kettle-dev" }
        ranges = []

        # Get source lines for checking blank lines
        source_lines = parse_result.source.lines

        # Match freeze/unfreeze pairs
        i = 0
        while i < kettle_dev_magics.length
          magic = kettle_dev_magics[i]
          if magic.value == "freeze"
            # Look for the matching unfreeze
            j = i + 1
            while j < kettle_dev_magics.length
              next_magic = kettle_dev_magics[j]
              if next_magic.value == "unfreeze"
                # Found a matching pair
                freeze_line = magic.key_loc.start_line
                unfreeze_line = next_magic.key_loc.start_line

                # Find the start of the freeze block by looking for contiguous comments before freeze marker
                # Only include comments that are immediately adjacent (no blank lines or code between them)
                start_line = freeze_line


                # Find comments immediately before the freeze marker
                # Work backwards from freeze_line - 1, stopping at first non-comment line
                candidate_line = freeze_line - 1
                while candidate_line >= 1
                  line_content = source_lines[candidate_line - 1]&.strip || ""

                  # Stop if we hit a blank line or non-comment line
                  break if line_content.empty? || !line_content.start_with?("#")

                  # Check if this line is a Ruby magic comment - if so, stop
                  is_ruby_magic = parse_result.magic_comments.any? do |mc|
                    ruby_magic_comment_key?(mc.key) &&
                      mc.key_loc.start_line == candidate_line
                  end
                  break if is_ruby_magic

                  # This is a valid comment in the freeze block header
                  start_line = candidate_line
                  candidate_line -= 1
                end

                # Extend slightly after unfreeze to catch trailing blank comment lines
                end_line = unfreeze_line + 1

                ranges << (start_line..end_line)
                i = j # Skip to after the unfreeze
                break
              end
              j += 1
            end
          end
          i += 1
        end

        ranges
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

      # Generate a signature for a node to determine if two nodes should be considered "the same"
      # during merge operations. The signature is used to:
      # 1. Identify duplicate nodes in append mode (skip adding if already present)
      # 2. Match nodes for replacement in merge mode (replace dest with src when signatures match)
      #
      # Signature strategies by node type:
      # - gem/source calls: Use method name + first argument (e.g., [:send, :gem, "foo"])
      #   This allows merging/replacing gem declarations with same name but different versions
      # - Block calls: Use method name + first argument + full source for non-standard blocks
      #   Special cases: Gem::Specification.new, task, git_source use simpler signatures
      # - Conditionals (if/unless/case): Use predicate/condition only, NOT full source
      #   This prevents duplication when template updates conditional body but keeps same condition
      #   Example: if ENV["FOO"] blocks with different bodies are treated as same statement
      # - Other nodes: Use class name + full source (fallback for unhandled types)
      #
      # @param node [Prism::Node] AST node to generate signature for
      # @return [Array] Signature array used as hash key for node identity
      # @api private
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
        when Prism::IfNode
          # For if/elsif/else nodes, create signature based ONLY on the predicate (condition).
          # This is critical: two if blocks with the same condition but different bodies
          # should be treated as the same statement, allowing the template to update the body.
          # Without this, we get duplicate if blocks when the template differs from destination.
          # Example: Template has 'ENV["HOME"] || Dir.home', dest has 'ENV["HOME"]' ->
          #          both should match and dest body should be replaced, not duplicated.
          predicate_signature = node.predicate&.slice
          [:if, predicate_signature]
        when Prism::UnlessNode
          # Similar logic to IfNode - match by condition only
          predicate_signature = node.predicate&.slice
          [:unless, predicate_signature]
        when Prism::CaseNode
          # For case statements, use the predicate/subject to match
          # Allows template to update case branches while matching on the case expression
          predicate_signature = node.predicate&.slice
          [:case, predicate_signature]
        when Prism::LocalVariableWriteNode
          # Match local variable assignments by variable name, not full source
          # This prevents duplication when assignment bodies differ between template and destination
          [:local_var_write, node.name]
        when Prism::InstanceVariableWriteNode
          # Match instance variable assignments by variable name
          [:instance_var_write, node.name]
        when Prism::ClassVariableWriteNode
          # Match class variable assignments by variable name
          [:class_var_write, node.name]
        when Prism::ConstantWriteNode
          # Match constant assignments by constant name
          [:constant_write, node.name]
        when Prism::GlobalVariableWriteNode
          # Match global variable assignments by variable name
          [:global_var_write, node.name]
        when Prism::ClassNode
          # Match class definitions by name
          class_name = PrismUtils.extract_const_name(node.constant_path)
          [:class, class_name]
        when Prism::ModuleNode
          # Match module definitions by name
          module_name = PrismUtils.extract_const_name(node.constant_path)
          [:module, module_name]
        else
          # Other node types - use full source as last resort
          # This may cause issues with nodes that should match by structure rather than content
          # Future enhancement: add specific handlers for while/until/for loops, class/module defs, etc.
          [node.class.name.split("::").last.to_sym, node.slice]
        end
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

      def append_freeze_block(content, block_text)
        snippet = ensure_trailing_newline(block_text)
        snippet = "\n" + snippet unless content.end_with?("\n")
        content + snippet
      end

      def insert_freeze_block_by_manifest(content, manifest)
        snippet = ensure_trailing_newline(manifest[:text])
        if (before_context = manifest[:before_context])
          index = content.index(before_context)
          if index
            insert_at = index + before_context.length
            return insert_with_spacing(content, insert_at, snippet)
          end
        end
        if (after_context = manifest[:after_context])
          index = content.index(after_context)
          if index
            insert_at = [index - snippet.length, 0].max
            return insert_with_spacing(content, insert_at, snippet)
          end
        end
        nil
      end

      def insert_with_spacing(content, insert_at, snippet)
        buffer = content.dup
        buffer.insert(insert_at, snippet)
      end

      def freeze_block_manifests(text)
        seen = Set.new
        freeze_blocks(text).map do |block|
          next if seen.include?(block[:text])
          seen << block[:text]
          {
            text: block[:text],
            start_marker: block[:start_marker],
            before_context: freeze_block_context_line(text, block[:range].begin, direction: :before),
            after_context: freeze_block_context_line(text, block[:range].end, direction: :after),
            original_index: block[:range].begin,
          }
        end.compact
      end

      def enforce_unique_freeze_blocks(content)
        seen = Set.new
        result = content.dup
        result.to_enum(:scan, FREEZE_BLOCK).each do
          match = Regexp.last_match
          block_text = match[0]
          next unless block_text
          next if seen.add?(block_text)
          range = match.begin(0)...match.end(0)
          result[range] = ""
        end
        result
      end

      def freeze_block_context_line(text, index, direction:)
        lines = text.lines
        return nil if lines.empty?
        line_number = text[0...index].count("\n")
        cursor = direction == :before ? line_number - 1 : line_number
        step = direction == :before ? -1 : 1
        while cursor >= 0 && cursor < lines.length
          raw_line = lines[cursor]
          stripped = raw_line.strip
          cursor += step
          next if stripped.empty?
          # Avoid anchoring to the freeze/unfreeze markers themselves
          next if stripped.match?(FREEZE_START) || stripped.match?(FREEZE_END)
          return raw_line
        end
        nil
      end

      def freeze_debug(message)
        return unless freeze_debug?
        puts("[kettle-dev:freeze] #{message}")
      end

      def freeze_debug?
        ENV["KETTLE_DEV_DEBUG_FREEZE"] == "1"
      end
    end
  end
end
