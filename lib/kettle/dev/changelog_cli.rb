# frozen_string_literal: true

module Kettle
  module Dev
    class ChangelogCLI
      UNRELEASED_SECTION_HEADING = "[Unreleased]:"
      def initialize
        @root = Kettle::Dev::CIHelpers.project_root
        @changelog_path = File.join(@root, "CHANGELOG.md")
        @coverage_path = File.join(@root, "coverage", "coverage.json")
      end

      def run
        version = Kettle::Dev::Versioning.detect_version(@root)
        today = Time.now.strftime("%Y-%m-%d")
        owner, repo = Kettle::Dev::CIHelpers.repo_info
        unless owner && repo
          warn("Could not determine GitHub owner/repo from origin remote.")
          warn("Make sure 'origin' points to github.com. Alternatively, set origin or update links manually afterward.")
        end

        line_cov_line, branch_cov_line = coverage_lines
        yard_line = yard_percent_documented

        changelog = File.read(@changelog_path)

        # If the detected version already exists in the changelog, abort to avoid duplicates
        if changelog =~ /^## \[#{Regexp.escape(version)}\]/
          abort("CHANGELOG.md already has a section for version #{version}. Bump version.rb or remove the duplicate.")
        end

        unreleased_block, before, after = extract_unreleased(changelog)
        if unreleased_block.nil?
          abort("Could not find '## [Unreleased]' section in CHANGELOG.md")
        end

        if unreleased_block.strip.empty?
          warn("No entries found under Unreleased. Creating an empty version section anyway.")
        end

        prev_version = detect_previous_version(after)

        new_section = +""
        new_section << "## [#{version}] - #{today}\n"
        new_section << "- TAG: [v#{version}][#{version}t]\n"
        new_section << "- #{line_cov_line}\n" if line_cov_line
        new_section << "- #{branch_cov_line}\n" if branch_cov_line
        new_section << "- #{yard_line}\n" if yard_line
        new_section << filter_unreleased_sections(unreleased_block)
        # Ensure exactly one blank line separates this new section from the next section
        new_section.rstrip!
        new_section << "\n\n"

        # Reset the Unreleased section to empty category headings
        unreleased_reset = <<~MD
          ## [Unreleased]
          ### Added
          ### Changed
          ### Deprecated
          ### Removed
          ### Fixed
          ### Security
        MD

        # Preserve everything from the first released section down to the line containing the [Unreleased] link ref.
        # Many real-world changelogs intersperse stray link refs between sections; we should keep them.
        updated = before + unreleased_reset + "\n" + new_section
        # Find the [Unreleased]: link-ref line and append everything from the start of the first released section
        # through to the end of the file, but if a [Unreleased]: ref exists, ensure we do not duplicate the
        # section content above it.
        if after && !after.empty?
          # Split 'after' by lines so we can locate the first link-ref to Unreleased
          after_lines = after.lines
          unreleased_ref_idx = after_lines.index { |l| l.start_with?(UNRELEASED_SECTION_HEADING) }
          if unreleased_ref_idx
            # Keep all content prior to the link-ref (older releases and interspersed refs)
            preserved_body = after_lines[0...unreleased_ref_idx].join
            # Then append the tail starting from the Unreleased link-ref line to preserve the footer refs
            preserved_footer = after_lines[unreleased_ref_idx..-1].join
            updated << preserved_body << preserved_footer
          else
            # No Unreleased ref found; just append the remainder as-is
            updated << after
          end
        end

        updated = update_link_refs(updated, owner, repo, prev_version, version)

        # Ensure exactly one trailing newline at EOF
        updated = updated.rstrip + "\n"

        File.write(@changelog_path, updated)
        puts "CHANGELOG.md updated with v#{version} section."
      end

      private

      def abort(msg)
        Kettle::Dev::ExitAdapter.abort(msg)
      end

      def detect_version
        candidates = Dir[File.join(@root, "lib", "**", "version.rb")]
        abort("Could not find version.rb under lib/**.") if candidates.empty?
        versions = candidates.map do |path|
          content = File.read(path)
          m = content.match(/VERSION\s*=\s*(["'])([^"']+)\1/)
          next unless m
          m[2]
        end.compact
        abort("VERSION constant not found in #{@root}/lib/**/version.rb") if versions.none?
        abort("Multiple VERSION constants found to be out of sync (#{versions.inspect}) in #{@root}/lib/**/version.rb") unless versions.uniq.length == 1
        versions.first
      end

      def extract_unreleased(content)
        lines = content.lines
        start_i = lines.index { |l| l.start_with?("## [Unreleased]") }
        return [nil, nil, nil] unless start_i
        # Find the next version heading after Unreleased
        next_i = (start_i + 1)
        while next_i < lines.length && !lines[next_i].start_with?("## [")
          next_i += 1
        end
        # Now next_i points to the next section heading or EOF
        before = lines[0..(start_i - 1)].join
        unreleased_block = lines[(start_i + 1)..(next_i - 1)].join
        after = lines[next_i..-1]&.join || ""
        [unreleased_block, before, after]
      end

      def detect_previous_version(after_text)
        # after_text begins with the first released section following Unreleased
        m = after_text.match(/^## \[(\d+\.\d+\.\d+)\]/)
        return m[1] if m
        nil
      end

      # From the Unreleased block, keep only sections that have content.
      # We detect sections as lines starting with '### '. A section has content if there is at least
      # one non-empty, non-heading line under it before the next '###' or '##'. Typically these are list items.
      # Returns a string that includes only the non-empty sections with their content.
      def filter_unreleased_sections(unreleased_block)
        lines = unreleased_block.lines
        out = []
        i = 0
        while i < lines.length
          line = lines[i]
          if line.start_with?("### ")
            header = line
            i += 1
            chunk = []
            while i < lines.length && !lines[i].start_with?("### ") && !lines[i].start_with?("## ")
              chunk << lines[i]
              i += 1
            end
            # Determine if chunk has any content (non-blank)
            content_present = chunk.any? { |l| l.strip != "" }
            if content_present
              # Trim trailing blank lines
              while chunk.any? && chunk.last.strip == ""
                chunk.pop
              end
              out << header
              out.concat(chunk)
              out << "\n" unless out.last&.end_with?("\n")
            end
            next
          else
            # Lines outside sections are ignored for released sections
            i += 1
          end
        end
        out.join
      end

      def coverage_lines
        unless File.file?(@coverage_path)
          warn("Coverage JSON not found at #{@coverage_path}.")
          warn("Run: K_SOUP_COV_FORMATTERS=\"json\" bin/rspec")
          return [nil, nil]
        end
        data = JSON.parse(File.read(@coverage_path))
        files = data["coverage"] || {}
        file_count = 0
        total_lines = 0
        covered_lines = 0
        total_branches = 0
        covered_branches = 0
        files.each_value do |h|
          lines = h["lines"] || []
          line_relevant = lines.count { |x| x.is_a?(Integer) }
          line_covered = lines.count { |x| x.is_a?(Integer) && x > 0 }
          if line_relevant > 0
            file_count += 1
            total_lines += line_relevant
            covered_lines += line_covered
          end
          branches = h["branches"] || []
          branches.each do |b|
            next unless b.is_a?(Hash)
            cov = b["coverage"]
            next unless cov.is_a?(Numeric)
            total_branches += 1
            covered_branches += 1 if cov > 0
          end
        end
        line_pct = (total_lines > 0) ? ((covered_lines.to_f / total_lines) * 100.0) : 0.0
        branch_pct = (total_branches > 0) ? ((covered_branches.to_f / total_branches) * 100.0) : 0.0
        line_str = format("COVERAGE: %.2f%% -- %d/%d lines in %d files", line_pct, covered_lines, total_lines, file_count)
        branch_str = format("BRANCH COVERAGE: %.2f%% -- %d/%d branches in %d files", branch_pct, covered_branches, total_branches, file_count)
        [line_str, branch_str]
      rescue StandardError => e
        warn("Failed to parse coverage: #{e.class}: #{e.message}")
        [nil, nil]
      end

      def yard_percent_documented
        cmd = File.join(@root, "bin", "yard")
        unless File.executable?(cmd)
          warn("bin/yard not found or not executable; ensure yard is installed via bundler")
          return
        end
        out, _ = Open3.capture2(cmd)
        # Look for a line containing e.g., "95.35% documented"
        line = out.lines.find { |l| l =~ /\d+(?:\.\d+)?%\s+documented/ }
        if line
          line = line.strip
          # Return exactly as requested: e.g. "95.35% documented"
          line
        else
          warn("Could not find documented percentage in bin/yard output.")
          nil
        end
      rescue StandardError => e
        warn("Failed to run bin/yard: #{e.class}: #{e.message}")
        nil
      end

      def update_link_refs(content, owner, repo, prev_version, new_version)
        # Convert any GitLab links to GitHub
        content = content.gsub(%r{https://gitlab\.com/([^/]+)/([^/]+)/-/compare/([^\.]+)\.\.\.([^\s]+)}) do
          o = owner || Regexp.last_match(1)
          r = repo || Regexp.last_match(2)
          from = Regexp.last_match(3)
          to = Regexp.last_match(4)
          "https://github.com/#{o}/#{r}/compare/#{from}...#{to}"
        end
        content = content.gsub(%r{https://gitlab\.com/([^/]+)/([^/]+)/-/tags/(v[^\s\]]+)}) do
          o = owner || Regexp.last_match(1)
          r = repo || Regexp.last_match(2)
          tag = Regexp.last_match(3)
          "https://github.com/#{o}/#{r}/releases/tag/#{tag}"
        end

        # Append or update the bottom reference links
        lines = content.lines

        # Identify the true start of the footer reference block: the line with the [Unreleased] link-ref.
        # Do NOT assume the first link-ref after the Unreleased heading starts the footer, because
        # some changelogs contain interspersed link-refs within section bodies.
        unreleased_ref_idx = lines.index { |l| l.start_with?(UNRELEASED_SECTION_HEADING) }
        first_ref = if unreleased_ref_idx
          unreleased_ref_idx
        else
          # If no [Unreleased]: ref is present, consider the reference block to start at EOF
          lines.length
        end

        # Ensure Unreleased points to GitHub compare from new tag to HEAD
        if owner && repo
          unreleased_ref = "[Unreleased]: https://github.com/#{owner}/#{repo}/compare/v#{new_version}...HEAD\n"
          # Update an existing Unreleased ref only if it appears after Unreleased heading; otherwise append
          idx = nil
          lines.each_with_index do |l, i|
            if l.start_with?(UNRELEASED_SECTION_HEADING) && i >= first_ref
              idx = i
              break
            end
          end
          if idx
            lines[idx] = unreleased_ref
          else
            lines << unreleased_ref
          end
        end

        if owner && repo
          # Add compare link for the new version
          from = prev_version ? "v#{prev_version}" : detect_initial_compare_base(lines)
          new_compare = "[#{new_version}]: https://github.com/#{owner}/#{repo}/compare/#{from}...v#{new_version}\n"
          unless lines.any? { |l| l.start_with?("[#{new_version}]:") }
            lines << new_compare
          end
          # Add tag link for the new version
          new_tag = "[#{new_version}t]: https://github.com/#{owner}/#{repo}/releases/tag/v#{new_version}\n"
          unless lines.any? { |l| l.start_with?("[#{new_version}t]:") }
            lines << new_tag
          end
        end

        # Rebuild and sort the reference block so Unreleased is first, then newest to oldest versions, preserving everything above first_ref
        ref_lines = lines[first_ref..-1].select { |l| l =~ /^\[[^\]]+\]:\s+http/ }
        # Deduplicate by key (text inside the square brackets)
        by_key = {}
        ref_lines.each do |l|
          if l =~ /^\[([^\]]+)\]:\s+/
            by_key[$1] = l
          end
        end
        unreleased_line = by_key.delete("Unreleased")
        # Separate version compare and tag links
        compares = {}
        tags = {}
        by_key.each do |k, v|
          if k =~ /^(\d+\.\d+\.\d+)$/
            compares[$1] = v
          elsif k =~ /^(\d+\.\d+\.\d+)t$/
            tags[$1] = v
          end
        end
        # Build a unified set of versions that appear in either compares or tags
        version_keys = (compares.keys | tags.keys)
        # Sort versions descending (newest to oldest)
        sorted_versions = version_keys.map { |s| Gem::Version.new(s) }.sort.reverse.map(&:to_s)

        new_ref_block = []
        new_ref_block << unreleased_line if unreleased_line
        sorted_versions.each do |v|
          new_ref_block << compares[v] if compares[v]
          new_ref_block << tags[v] if tags[v]
        end
        # Replace the old block
        rebuilt = lines[0...first_ref] + new_ref_block + ["\n"]
        rebuilt.join
      end

      def detect_initial_compare_base(lines)
        # Fallback when prev_version is unknown: try to find the first compare base used historically
        # e.g., for 1.0.0 it may be a commit SHA instead of a tag
        ref = lines.find { |l| l =~ /^\[1\.0\.0\]:\s+https:\/\/github\.com\// }
        if ref && (m = ref.match(%r{compare/([^\.]+)\.\.\.v\d+})).is_a?(MatchData)
          m[1]
        else
          # Default to previous tag name if none found (unlikely to be correct, but better than empty)
          "HEAD^"
        end
      end
    end
  end
end
