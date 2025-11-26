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
      # This is a conservative, comment-preserving approach using Prism to detect call nodes.
      def merge_gem_calls(src_content, dest_content)
        src_res = PrismUtils.parse_with_comments(src_content)
        dest_res = PrismUtils.parse_with_comments(dest_content)

        src_stmts = PrismUtils.extract_statements(src_res.value.statements)
        dest_stmts = PrismUtils.extract_statements(dest_res.value.statements)

        # Find source nodes
        src_source_node = src_stmts.find { |n| PrismUtils.call_to?(n, :source) }
        dest_source_node = dest_stmts.find { |n| PrismUtils.call_to?(n, :source) }

        out = dest_content.dup
        dest_lines = out.lines

        # Replace or insert source line
        if src_source_node
          src_src = src_source_node.slice
          if dest_source_node
            out = out.sub(dest_source_node.slice, src_src)
            dest_lines = out.lines
          else
            # insert after any leading comment/blank block
            insert_idx = 0
            while insert_idx < dest_lines.length && (dest_lines[insert_idx].strip.empty? || dest_lines[insert_idx].lstrip.start_with?("#"))
              insert_idx += 1
            end
            dest_lines.insert(insert_idx, src_src.rstrip + "\n")
            out = dest_lines.join
            dest_lines = out.lines
          end
        end

        # --- Handle git_source replacement/insertion ---
        src_git_nodes = src_stmts.select { |n| PrismUtils.call_to?(n, :git_source) }
        if src_git_nodes.any?
          # We'll operate on dest_lines for insertion; recompute dest_stmts if we changed out
          dest_res = PrismUtils.parse_with_comments(out)
          dest_stmts = PrismUtils.extract_statements(dest_res.value.statements)

          # Iterate in reverse when inserting so that inserting at the same index
          # preserves the original order from the source (we insert at a fixed index).
          src_git_nodes.reverse_each do |gnode|
            key = PrismUtils.statement_key(gnode) # => [:git_source, name]
            name = key && key[1]
            replaced = false

            if name
              dest_same_idx = dest_stmts.index { |d| PrismUtils.statement_key(d) && PrismUtils.statement_key(d)[0] == :git_source && PrismUtils.statement_key(d)[1] == name }
              if dest_same_idx
                # Replace the matching dest node slice
                out = out.sub(dest_stmts[dest_same_idx].slice, gnode.slice)
                replaced = true
              end
            end

            # If not replaced, prefer to replace an existing github entry in destination
            # (this mirrors previous behavior in template_helpers which favored replacing
            # a github git_source when inserting others).
            unless replaced
              dest_github_idx = dest_stmts.index { |d| PrismUtils.statement_key(d) && PrismUtils.statement_key(d)[0] == :git_source && PrismUtils.statement_key(d)[1] == 'github' }
              if dest_github_idx
                out = out.sub(dest_stmts[dest_github_idx].slice, gnode.slice)
                replaced = true
              end
            end

            unless replaced
               # Insert below source line if present, else at top after comments
               dest_lines = out.lines
               insert_idx = dest_lines.index { |ln| !ln.strip.start_with?("#") && ln =~ /^\s*source\s+/ } || 0
               insert_idx = insert_idx + 1 if insert_idx
               dest_lines.insert(insert_idx, gnode.slice.rstrip + "\n")
               out = dest_lines.join
             end

             # Recompute dest_stmts for subsequent iterations
             dest_res = PrismUtils.parse_with_comments(out)
             dest_stmts = PrismUtils.extract_statements(dest_res.value.statements)
           end
         end

        # Collect gem names present in dest (top-level only)
        dest_res = PrismUtils.parse_with_comments(out)
        dest_stmts = PrismUtils.extract_statements(dest_res.value.statements)
        dest_gem_names = dest_stmts.map { |n| PrismUtils.statement_key(n) }.compact.select { |k| k[0] == :gem }.map { |k| k[1] }.to_set

        # Find gem call nodes in src and append missing ones (top-level only)
        missing_nodes = src_stmts.select do |n|
          k = PrismUtils.statement_key(n)
          k && k.first == :gem && !dest_gem_names.include?(k[1])
        end
        if missing_nodes.any?
          out << "\n" unless out.end_with?("\n") || out.empty?
          missing_nodes.each do |n|
            # Preserve inline comments for the source node when appending
            inline = PrismUtils.inline_comments_for_node(src_res, n) rescue []
            line = n.slice.rstrip
            if inline && inline.any?
              inline_text = inline.map { |c| c.slice.strip }.join(" ")
              # Only append the inline text if it's not already part of the slice
              line = line + " " + inline_text unless line.include?(inline_text)
            end
            out << line + "\n"
          end
        end

        out
      rescue StandardError => e
        # Use debug_log if available, otherwise Kettle::Dev.debug_error
        if defined?(Kettle::Dev) && Kettle::Dev.respond_to?(:debug_error)
          Kettle::Dev.debug_error(e, __method__)
        else
          Kernel.warn("[#{__method__}] #{e.class}: #{e.message}")
        end
        dest_content
      end
    end
  end
end
