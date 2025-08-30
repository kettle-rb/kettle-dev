# frozen_string_literal: true

require "kettle/dev/exit_adapter"
require "kettle/dev/input_adapter"

module Kettle
  module Dev
    module Tasks
      # Thin wrapper to expose the kettle:dev:template task logic as a callable API
      # for testability. The rake task should only call this method.
      module TemplateTask
        module_function

        # Abort wrapper that avoids terminating the entire process during specs
        def task_abort(msg)
          if defined?(RSpec)
            raise Kettle::Dev::Error, msg
          else
            Kettle::Dev::ExitAdapter.abort(msg)
          end
        end

        # Execute the template operation into the current project.
        # All options/IO are controlled via TemplateHelpers and ENV.
        def run
          # Inline the former rake task body, but using helpers directly.
          helpers = Kettle::Dev::TemplateHelpers

          project_root = helpers.project_root
          gem_checkout_root = helpers.gem_checkout_root

          # Ensure git working tree is clean before making changes (when run standalone)
          helpers.ensure_clean_git!(root: project_root, task_label: "kettle:dev:template")

          meta = helpers.gemspec_metadata(project_root)
          gem_name = meta[:gem_name]
          min_ruby = meta[:min_ruby]
          forge_org = meta[:forge_org] || meta[:gh_org]
          funding_org = meta[:funding_org] || forge_org
          entrypoint_require = meta[:entrypoint_require]
          namespace = meta[:namespace]
          namespace_shield = meta[:namespace_shield]
          gem_shield = meta[:gem_shield]

          # 1) .devcontainer directory
          helpers.copy_dir_with_prompt(File.join(gem_checkout_root, ".devcontainer"), File.join(project_root, ".devcontainer"))

          # 2) .github/**/*.yml with FUNDING.yml customizations
          source_github_dir = File.join(gem_checkout_root, ".github")
          if Dir.exist?(source_github_dir)
            files = Dir.glob(File.join(source_github_dir, "**", "*.yml")) +
              Dir.glob(File.join(source_github_dir, "**", "*.yml.example"))
            files.uniq.each do |orig_src|
              src = helpers.prefer_example(orig_src)
              # Destination path should never include the .example suffix.
              rel = orig_src.sub(/^#{Regexp.escape(gem_checkout_root)}\/?/, "").sub(/\.example\z/, "")
              dest = File.join(project_root, rel)
              if File.basename(rel) == "FUNDING.yml"
                helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) do |content|
                  c = content.dup
                  c = c.gsub(/^open_collective:\s+.*$/i) { |line| funding_org ? "open_collective: #{funding_org}" : line }
                  if gem_name && !gem_name.empty?
                    c = c.gsub(/^tidelift:\s+.*$/i, "tidelift: rubygems/#{gem_name}")
                  end
                  # Also apply common replacements for org/gem/namespace/shields
                  helpers.apply_common_replacements(
                    c,
                    org: forge_org,
                    gem_name: gem_name,
                    namespace: namespace,
                    namespace_shield: namespace_shield,
                    gem_shield: gem_shield,
                  )
                end
              else
                helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) do |content|
                  helpers.apply_common_replacements(
                    content,
                    org: forge_org,
                    gem_name: gem_name,
                    namespace: namespace,
                    namespace_shield: namespace_shield,
                    gem_shield: gem_shield,
                  )
                end
              end
            end
          end

          # 3) .qlty/qlty.toml
          helpers.copy_file_with_prompt(
            helpers.prefer_example(File.join(gem_checkout_root, ".qlty/qlty.toml")),
            File.join(project_root, ".qlty/qlty.toml"),
            allow_create: true,
            allow_replace: true,
          )

          # 4) gemfiles/modular/*.gemfile (from gem's gemfiles/modular)
          [%w[coverage.gemfile], %w[documentation.gemfile], %w[style.gemfile], %w[optional.gemfile]].each do |base|
            src = helpers.prefer_example(File.join(gem_checkout_root, "gemfiles/modular", base[0]))
            dest = File.join(project_root, "gemfiles/modular", base[0])
            if File.basename(src).sub(/\.example\z/, "") == "style.gemfile"
              helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) do |content|
                # Adjust rubocop-lts constraint based on min_ruby
                version_map = [
                  [Gem::Version.new("1.8"), "~> 0.0"],
                  [Gem::Version.new("1.9"), "~> 2.0"],
                  [Gem::Version.new("2.0"), "~> 4.0"],
                  [Gem::Version.new("2.1"), "~> 6.0"],
                  [Gem::Version.new("2.2"), "~> 8.0"],
                  [Gem::Version.new("2.3"), "~> 10.0"],
                  [Gem::Version.new("2.4"), "~> 12.0"],
                  [Gem::Version.new("2.5"), "~> 14.0"],
                  [Gem::Version.new("2.6"), "~> 16.0"],
                  [Gem::Version.new("2.7"), "~> 18.0"],
                  [Gem::Version.new("3.0"), "~> 20.0"],
                  [Gem::Version.new("3.1"), "~> 22.0"],
                  [Gem::Version.new("3.2"), "~> 24.0"],
                  [Gem::Version.new("3.3"), "~> 26.0"],
                  [Gem::Version.new("3.4"), "~> 28.0"],
                ]
                new_constraint = nil
                begin
                  if min_ruby && !min_ruby.empty?
                    v = Gem::Version.new(min_ruby.split(".")[0, 2].join("."))
                    version_map.reverse_each do |min, req|
                      if v >= min
                        new_constraint = req
                        break
                      end
                    end
                  end
                rescue StandardError
                  # leave nil
                end
                if new_constraint
                  content.gsub(/^gem\s+"rubocop-lts",\s*"[^"]+".*$/) do |_line|
                    # Do not preserve whatever tail was there before
                    %(gem "rubocop-lts", "#{new_constraint}")
                  end
                else
                  content
                end
              end
            else
              helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
            end
          end

          # 5) spec/spec_helper.rb (no create)
          dest_spec_helper = File.join(project_root, "spec/spec_helper.rb")
          if File.file?(dest_spec_helper)
            old = File.read(dest_spec_helper)
            if old.include?('require "kettle/dev"') || old.include?("require 'kettle/dev'")
              replacement = %(require "#{entrypoint_require}")
              new_content = old.gsub(/require\s+["']kettle\/dev["']/, replacement)
              if new_content != old
                if helpers.ask("Replace require \"kettle/dev\" in spec/spec_helper.rb with #{replacement}?", true)
                  helpers.write_file(dest_spec_helper, new_content)
                  puts "Updated require in spec/spec_helper.rb"
                else
                  puts "Skipped modifying spec/spec_helper.rb"
                end
              end
            end
          end

          # 6) .env.local special case: never read or touch .env.local from source; only copy .env.local.example to .env.local.example
          begin
            envlocal_src = File.join(gem_checkout_root, ".env.local.example")
            envlocal_dest = File.join(project_root, ".env.local.example")
            if File.exist?(envlocal_src)
              helpers.copy_file_with_prompt(envlocal_src, envlocal_dest, allow_create: true, allow_replace: true)
            end
          rescue StandardError => e
            puts "WARNING: Skipped .env.local example copy due to #{e.class}: #{e.message}"
          end

          # 7) Root and other files
          # 7a) Special-case: gemspec example must be renamed to destination gem's name
          begin
            # Prefer the .example variant when present
            gemspec_template_src = helpers.prefer_example(File.join(gem_checkout_root, "kettle-dev.gemspec"))
            if File.exist?(gemspec_template_src)
              dest_gemspec = if gem_name && !gem_name.to_s.empty?
                File.join(project_root, "#{gem_name}.gemspec")
              else
                # Fallback rules:
                # 1) Prefer any existing gemspec in the destination project
                existing = Dir.glob(File.join(project_root, "*.gemspec")).sort.first
                if existing
                  existing
                else
                  # 2) If none, use the example file's name with ".example" removed
                  fallback_name = File.basename(gemspec_template_src).sub(/\.example\z/, "")
                  File.join(project_root, fallback_name)
                end
              end
              helpers.copy_file_with_prompt(gemspec_template_src, dest_gemspec, allow_create: true, allow_replace: true) do |content|
                helpers.apply_common_replacements(
                  content,
                  org: forge_org,
                  gem_name: gem_name,
                  namespace: namespace,
                  namespace_shield: namespace_shield,
                  gem_shield: gem_shield,
                )
              end
            end
          rescue StandardError
            # Do not fail the entire template task if gemspec copy has issues
          end

          files_to_copy = %w[
            .envrc
            .gitignore
            .gitlab-ci.yml
            .rspec
            .rubocop.yml
            .simplecov
            .tool-versions
            .yard_gfm_support.rb
            .yardopts
            .opencollective.yml
            Appraisal.root.gemfile
            Appraisals
            CHANGELOG.md
            CITATION.cff
            CODE_OF_CONDUCT.md
            CONTRIBUTING.md
            FUNDING.md
            Gemfile
            Rakefile
            README.md
            RUBOCOP.md
            SECURITY.md
            .junie/guidelines.md
            .junie/guidelines-rbs.md
          ]

          # Snapshot existing README content once (for H1 prefix preservation after write)
          existing_readme_before = begin
            path = File.join(project_root, "README.md")
            File.file?(path) ? File.read(path) : nil
          rescue StandardError
            nil
          end

          files_to_copy.each do |rel|
            src = helpers.prefer_example(File.join(gem_checkout_root, rel))
            dest = File.join(project_root, rel)
            next unless File.exist?(src)
            if File.basename(rel) == "README.md"
              # Precompute destination README H1 prefix (emoji(s) or first grapheme) before any overwrite occurs
              prev_readme = File.exist?(dest) ? File.read(dest) : nil
              begin
                if prev_readme
                  first_h1_prev = prev_readme.lines.find { |ln| ln =~ /^#\s+/ }
                  if first_h1_prev
                    require "kettle/emoji_regex"
                    emoji_re = Kettle::EmojiRegex::REGEX
                    tail = first_h1_prev.sub(/^#\s+/, "")
                    # Extract consecutive leading emoji graphemes
                    out = +""
                    s = tail.dup
                    loop do
                      cluster = s[/\A\X/u]
                      break if cluster.nil? || cluster.empty?
                      if emoji_re.match?(cluster)
                        out << cluster
                        s = s[cluster.length..-1].to_s
                      else
                        break
                      end
                    end
                    if !out.empty?
                      out
                    else
                      # Fallback to first grapheme
                      tail[/\A\X/u]
                    end
                  end
                end
              rescue StandardError
                # ignore, leave dest_preserve_prefix as nil
              end

              helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) do |content|
                # 1) Do token replacements on the template content (org/gem/namespace/shields)
                c = helpers.apply_common_replacements(
                  content,
                  org: forge_org,
                  gem_name: gem_name,
                  namespace: namespace,
                  namespace_shield: namespace_shield,
                  gem_shield: gem_shield,
                )

                # 2) Merge specific sections from destination README, if present
                begin
                  dest_existing = prev_readme

                  # Parse Markdown headings while ignoring fenced code blocks (``` ... ```)
                  build_sections = lambda do |md|
                    return {lines: [], sections: [], line_count: 0} unless md
                    lines = md.split("\n", -1)
                    line_count = lines.length

                    sections = []
                    in_code = false
                    fence_re = /^\s*```/ # start or end of fenced block

                    lines.each_with_index do |ln, i|
                      if ln =~ fence_re
                        in_code = !in_code
                        next
                      end
                      next if in_code
                      if (m = ln.match(/^(#+)\s+.+/))
                        level = m[1].length
                        title = ln.sub(/^#+\s+/, "")
                        base = title.sub(/\A[^\p{Alnum}]+/u, "").strip.downcase
                        sections << {start: i, level: level, heading: ln, base: base}
                      end
                    end

                    # Compute stop indices based on next heading of same or higher level
                    sections.each_with_index do |sec, i|
                      j = i + 1
                      stop = line_count - 1
                      while j < sections.length
                        if sections[j][:level] <= sec[:level]
                          stop = sections[j][:start] - 1
                          break
                        end
                        j += 1
                      end
                      sec[:stop_to_next_any] = stop
                      body_lines_any = lines[(sec[:start] + 1)..stop] || []
                      sec[:body_to_next_any] = body_lines_any.join("\n")
                    end

                    {lines: lines, sections: sections, line_count: line_count}
                  end

                  # Helper: Compute the branch end (inclusive) for a section at index i
                  branch_end_index = lambda do |sections_arr, i, total_lines|
                    current = sections_arr[i]
                    j = i + 1
                    while j < sections_arr.length
                      return sections_arr[j][:start] - 1 if sections_arr[j][:level] <= current[:level]
                      j += 1
                    end
                    total_lines - 1
                  end

                  src_parsed = build_sections.call(c)
                  dest_parsed = build_sections.call(dest_existing)

                  # Build lookup for destination sections by base title, using full branch body (to next heading of same or higher level)
                  dest_lookup = {}
                  if dest_parsed && dest_parsed[:sections]
                    dest_parsed[:sections].each_with_index do |s, idx|
                      base = s[:base]
                      # Only set once (first occurrence wins)
                      next if dest_lookup.key?(base)
                      be = branch_end_index.call(dest_parsed[:sections], idx, dest_parsed[:line_count])
                      body_lines = dest_parsed[:lines][(s[:start] + 1)..be] || []
                      dest_lookup[base] = {body_branch: body_lines.join("\n"), level: s[:level]}
                    end
                  end

                  # Build targets to merge: existing curated list plus any NOTE sections at any level
                  note_bases = []
                  if src_parsed && src_parsed[:sections]
                    note_bases = src_parsed[:sections]
                      .select { |s| s[:heading] =~ /^#+\s+note:.*/i }
                      .map { |s| s[:base] }
                  end
                  targets = ["synopsis", "configuration", "basic usage"] + note_bases

                  # Replace matching sections in src using full branch ranges
                  if src_parsed && src_parsed[:sections] && !src_parsed[:sections].empty?
                    lines = src_parsed[:lines].dup
                    # Iterate in reverse to keep indices valid
                    src_parsed[:sections].reverse_each.with_index do |sec, rev_i|
                      next unless targets.include?(sec[:base])
                      # Determine branch range in src for this section
                      # rev_i is reverse index; compute forward index
                      i = src_parsed[:sections].length - 1 - rev_i
                      src_end = branch_end_index.call(src_parsed[:sections], i, src_parsed[:line_count])
                      dest_entry = dest_lookup[sec[:base]]
                      new_body = dest_entry ? dest_entry[:body_branch] : "\n\n"
                      new_block = [sec[:heading], new_body].join("\n")
                      range_start = sec[:start]
                      range_end = src_end
                      # Remove old range
                      lines.slice!(range_start..range_end)
                      # Insert new block (split preserves potential empty tail)
                      insert_lines = new_block.split("\n", -1)
                      lines.insert(range_start, *insert_lines)
                    end
                    c = lines.join("\n")
                  end

                  # 3) Preserve entire H1 line from destination README, if any
                  begin
                    if dest_existing
                      dest_h1 = dest_existing.lines.find { |ln| ln =~ /^#\s+/ }
                      if dest_h1
                        lines_new = c.split("\n", -1)
                        src_h1_idx = lines_new.index { |ln| ln =~ /^#\s+/ }
                        if src_h1_idx
                          # Replace the entire H1 line with the destination's H1 exactly
                          lines_new[src_h1_idx] = dest_h1.chomp
                          c = lines_new.join("\n")
                        end
                      end
                    end
                  rescue StandardError
                    # ignore H1 preservation errors
                  end
                rescue StandardError
                  # Best effort; if anything fails, keep c as-is
                end

                c
              end
            elsif ["CHANGELOG.md", "CITATION.cff", "CONTRIBUTING.md", ".opencollective.yml", "FUNDING.md", ".junie/guidelines.md"].include?(rel)
              helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) do |content|
                c = helpers.apply_common_replacements(
                  content,
                  org: ((File.basename(rel) == ".opencollective.yml" || File.basename(rel) == "FUNDING.md") ? funding_org : forge_org),
                  gem_name: gem_name,
                  namespace: namespace,
                  namespace_shield: namespace_shield,
                  gem_shield: gem_shield,
                )
                # Retain whitespace everywhere, except collapse repeated whitespace in CHANGELOG release headers only
                if File.basename(rel) == "CHANGELOG.md"
                  lines = c.split("\n", -1)
                  lines.map! do |ln|
                    if ln =~ /^##\s+\[.*\]/
                      ln.gsub(/[ \t]+/, " ")
                    else
                      ln
                    end
                  end
                  c = lines.join("\n")
                end
                c
              end
            else
              helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
            end
          end

          # Post-process README H1 preservation using snapshot (replace entire H1 line)
          begin
            if existing_readme_before
              readme_path = File.join(project_root, "README.md")
              if File.file?(readme_path)
                prev = existing_readme_before
                newc = File.read(readme_path)
                prev_h1 = prev.lines.find { |ln| ln =~ /^#\s+/ }
                lines = newc.split("\n", -1)
                cur_h1_idx = lines.index { |ln| ln =~ /^#\s+/ }
                if prev_h1 && cur_h1_idx
                  # Replace the entire H1 line with the previous README's H1 exactly
                  lines[cur_h1_idx] = prev_h1.chomp
                  File.open(readme_path, "w") { |f| f.write(lines.join("\n")) }
                end
              end
            end
          rescue StandardError
            # ignore post-processing errors
          end

          # 7b) certs/pboling.pem
          begin
            cert_src = File.join(gem_checkout_root, "certs", "pboling.pem")
            cert_dest = File.join(project_root, "certs", "pboling.pem")
            if File.exist?(cert_src)
              helpers.copy_file_with_prompt(cert_src, cert_dest, allow_create: true, allow_replace: true)
            end
          rescue StandardError => e
            puts "WARNING: Skipped copying certs/pboling.pem due to #{e.class}: #{e.message}"
          end

          # After creating or replacing .envrc or .env.local.example, require review and exit unless allowed
          begin
            envrc_path = File.join(project_root, ".envrc")
            envlocal_example_path = File.join(project_root, ".env.local.example")
            changed_env_files = []
            changed_env_files << envrc_path if helpers.modified_by_template?(envrc_path)
            changed_env_files << envlocal_example_path if helpers.modified_by_template?(envlocal_example_path)
            if !changed_env_files.empty?
              if ENV.fetch("allowed", "").to_s =~ /\A(1|true|y|yes)\z/i
                puts "Detected updates to #{changed_env_files.map { |p| File.basename(p) }.join(" and ")}. Proceeding because allowed=true."
              else
                puts
                puts "IMPORTANT: The following environment-related files were created/updated:"
                changed_env_files.each { |p| puts "  - #{p}" }
                puts
                puts "Please review these files. If .envrc changed, run:"
                puts "  direnv allow"
                puts
                puts "After that, re-run to resume:"
                puts "  bundle exec rake kettle:dev:template allowed=true"
                puts "  # or to run the full install afterwards:"
                puts "  bundle exec rake kettle:dev:install allowed=true"
                task_abort("Aborting: review of environment files required before continuing.")
              end
            end
          rescue StandardError => e
            # Do not swallow intentional task aborts
            raise if e.is_a?(Kettle::Dev::Error)
            puts "WARNING: Could not determine env file changes: #{e.class}: #{e.message}"
          end

          # Handle .git-hooks files (see original rake task for details)
          source_hooks_dir = File.join(gem_checkout_root, ".git-hooks")
          if Dir.exist?(source_hooks_dir)
            # Honor ENV["only"]: skip entire .git-hooks handling unless patterns include .git-hooks
            begin
              only_raw = ENV["only"].to_s
              if !only_raw.empty?
                patterns = only_raw.split(",").map { |s| s.strip }.reject(&:empty?)
                if !patterns.empty?
                  proj = helpers.project_root.to_s
                  target_dir = File.join(proj, ".git-hooks")
                  # Determine if any pattern would match either the directory itself (with /** semantics) or files within it
                  matches = patterns.any? do |pat|
                    if pat.end_with?("/**")
                      base = pat[0..-4]
                      base == ".git-hooks" || base == target_dir.sub(/^#{Regexp.escape(proj)}\/?/, "")
                    else
                      # Check for explicit .git-hooks or subpaths
                      File.fnmatch?(pat, ".git-hooks", File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH) ||
                        File.fnmatch?(pat, ".git-hooks/*", File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
                    end
                  end
                  unless matches
                    # No interest in .git-hooks => skip prompts and copies for hooks entirely
                    # Note: we intentionally do not record template_results for hooks
                    return
                  end
                end
              end
            rescue StandardError
              # If filter parsing fails, proceed as before
            end
            goalie_src = File.join(source_hooks_dir, "commit-subjects-goalie.txt")
            footer_src = File.join(source_hooks_dir, "footer-template.erb.txt")
            hook_ruby_src = File.join(source_hooks_dir, "commit-msg")
            hook_sh_src = File.join(source_hooks_dir, "prepare-commit-msg")

            # First: templates (.txt) — ask local/global/skip
            if File.file?(goalie_src) && File.file?(footer_src)
              puts
              puts "Git hooks templates found:"
              puts "  - #{goalie_src}"
              puts "  - #{footer_src}"
              puts
              puts "About these files:"
              puts "- commit-subjects-goalie.txt:"
              puts "  Lists commit subject prefixes to look for; if a commit subject starts with any listed prefix,"
              puts "  kettle-commit-msg will append a footer to the commit message (when GIT_HOOK_FOOTER_APPEND=true)."
              puts "  Defaults include release prep (🔖 Prepare release v) and checksum commits (🔒️ Checksums for v)."
              puts "- footer-template.erb.txt:"
              puts "  ERB template rendered to produce the footer. You can customize its contents and variables."
              puts
              puts "Where would you like to install these two templates?"
              puts "  [l] Local to this project (#{File.join(project_root, ".git-hooks")})"
              puts "  [g] Global for this user (#{File.join(ENV["HOME"], ".git-hooks")})"
              puts "  [s] Skip copying"
              # Allow non-interactive selection via environment
              # Precedence: CLI switch (hook_templates) > KETTLE_DEV_HOOK_TEMPLATES > prompt
              env_choice = ENV["hook_templates"]
              env_choice = ENV["KETTLE_DEV_HOOK_TEMPLATES"] if env_choice.nil? || env_choice.strip.empty?
              choice = env_choice&.strip
              unless choice && !choice.empty?
                print("Choose (l/g/s) [l]: ")
                choice = Kettle::Dev::InputAdapter.gets&.strip
              end
              choice = "l" if choice.nil? || choice.empty?
              dest_dir = case choice.downcase
              when "g", "global" then File.join(ENV["HOME"], ".git-hooks")
              when "s", "skip" then nil
              else File.join(project_root, ".git-hooks")
              end

              if dest_dir
                FileUtils.mkdir_p(dest_dir)
                [[goalie_src, "commit-subjects-goalie.txt"], [footer_src, "footer-template.erb.txt"]].each do |src, base|
                  dest = File.join(dest_dir, base)
                  # Allow create/replace prompts for these files (question applies to them)
                  helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
                  # Ensure readable (0644). These are data/templates, not executables.
                  begin
                    File.chmod(0o644, dest) if File.exist?(dest)
                  rescue StandardError
                    # ignore permission issues
                  end
                end
              else
                puts "Skipping copy of .git-hooks templates."
              end
            end

            # Second: hook scripts — copy only to local project; prompt only on overwrite
            hook_dests = [File.join(project_root, ".git-hooks")]
            hook_pairs = [[hook_ruby_src, "commit-msg", 0o755], [hook_sh_src, "prepare-commit-msg", 0o755]]
            hook_pairs.each do |src, base, mode|
              next unless File.file?(src)
              hook_dests.each do |dstdir|
                begin
                  FileUtils.mkdir_p(dstdir)
                  dest = File.join(dstdir, base)
                  # Create without prompt if missing; if exists, ask to replace
                  if File.exist?(dest)
                    if helpers.ask("Overwrite existing #{dest}?", true)
                      content = File.read(src)
                      helpers.write_file(dest, content)
                      begin
                        File.chmod(mode, dest)
                      rescue StandardError
                        # ignore permission issues
                      end
                      puts "Replaced #{dest}"
                    else
                      puts "Kept existing #{dest}"
                    end
                  else
                    content = File.read(src)
                    helpers.write_file(dest, content)
                    begin
                      File.chmod(mode, dest)
                    rescue StandardError
                      # ignore permission issues
                    end
                    puts "Installed #{dest}"
                  end
                rescue StandardError => e
                  puts "WARNING: Could not install hook #{base} to #{dstdir}: #{e.class}: #{e.message}"
                end
              end
            end
          end

          # Done
          nil
        end
      end
    end
  end
end
