# frozen_string_literal: true

module Kettle
  module Dev
    module Tasks
      module InstallTask
        module_function

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
              if helpers.ask("Add PATH_add bin to #{envrc_path}?", true)
                content = current.dup
                insertion = "# Run any command in this project's bin/ without the bin/ prefix\nPATH_add bin\n"
                if content.empty?
                  content = insertion
                else
                  content = insertion + "\n" + content unless content.start_with?(insertion)
                end
                File.open(envrc_path, "w") { |f| f.write(content) }
                puts "   Updated #{envrc_path} with PATH_add bin"
                updated_envrc_by_install = true
              else
                puts "   Skipping modification of .envrc. You may add 'PATH_add bin' manually at the top."
              end
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
              print "Add to .gitignore now [Y/n]: "
              answer = $stdin.gets&.strip
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
                    origin_url = IO.popen(origin_cmd, &:read).to_s.strip
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
                    abort("Aborting: homepage cannot be corrected without a GitHub origin remote.")
                  end

                  org, repo = org_repo
                  suggested = "https://github.com/#{org}/#{repo}"

                  puts "Current spec.homepage appears #{interpolated ? "interpolated" : "invalid"}: #{assigned}"
                  puts "Suggested literal homepage: \"#{suggested}\""
                  print("Update #{File.basename(gemspec_path)} to use this homepage? [Y/n]: ")
                  ans = $stdin.gets&.strip
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
            puts "WARNING: An error occurred while checking gemspec homepage: #{e.class}: #{e.message}"
          end

          if defined?(updated_envrc_by_install) && updated_envrc_by_install
            if ENV.fetch("allowed", "").to_s =~ /\A(1|true|y|yes)\z/i
              puts "Proceeding after .envrc update because allowed=true."
            else
              puts
              puts "IMPORTANT: .envrc was updated during kettle:dev:install."
              puts "Please review it and then run:"
              puts "  direnv allow"
              puts
              puts "After that, re-run to resume:"
              puts "  bundle exec rake kettle:dev:install allowed=true"
              abort("Aborting: direnv allow required after .envrc changes.")
            end
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
          puts "kettle:dev:install complete."
        end
      end
    end
  end
end
