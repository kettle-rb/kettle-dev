# frozen_string_literal: true

# External stdlibs
require "find"
# Internal
require "kettle/dev/input_adapter"

module Kettle
  module Dev
    # Helpers shared by kettle:dev Rake tasks for templating and file ops.
    module TemplateHelpers
      # Track results of templating actions across a single process run.
      # Keys: absolute destination paths (String)
      # Values: Hash with keys: :action (Symbol, one of :create, :replace, :skip, :dir_create, :dir_replace), :timestamp (Time)
      @@template_results = {}

      module_function

      # Root of the host project where Rake was invoked
      # @return [String]
      def project_root
        CIHelpers.project_root
      end

      # Root of this gem's checkout (repository root when working from source)
      # Calculated relative to lib/kettle/dev/
      # @return [String]
      def gem_checkout_root
        File.expand_path("../../..", __dir__)
      end

      # Simple yes/no prompt.
      # @param prompt [String]
      # @param default [Boolean]
      # @return [Boolean]
      def ask(prompt, default)
        # Force mode: any prompt resolves to Yes when ENV["force"] is set truthy
        if ENV.fetch("force", "").to_s =~ /\A(1|true|y|yes)\z/i
          puts "#{prompt} #{default ? "[Y/n]" : "[y/N]"}: Y (forced)"
          return true
        end
        print("#{prompt} #{default ? "[Y/n]" : "[y/N]"}: ")
        ans = Kettle::Dev::InputAdapter.gets&.strip
        ans = "" if ans.nil?
        if default
          ans.empty? || ans =~ /\Ay(es)?\z/i
        else
          ans =~ /\Ay(es)?\z/i
        end
      end

      # Write file content creating directories as needed
      # @param dest_path [String]
      # @param content [String]
      # @return [void]
      def write_file(dest_path, content)
        FileUtils.mkdir_p(File.dirname(dest_path))
        File.open(dest_path, "w") { |f| f.write(content) }
      end

      # Prefer an .example variant for a given source path when present
      # For a given intended source path (e.g., "/src/Rakefile"), this will return
      # "/src/Rakefile.example" if it exists, otherwise returns the original path.
      # If the given path already ends with .example, it is returned as-is.
      # @param src_path [String]
      # @return [String]
      def prefer_example(src_path)
        return src_path if src_path.end_with?(".example")
        example = src_path + ".example"
        File.exist?(example) ? example : src_path
      end

      # Record a template action for a destination path
      # @param dest_path [String]
      # @param action [Symbol] one of :create, :replace, :skip, :dir_create, :dir_replace
      # @return [void]
      def record_template_result(dest_path, action)
        abs = File.expand_path(dest_path.to_s)
        if action == :skip && @@template_results.key?(abs)
          # Preserve the last meaningful action; do not downgrade to :skip
          return
        end
        @@template_results[abs] = {action: action, timestamp: Time.now}
      end

      # Access all template results (read-only clone)
      # @return [Hash]
      def template_results
        @@template_results.clone
      end

      # Returns true if the given path was created or replaced by the template task in this run
      # @param dest_path [String]
      # @return [Boolean]
      def modified_by_template?(dest_path)
        rec = @@template_results[File.expand_path(dest_path.to_s)]
        return false unless rec
        [:create, :replace, :dir_create, :dir_replace].include?(rec[:action])
      end

      # Ensure git working tree is clean before making changes in a task.
      # If not a git repo, this is a no-op.
      # @param root [String] project root to run git commands in
      # @param task_label [String] name of the rake task for user-facing messages (e.g., "kettle:dev:install")
      # @return [void]
      def ensure_clean_git!(root:, task_label:)
        inside_repo = begin
          system("git", "-C", root.to_s, "rev-parse", "--is-inside-work-tree", out: File::NULL, err: File::NULL)
        rescue StandardError
          false
        end
        return unless inside_repo

        status_output = begin
          IO.popen(["git", "-C", root.to_s, "status", "--porcelain"], &:read).to_s
        rescue StandardError
          ""
        end
        return if status_output.strip.empty?

        puts "ERROR: Your git working tree has uncommitted changes."
        puts "#{task_label} may modify files (e.g., .github/, .gitignore, *.gemspec)."
        puts "Please commit or stash your changes, then re-run: rake #{task_label}"
        preview = status_output.lines.take(10).map(&:rstrip)
        unless preview.empty?
          puts "Detected changes:"
          preview.each { |l| puts "  #{l}" }
          puts "(showing up to first 10 lines)"
        end
        raise Kettle::Dev::Error, "Aborting: git working tree is not clean."
      end

      # Copy a single file with interactive prompts for create/replace.
      # Yields content for transformation when block given.
      # @return [void]
      def copy_file_with_prompt(src_path, dest_path, allow_create: true, allow_replace: true)
        return unless File.exist?(src_path)

        # Apply optional inclusion filter via ENV["only"] (comma-separated glob patterns relative to project root)
        begin
          only_raw = ENV["only"].to_s
          if !only_raw.empty?
            patterns = only_raw.split(",").map { |s| s.strip }.reject(&:empty?)
            if !patterns.empty?
              proj = project_root.to_s
              rel_dest = dest_path.to_s
              if rel_dest.start_with?(proj + "/")
                rel_dest = rel_dest[(proj.length + 1)..-1]
              elsif rel_dest == proj
                rel_dest = ""
              end
              matched = patterns.any? do |pat|
                if pat.end_with?("/**")
                  base = pat[0..-4]
                  rel_dest == base || rel_dest.start_with?(base + "/")
                else
                  File.fnmatch?(pat, rel_dest, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
                end
              end
              unless matched
                record_template_result(dest_path, :skip)
                puts "Skipping #{dest_path} (excluded by only filter)"
                return
              end
            end
          end
        rescue StandardError
          # If anything goes wrong parsing/matching, ignore the filter and proceed.
        end

        dest_exists = File.exist?(dest_path)
        action = nil
        if dest_exists
          if allow_replace
            action = ask("Replace #{dest_path}?", true) ? :replace : :skip
          else
            puts "Skipping #{dest_path} (replace not allowed)."
            action = :skip
          end
        elsif allow_create
          action = ask("Create #{dest_path}?", true) ? :create : :skip
        else
          puts "Skipping #{dest_path} (create not allowed)."
          action = :skip
        end
        if action == :skip
          record_template_result(dest_path, :skip)
          return
        end

        content = File.read(src_path)
        content = yield(content) if block_given?
        write_file(dest_path, content)
        record_template_result(dest_path, dest_exists ? :replace : :create)
        puts "Wrote #{dest_path}"
      end

      # Copy a directory tree, prompting before creating or overwriting.
      # @return [void]
      def copy_dir_with_prompt(src_dir, dest_dir)
        return unless Dir.exist?(src_dir)

        # Build a matcher for ENV["only"], relative to project root, that can be reused within this method
        only_raw = ENV["only"].to_s
        patterns = only_raw.split(",").map { |s| s.strip }.reject(&:empty?) unless only_raw.nil?
        patterns ||= []
        proj_root = project_root.to_s
        matches_only = lambda do |abs_dest|
          return true if patterns.empty?
          begin
            rel_dest = abs_dest.to_s
            if rel_dest.start_with?(proj_root + "/")
              rel_dest = rel_dest[(proj_root.length + 1)..-1]
            elsif rel_dest == proj_root
              rel_dest = ""
            end
            patterns.any? do |pat|
              if pat.end_with?("/**")
                base = pat[0..-4]
                rel_dest == base || rel_dest.start_with?(base + "/")
              else
                File.fnmatch?(pat, rel_dest, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
              end
            end
          rescue StandardError
            # On any error, do not filter out (act as matched)
            true
          end
        end

        # Early exit: if an only filter is present and no files inside this directory would match,
        # do not prompt to create/replace this directory at all.
        begin
          if !patterns.empty?
            any_match = false
            Find.find(src_dir) do |path|
              rel = path.sub(/^#{Regexp.escape(src_dir)}\/?/, "")
              next if rel.empty?
              next if File.directory?(path)
              target = File.join(dest_dir, rel)
              if matches_only.call(target)
                any_match = true
                break
              end
            end
            unless any_match
              record_template_result(dest_dir, :skip)
              return
            end
          end
        rescue StandardError
          # If determining matches fails, fall through to prompting logic
        end

        dest_exists = Dir.exist?(dest_dir)
        if dest_exists
          if ask("Replace directory #{dest_dir} (will overwrite files)?", true)
            Find.find(src_dir) do |path|
              rel = path.sub(/^#{Regexp.escape(src_dir)}\/?/, "")
              next if rel.empty?
              target = File.join(dest_dir, rel)
              if File.directory?(path)
                FileUtils.mkdir_p(target)
              else
                # Per-file inclusion filter
                next unless matches_only.call(target)

                FileUtils.mkdir_p(File.dirname(target))
                if File.exist?(target)

                  # Skip only if contents are identical. If source and target paths are the same,
                  # avoid FileUtils.cp (which raises) and do an in-place rewrite to satisfy "copy".
                  begin
                    if FileUtils.compare_file(path, target)
                      next
                    elsif path == target
                      data = File.binread(path)
                      File.open(target, "wb") { |f| f.write(data) }
                      next
                    end
                  rescue StandardError
                    # ignore compare errors; fall through to copy
                  end
                end
                FileUtils.cp(path, target)
              end
            end
            puts "Updated #{dest_dir}"
            record_template_result(dest_dir, :dir_replace)
          else
            puts "Skipped #{dest_dir}"
            record_template_result(dest_dir, :skip)
          end
        elsif ask("Create directory #{dest_dir}?", true)
          FileUtils.mkdir_p(dest_dir)
          Find.find(src_dir) do |path|
            rel = path.sub(/^#{Regexp.escape(src_dir)}\/?/, "")
            next if rel.empty?
            target = File.join(dest_dir, rel)
            if File.directory?(path)
              FileUtils.mkdir_p(target)
            else
              # Per-file inclusion filter
              next unless matches_only.call(target)

              FileUtils.mkdir_p(File.dirname(target))
              if File.exist?(target)
                # Skip only if contents are identical. If source and target paths are the same,
                # avoid FileUtils.cp (which raises) and do an in-place rewrite to satisfy "copy".
                begin
                  if FileUtils.compare_file(path, target)
                    next
                  elsif path == target
                    data = File.binread(path)
                    File.open(target, "wb") { |f| f.write(data) }
                    next
                  end
                rescue StandardError
                  # ignore compare errors; fall through to copy
                end
              end
              FileUtils.cp(path, target)
            end
          end
          puts "Created #{dest_dir}"
          record_template_result(dest_dir, :dir_create)
        end
      end

      # Apply common token replacements used when templating text files
      # @param content [String]
      # @param org [String, nil]
      # @param gem_name [String]
      # @param namespace [String]
      # @param namespace_shield [String]
      # @param gem_shield [String]
      # @return [String]
      def apply_common_replacements(content, org:, gem_name:, namespace:, namespace_shield:, gem_shield:)
        c = content.dup
        c = c.gsub("kettle-rb", org.to_s) if org && !org.empty?
        if gem_name && !gem_name.empty?
          # Replace occurrences of the template gem name in text, including inside
          # markdown reference labels like [🖼️kettle-dev] and identifiers like kettle-dev-i
          c = c.gsub("kettle-dev", gem_name)
          c = c.gsub(/\bKettle::Dev\b/u, namespace) unless namespace.empty?
          c = c.gsub("Kettle%3A%3ADev", namespace_shield) unless namespace_shield.empty?
          c = c.gsub("kettle--dev", gem_shield)
        end
        c
      end

      # Parse gemspec metadata and derive useful strings
      # @param root [String] project root
      # @return [Hash]
      def gemspec_metadata(root = project_root)
        gemspecs = Dir.glob(File.join(root, "*.gemspec"))
        gemspec_path = gemspecs.first
        gemspec_text = (gemspec_path && File.file?(gemspec_path)) ? File.read(gemspec_path) : ""
        gem_name = (gemspec_text[/\bspec\.name\s*=\s*["']([^"']+)["']/, 1] || "").strip
        min_ruby = (
          gemspec_text[/\bspec\.minimum_ruby_version\s*=\s*["'](?:>=\s*)?([0-9]+\.[0-9]+(?:\.[0-9]+)?)["']/i, 1] ||
          gemspec_text[/\bspec\.required_ruby_version\s*=\s*["']>=\s*([0-9]+\.[0-9]+(?:\.[0-9]+)?)["']/i, 1] ||
          gemspec_text[/\brequired_ruby_version\s*[:=]\s*["'](?:>=\s*)?([0-9]+\.[0-9]+(?:\.[0-9]+)?)["']/i, 1] ||
          ""
        ).strip
        homepage_line = gemspec_text.lines.find { |l| l =~ /\bspec\.homepage\s*=\s*/ }
        homepage_val = homepage_line ? homepage_line.split("=", 2).last.to_s.strip : ""
        if (homepage_val.start_with?("\"") && homepage_val.end_with?("\"")) || (homepage_val.start_with?("'") && homepage_val.end_with?("'"))
          homepage_val = begin
            homepage_val[1..-2]
          rescue
            homepage_val
          end
        end
        gh_match = homepage_val&.match(%r{github\.com/([^/]+)/([^/]+)}i)
        forge_org = gh_match && gh_match[1]
        gh_repo = gh_match && gh_match[2]&.sub(/\.git\z/, "")
        if forge_org.nil?
          begin
            origin_out = IO.popen(["git", "-C", root.to_s, "remote", "get-url", "origin"], &:read)
            origin_out = origin_out.read if origin_out.respond_to?(:read)
            origin_url = origin_out.to_s.strip
            if (m = origin_url.match(%r{github\.com[/:]([^/]+)/([^/]+)}i))
              forge_org = m[1]
              gh_repo = m[2]&.sub(/\.git\z/, "")
            end
          rescue StandardError
            # ignore
          end
        end

        camel = lambda do |s|
          s.split(/[_-]/).map { |p| p.gsub(/\b([a-z])/) { Regexp.last_match(1).upcase } }.join
        end
        namespace = gem_name.to_s.split("-").map { |seg| camel.call(seg) }.join("::")
        namespace_shield = namespace.gsub("::", "%3A%3A")
        entrypoint_require = gem_name.to_s.tr("-", "/")
        gem_shield = gem_name.to_s.gsub("-", "--").gsub("_", "__")

        # Determine funding_org independently of forge_org (GitHub org)
        funding_org = ENV["FUNDING_ORG"].to_s.strip
        funding_org = ENV["OPENCOLLECTIVE_ORG"].to_s.strip if funding_org.empty?
        funding_org = ENV["OPENCOLLECTIVE_HANDLE"].to_s.strip if funding_org.empty?
        if funding_org.empty?
          begin
            oc_path = File.join(root.to_s, ".opencollective.yml")
            if File.file?(oc_path)
              txt = File.read(oc_path)
              if (m = txt.match(/\borg:\s*([\w\-]+)/i))
                funding_org = m[1].to_s
              end
            end
          rescue StandardError
            # ignore
          end
        end
        funding_org = forge_org.to_s if funding_org.to_s.empty?

        {
          gemspec_path: gemspec_path,
          gem_name: gem_name,
          min_ruby: min_ruby,
          homepage: homepage_val,
          gh_org: forge_org, # Backward compat: keep old key synonymous with forge_org
          forge_org: forge_org,
          funding_org: funding_org,
          gh_repo: gh_repo,
          namespace: namespace,
          namespace_shield: namespace_shield,
          entrypoint_require: entrypoint_require,
          gem_shield: gem_shield,
        }
      end
    end
  end
end
