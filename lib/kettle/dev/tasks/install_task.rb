# frozen_string_literal: true

require "kettle/dev/exit_adapter"
require "kettle/dev/input_adapter"

module Kettle
  module Dev
    module Tasks
      module InstallTask
        module_function

        # Abort wrapper that avoids terminating the entire process during specs
        def task_abort(msg)
          if defined?(RSpec)
            raise Kettle::Dev::Error, msg
          else
            Kettle::Dev::ExitAdapter.abort(msg)
          end
        end

        def run
          helpers = Kettle::Dev::TemplateHelpers
          project_root = helpers.project_root

          # Run file templating via dedicated task first
          Rake::Task["kettle:dev:template"].invoke

          # .tool-versions cleanup offers
          tool_versions_path = File.join(project_root, ".tool-versions")
          if File.file?(tool_versions_path)
            rv = File.join(project_root, ".ruby-version")
            rg = File.join(project_root, ".ruby-gemset")
            to_remove = [rv, rg].select { |p| File.exist?(p) }
            unless to_remove.empty?
              if helpers.ask("Remove #{to_remove.map { |p| File.basename(p) }.join(" and ")} (managed by .tool-versions)?", true)
                to_remove.each { |p| FileUtils.rm_f(p) }
                puts "Removed #{to_remove.map { |p| File.basename(p) }.join(" and ")}"
              end
            end
          end

          # Trim MRI Ruby version badges in README.md to >= required_ruby_version from gemspec
          begin
            readme_path = File.join(project_root, "README.md")
            if File.file?(readme_path)
              md = helpers.gemspec_metadata(project_root)
              min_ruby = md[:min_ruby].to_s.strip
              if !min_ruby.empty?
                # Compare using Gem::Version on major.minor
                require "rubygems"
                min_ver = begin
                  Gem::Version.new(min_ruby.sub(/\A(~>\s*|>=\s*)/, ""))
                rescue
                  nil
                end
                if min_ver
                  content = File.read(readme_path)

                  # Detect all MRI ruby badge labels present
                  removed_labels = []

                  content.scan(/\[(?<label>💎ruby-(?<ver>\d+\.\d+)i)\]/) do |arr|
                    label, ver_s = arr
                    begin
                      ver = Gem::Version.new(ver_s)
                      if ver < min_ver
                        # Remove occurrences of badges using this label
                        label_re = Regexp.escape(label)
                        # Linked form: [![...][label]][...]
                        content = content.gsub(/\[!\[[^\]]*?\]\s*\[#{label_re}\]\s*\]\s*\[[^\]]+\]/, "")
                        # Unlinked form: ![...][label]
                        content = content.gsub(/!\[[^\]]*?\]\s*\[#{label_re}\]/, "")
                        removed_labels << label
                      end
                    rescue StandardError
                      # ignore
                    end
                  end

                  # Fix leading <br/> in MRI rows and remove rows that end up empty
                  content = content.lines.map { |ln|
                    if ln.start_with?("| Works with MRI Ruby")
                      cells = ln.split("|", -1)
                      # cells[0] is empty (leading |), cells[1] = label cell, cells[2] = badges cell
                      badge_cell = cells[2] || ""
                      # If badge cell is only a <br/> (possibly with whitespace), treat as empty (row will be removed later)
                      if badge_cell.strip == "<br/>"
                        cells[2] = " "
                        cells.join("|")
                      elsif badge_cell =~ /\A\s*<br\/>/i
                        # If badge cell starts with <br/> and there are no badges before it, strip the leading <br/>
                        # We consider "no badges before" as any leading whitespace followed immediately by <br/>
                        cleaned = badge_cell.sub(/\A\s*<br\/>\s*/i, "")
                        cells[2] = " #{cleaned}" # prefix with a single space
                        cells.join("|")
                      else
                        ln
                      end
                    else
                      ln
                    end
                  }.reject { |ln|
                    if ln.start_with?("| Works with MRI Ruby")
                      cells = ln.split("|", -1)
                      badge_cell = cells[2] || ""
                      badge_cell.strip.empty?
                    else
                      false
                    end
                  }.join

                  # Clean up extra repeated whitespace only when it appears between word characters, and only for non-table lines.
                  # This preserves Markdown table alignment and spacing around punctuation/symbols.
                  content = content.lines.map do |ln|
                    if ln.start_with?("|")
                      ln
                    else
                      # Squish only runs of spaces/tabs between word characters
                      ln.gsub(/(\w)[ \t]{2,}(\w)/u, "\\1 \\2")
                    end
                  end.join

                  # Remove reference definitions for removed labels that are no longer used
                  unless removed_labels.empty?
                    # Unique
                    removed_labels.uniq!
                    # Determine which labels are still referenced after edits
                    still_referenced = {}
                    removed_labels.each do |lbl|
                      lbl_re = Regexp.escape(lbl)
                      # Consider a label referenced only when it appears not as a definition (i.e., not followed by colon)
                      still_referenced[lbl] = !!(content =~ /\[#{lbl_re}\](?!:)/)
                    end

                    new_lines = content.lines.map do |line|
                      if line =~ /^\[(?<lab>[^\]]+)\]:/ && removed_labels.include?(Regexp.last_match(:lab))
                        # Only drop if not referenced anymore
                        still_referenced[Regexp.last_match(:lab)] ? line : nil
                      else
                        line
                      end
                    end.compact
                    content = new_lines.join
                  end

                  File.open(readme_path, "w") { |f| f.write(content) }
                end
              end
            end
          rescue StandardError => e
            puts "WARNING: Skipped trimming MRI Ruby badges in README.md due to #{e.class}: #{e.message}"
          end

          # Synchronize leading grapheme (emoji) between README H1 and gemspec summary/description
          begin
            readme_path = File.join(project_root, "README.md")
            gemspecs = Dir.glob(File.join(project_root, "*.gemspec"))
            if File.file?(readme_path) && !gemspecs.empty?
              gemspec_path = gemspecs.first
              readme = File.read(readme_path)
              first_h1_idx = readme.lines.index { |ln| ln =~ /^#\s+/ }
              chosen_grapheme = nil
              if first_h1_idx
                lines = readme.split("\n", -1)
                h1 = lines[first_h1_idx]
                tail = h1.sub(/^#\s+/, "")
                begin
                  emoji_re = Kettle::EmojiRegex::REGEX
                  # Extract first emoji grapheme cluster if present
                  if tail =~ /\A#{emoji_re.source}/u
                    cluster = tail[/\A\X/u]
                    chosen_grapheme = cluster unless cluster.to_s.empty?
                  end
                rescue StandardError
                  # Fallback: take first Unicode grapheme if any non-space char
                  chosen_grapheme ||= tail[/\A\X/u]
                end
              end

              # If no grapheme found in README H1, ask the user which to use
              if chosen_grapheme.nil? || chosen_grapheme.empty?
                puts "No grapheme found after README H1. Enter a grapheme (emoji/symbol) to use for README, summary, and description:"
                print("Grapheme: ")
                ans = Kettle::Dev::InputAdapter.gets&.strip.to_s
                chosen_grapheme = ans[/\A\X/u].to_s
                # If still empty, skip synchronization silently
                chosen_grapheme = nil if chosen_grapheme.empty?
              end

              if chosen_grapheme
                # 1) Normalize README H1 to exactly one grapheme + single space after '#'
                begin
                  lines = readme.split("\n", -1)
                  idx = lines.index { |ln| ln =~ /^#\s+/ }
                  if idx
                    rest = lines[idx].sub(/^#\s+/, "")
                    begin
                      emoji_re = Kettle::EmojiRegex::REGEX
                      # Remove any leading emojis from the H1 by peeling full grapheme clusters
                      tmp = rest.dup
                      while tmp =~ /\A#{emoji_re.source}/u
                        cluster = tmp[/\A\X/u]
                        tmp = tmp[cluster.length..-1].to_s
                      end
                      rest_wo_emoji = tmp.sub(/\A\s+/, "")
                    rescue StandardError
                      rest_wo_emoji = rest.sub(/\A\s+/, "")
                    end
                    # Build H1 with single spaces only around separators; preserve inner spacing in rest_wo_emoji
                    new_line = ["#", chosen_grapheme, rest_wo_emoji].join(" ").sub(/^#\s+/, "# ")
                    lines[idx] = new_line
                    new_readme = lines.join("\n")
                    File.open(readme_path, "w") { |f| f.write(new_readme) }
                  end
                rescue StandardError
                  # ignore README normalization errors
                end

                # 2) Update gemspec summary and description to start with grapheme + single space
                begin
                  gspec = File.read(gemspec_path)

                  normalize_field = lambda do |text, field|
                    # Match the assignment line and the first quoted string
                    text.gsub(/(\b#{Regexp.escape(field)}\s*=\s*)(["'])([^\"']*)(\2)/) do
                      pre = Regexp.last_match(1)
                      q = Regexp.last_match(2)
                      body = Regexp.last_match(3)
                      # Strip existing leading emojis and spaces
                      begin
                        emoji_re = Kettle::EmojiRegex::REGEX
                        tmp = body.dup
                        tmp = tmp.sub(/\A\s+/, "")
                        while tmp =~ /\A#{emoji_re.source}/u
                          cluster = tmp[/\A\X/u]
                          tmp = tmp[cluster.length..-1].to_s
                        end
                        tmp = tmp.sub(/\A\s+/, "")
                        body_wo = tmp
                      rescue StandardError
                        body_wo = body.sub(/\A\s+/, "")
                      end
                      pre + q + ("#{chosen_grapheme} " + body_wo) + q
                    end
                  end

                  gspec2 = normalize_field.call(gspec, "spec.summary")
                  gspec3 = normalize_field.call(gspec2, "spec.description")
                  if gspec3 != gspec
                    File.open(gemspec_path, "w") { |f| f.write(gspec3) }
                  end
                rescue StandardError
                  # ignore gemspec edits on error
                end
              end
            end
          rescue StandardError => e
            puts "WARNING: Skipped grapheme synchronization due to #{e.class}: #{e.message}"
          end

          # Perform final whitespace normalization for README: only squish whitespace between word characters (non-table lines)
          begin
            readme_path = File.join(project_root, "README.md")
            if File.file?(readme_path)
              content = File.read(readme_path)
              content = content.lines.map do |ln|
                if ln.start_with?("|")
                  ln
                else
                  ln.gsub(/(\w)[ \t]{2,}(\w)/u, "\\1 \\2")
                end
              end.join
              File.open(readme_path, "w") { |f| f.write(content) }
            end
          rescue StandardError
            # ignore whitespace normalization errors
          end

          # Validate gemspec homepage points to GitHub and is a non-interpolated string
          begin
            gemspecs = Dir.glob(File.join(project_root, "*.gemspec"))
            if gemspecs.empty?
              puts
              puts "No .gemspec found in #{project_root}; skipping homepage check."
            else
              gemspec_path = gemspecs.first
              if gemspecs.size > 1
                puts
                puts "Multiple gemspecs found; defaulting to #{File.basename(gemspec_path)} for homepage check."
              end

              content = File.read(gemspec_path)
              homepage_line = content.lines.find { |l| l =~ /\bspec\.homepage\s*=\s*/ }
              if homepage_line.nil?
                puts
                puts "WARNING: spec.homepage not found in #{File.basename(gemspec_path)}."
                puts "This gem should declare a GitHub homepage: https://github.com/<org>/<repo>"
              else
                assigned = homepage_line.split("=", 2).last.to_s.strip
                interpolated = assigned.include?('#{')

                if assigned.start_with?("\"", "'")
                  begin
                    assigned = assigned[1..-2]
                  rescue
                    # leave as-is
                  end
                end

                github_repo_from_url = lambda do |url|
                  return unless url
                  url = url.strip
                  m = url.match(%r{github\.com[/:]([^/\s:]+)/([^/\s]+?)(?:\.git)?/?\z}i)
                  return unless m
                  [m[1], m[2]]
                end

                github_homepage_literal = lambda do |val|
                  return false unless val
                  return false if val.include?('#{')
                  v = val.to_s.strip
                  if (v.start_with?("\"") && v.end_with?("\"")) || (v.start_with?("'") && v.end_with?("'"))
                    v = begin
                      v[1..-2]
                    rescue
                      v
                    end
                  end
                  return false unless v =~ %r{\Ahttps?://github\.com/}i
                  !!github_repo_from_url.call(v)
                end

                valid_literal = github_homepage_literal.call(assigned)

                if interpolated || !valid_literal
                  puts
                  puts "Checking git remote 'origin' to derive GitHub homepage..."
                  origin_url = nil
                  begin
                    origin_cmd = ["git", "-C", project_root.to_s, "remote", "get-url", "origin"]
                    origin_out = IO.popen(origin_cmd, &:read)
                    origin_out = origin_out.read if origin_out.respond_to?(:read)
                    origin_url = origin_out.to_s.strip
                  rescue StandardError
                    origin_url = ""
                  end

                  org_repo = github_repo_from_url.call(origin_url)
                  unless org_repo
                    puts "ERROR: git remote 'origin' is not a GitHub URL (or not found): #{origin_url.empty? ? "(none)" : origin_url}"
                    puts "To complete installation: set your GitHub repository as the 'origin' remote, and move any other forge to an alternate name."
                    puts "Example:"
                    puts "  git remote rename origin something_else"
                    puts "  git remote add origin https://github.com/<org>/<repo>.git"
                    puts "After fixing, re-run: rake kettle:dev:install"
                    task_abort("Aborting: homepage cannot be corrected without a GitHub origin remote.")
                  end

                  org, repo = org_repo
                  suggested = "https://github.com/#{org}/#{repo}"

                  puts "Current spec.homepage appears #{interpolated ? "interpolated" : "invalid"}: #{assigned}"
                  puts "Suggested literal homepage: \"#{suggested}\""
                  print("Update #{File.basename(gemspec_path)} to use this homepage? [Y/n]: ")
                  ans = Kettle::Dev::InputAdapter.gets&.strip
                  do_update = if ENV.fetch("force", "").to_s =~ /\A(1|true|y|yes)\z/i
                    true
                  else
                    ans.nil? || ans.empty? || ans =~ /\Ay(es)?\z/i
                  end

                  if do_update
                    new_line = homepage_line.sub(/=.*/, "= \"#{suggested}\"\n")
                    new_content = content.sub(homepage_line, new_line)
                    File.open(gemspec_path, "w") { |f| f.write(new_content) }
                    puts "Updated spec.homepage in #{File.basename(gemspec_path)} to #{suggested}"
                  else
                    puts "Skipping update of spec.homepage. You should set it to: #{suggested}"
                  end
                end
              end
            end
          rescue StandardError => e
            # Do not swallow intentional task aborts signaled via Kettle::Dev::Error
            raise if e.is_a?(Kettle::Dev::Error)
            puts "WARNING: An error occurred while checking gemspec homepage: #{e.class}: #{e.message}"
          end

          # Summary of templating changes
          begin
            results = helpers.template_results
            meaningful = results.select { |_, rec| [:create, :replace, :dir_create, :dir_replace].include?(rec[:action]) }
            puts
            puts "Summary of templating changes:"
            if meaningful.empty?
              puts "  (no files were created or replaced by kettle:dev:template)"
            else
              action_labels = {
                create: "Created",
                replace: "Replaced",
                dir_create: "Directory created",
                dir_replace: "Directory replaced",
              }
              [:create, :replace, :dir_create, :dir_replace].each do |sym|
                items = meaningful.select { |_, rec| rec[:action] == sym }.map { |path, _| path }
                next if items.empty?
                puts "  #{action_labels[sym]}:"
                items.sort.each do |abs|
                  rel = begin
                    abs.start_with?(project_root.to_s) ? abs.sub(/^#{Regexp.escape(project_root.to_s)}\/?/, "") : abs
                  rescue
                    abs
                  end
                  puts "    - #{rel}"
                end
              end
            end
          rescue StandardError => e
            puts
            puts "Summary of templating changes: (unavailable: #{e.class}: #{e.message})"
          end

          puts
          puts "Next steps:"
          puts "1) Configure a shared git hooks path (optional, recommended):"
          puts "   git config --global core.hooksPath .git-hooks"
          puts
          puts "2) Install binstubs for this gem so the commit-msg tool is available in ./bin:"
          puts "   bundle binstubs kettle-dev --path bin"
          puts "   # After running, you should have bin/kettle-commit-msg (wrapper)."
          puts
          # Step 3: direnv and .envrc
          envrc_path = File.join(project_root, ".envrc")
          puts "3) Install direnv (if not already):"
          puts "   brew install direnv"
          if helpers.modified_by_template?(envrc_path)
            puts "   Your .envrc was created/updated by kettle:dev:template."
            puts "   It includes PATH_add bin so that executables in ./bin are on PATH when direnv is active."
            puts "   This allows running tools without the bin/ prefix inside the project directory."
          else
            begin
              current = File.file?(envrc_path) ? File.read(envrc_path) : ""
            rescue StandardError
              current = ""
            end
            has_path_add = current.lines.any? { |l| l.strip =~ /^PATH_add\s+bin\b/ }
            if has_path_add
              puts "   Your .envrc already contains PATH_add bin."
            else
              puts "   Adding PATH_add bin to your project's .envrc is recommended to expose ./bin on PATH."
              if helpers.ask("Add PATH_add bin to #{envrc_path}?", false)
                content = current.dup
                insertion = "# Run any command in this project's bin/ without the bin/ prefix\nPATH_add bin\n"
                if content.empty?
                  content = insertion
                else
                  content = insertion + "\n" + content unless content.start_with?(insertion)
                end
                # Ensure a stale directory at .envrc is removed so the file can be written
                FileUtils.rm_rf(envrc_path) if File.directory?(envrc_path)
                File.open(envrc_path, "w") { |f| f.write(content) }
                puts "   Updated #{envrc_path} with PATH_add bin"
                updated_envrc_by_install = true
              else
                puts "   Skipping modification of .envrc. You may add 'PATH_add bin' manually at the top."
              end
            end
          end

          if defined?(updated_envrc_by_install) && updated_envrc_by_install
            allowed_truthy = ENV.fetch("allowed", "").to_s =~ /\A(1|true|y|yes)\z/i
            force_truthy = ENV.fetch("force", "").to_s =~ /\A(1|true|y|yes)\z/i
            if allowed_truthy || force_truthy
              reason = allowed_truthy ? "allowed=true" : "force=true"
              puts "Proceeding after .envrc update because #{reason}."
            else
              puts
              puts "IMPORTANT: .envrc was updated during kettle:dev:install."
              puts "Please review it and then run:"
              puts "  direnv allow"
              puts
              puts "After that, re-run to resume:"
              puts "  bundle exec rake kettle:dev:install allowed=true"
              task_abort("Aborting: direnv allow required after .envrc changes.")
            end
          end

          # Warn about .env.local and offer to add it to .gitignore
          puts
          puts "WARNING: Do not commit .env.local; it often contains machine-local secrets."
          puts "Ensure your .gitignore includes:"
          puts "  # direnv - brew install direnv"
          puts "  .env.local"

          gitignore_path = File.join(project_root, ".gitignore")
          unless helpers.modified_by_template?(gitignore_path)
            begin
              gitignore_current = File.exist?(gitignore_path) ? File.read(gitignore_path) : ""
            rescue StandardError
              gitignore_current = ""
            end
            has_env_local = gitignore_current.lines.any? { |l| l.strip == ".env.local" }
            unless has_env_local
              puts
              puts "Would you like to add '.env.local' to #{gitignore_path}?"
              print("Add to .gitignore now [Y/n]: ")
              answer = Kettle::Dev::InputAdapter.gets&.strip
              add_it = if ENV.fetch("force", "").to_s =~ /\A(1|true|y|yes)\z/i
                true
              else
                answer.nil? || answer.empty? || answer =~ /\Ay(es)?\z/i
              end
              if add_it
                FileUtils.mkdir_p(File.dirname(gitignore_path))
                mode = File.exist?(gitignore_path) ? "a" : "w"
                File.open(gitignore_path, mode) do |f|
                  f.write("\n") unless gitignore_current.empty? || gitignore_current.end_with?("\n")
                  unless gitignore_current.lines.any? { |l| l.strip == "# direnv - brew install direnv" }
                    f.write("# direnv - brew install direnv\n")
                  end
                  f.write(".env.local\n")
                end
                puts "Added .env.local to #{gitignore_path}"
              else
                puts "Skipping modification of .gitignore. Remember to add .env.local to avoid committing it."
              end
            end
          end

          puts
          puts "kettle:dev:install complete."
        end
      end
    end
  end
end
