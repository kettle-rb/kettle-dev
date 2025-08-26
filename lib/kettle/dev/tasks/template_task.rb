# frozen_string_literal: true

require "kettle/dev/exit_adapter"

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
          gh_org = meta[:gh_org]
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
                  c = c.gsub(/^open_collective:\s+.*$/i) { |line| gh_org ? "open_collective: #{gh_org}" : line }
                  if gem_name && !gem_name.empty?
                    c = c.gsub(/^tidelift:\s+.*$/i, "tidelift: rubygems/#{gem_name}")
                  end
                  # Also apply common replacements for org/gem/namespace/shields
                  helpers.apply_common_replacements(
                    c,
                    gh_org: gh_org,
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
                    gh_org: gh_org,
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
          [%w[coverage.gemfile], %w[documentation.gemfile], %w[style.gemfile]].each do |base|
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

          # 6) .env.local special case: never overwrite project .env.local; copy template as .env.local.example
          begin
            envlocal_src = helpers.prefer_example(File.join(gem_checkout_root, ".env.local"))
            envlocal_dest = File.join(project_root, ".env.local.example")
            if File.exist?(envlocal_src)
              helpers.copy_file_with_prompt(envlocal_src, envlocal_dest, allow_create: true, allow_replace: true)
            end
          rescue StandardError => e
            puts "WARNING: Skipped .env.local example copy due to #{e.class}: #{e.message}"
          end

          # 7) Root and other files
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
            Gemfile
            Rakefile
            README.md
            RUBOCOP.md
            SECURITY.md
            .junie/guidelines.md
            .junie/guidelines-rbs.md
          ]

          files_to_copy.each do |rel|
            src = helpers.prefer_example(File.join(gem_checkout_root, rel))
            dest = File.join(project_root, rel)
            next unless File.exist?(src)
            if File.basename(rel) == "README.md"
              helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) do |content|
                # 1) Do token replacements on the template content (org/gem/namespace/shields)
                c = helpers.apply_common_replacements(
                  content,
                  gh_org: gh_org,
                  gem_name: gem_name,
                  namespace: namespace,
                  namespace_shield: namespace_shield,
                  gem_shield: gem_shield,
                )

                # 2) Merge specific sections from destination README, if present
                begin
                  dest_existing = File.exist?(dest) ? File.read(dest) : nil

                  # Helper to parse markdown sections at any heading level (#, ##, ###, ...)
                  parse_sections = lambda do |md|
                    sections = []
                    return sections unless md
                    lines = md.split("\n", -1) # keep trailing empty lines
                    indices = []
                    lines.each_with_index do |ln, i|
                      indices << i if ln =~ /^#+\s+.+/
                    end
                    indices << lines.length
                    indices.each_cons(2) do |start_i, nxt|
                      heading = lines[start_i]
                      body_lines = lines[(start_i + 1)...nxt] || []
                      title = heading.sub(/^#+\s+/, "")
                      # Normalize by removing leading emoji/non-alnum and extra spaces
                      base = title.sub(/\A[^\p{Alnum}]+/u, "").strip.downcase
                      sections << {start: start_i, stop: nxt - 1, heading: heading, body: body_lines.join("\n"), base: base}
                    end
                    {lines: lines, sections: sections}
                  end

                  # Parse src (c) and dest
                  src_parsed = parse_sections.call(c)
                  dest_parsed = parse_sections.call(dest_existing)

                  # Build lookup for destination sections by base title
                  dest_lookup = {}
                  if dest_parsed && dest_parsed[:sections]
                    dest_parsed[:sections].each do |s|
                      dest_lookup[s[:base]] = s[:body]
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

                  # Replace matching sections in src
                  if src_parsed && src_parsed[:sections] && !src_parsed[:sections].empty?
                    lines = src_parsed[:lines].dup
                    # Iterate over src sections; when base is in targets, rewrite its body
                    src_parsed[:sections].reverse_each do |sec|
                      next unless targets.include?(sec[:base])
                      new_body = dest_lookup.fetch(sec[:base], "\n\n")
                      new_block = [sec[:heading], new_body].join("\n")
                      # Replace the range from start+0 to stop with new_block lines
                      range_start = sec[:start]
                      range_end = sec[:stop]
                      # Remove old range
                      lines.slice!(range_start..range_end)
                      # Insert new block (split preserves potential empty tail)
                      insert_lines = new_block.split("\n", -1)
                      lines.insert(range_start, *insert_lines)
                    end
                    c = lines.join("\n")
                  end

                  # 3) Preserve first H1 emojis from destination README, if any
                  begin
                    emoji_re = Kettle::EmojiRegex::REGEX

                    dest_emojis = nil
                    if dest_existing
                      first_h1_dest = dest_existing.lines.find { |ln| ln =~ /^#\s+/ }
                      if first_h1_dest
                        after = first_h1_dest.sub(/^#\s+/, "")
                        emojis = +""
                        while after =~ /\A#{emoji_re.source}/u
                          # Capture the entire grapheme cluster for the emoji (handles VS16/ZWJ sequences)
                          cluster = after[/\A\X/u]
                          emojis << cluster
                          after = after[cluster.length..-1].to_s
                        end
                        dest_emojis = emojis unless emojis.empty?
                      end
                    end

                    if dest_emojis && !dest_emojis.empty?
                      lines_new = c.split("\n", -1)
                      idx = lines_new.index { |ln| ln =~ /^#\s+/ }
                      if idx
                        rest = lines_new[idx].sub(/^#\s+/, "")
                        # Remove any leading emojis from the H1 by peeling full grapheme clusters
                        rest_wo_emoji = begin
                          tmp = rest.dup
                          while tmp =~ /\A#{emoji_re.source}/u
                            cluster = tmp[/\A\X/u]
                            tmp = tmp[cluster.length..-1].to_s
                          end
                          tmp.sub(/\A\s+/, "")
                        end
                        lines_new[idx] = ["#", dest_emojis, rest_wo_emoji].join(" ").gsub(/\s+/, " ").sub(/^#\s+/, "# ")
                        c = lines_new.join("\n")
                      end
                    end
                  rescue StandardError
                    # ignore emoji preservation errors
                  end
                rescue StandardError
                  # Best effort; if anything fails, keep c as-is
                end

                c
              end
            elsif ["CHANGELOG.md", "CITATION.cff", "CONTRIBUTING.md", ".opencollective.yml", ".junie/guidelines.md"].include?(rel)
              helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) do |content|
                helpers.apply_common_replacements(
                  content,
                  gh_org: gh_org,
                  gem_name: gem_name,
                  namespace: namespace,
                  namespace_shield: namespace_shield,
                  gem_shield: gem_shield,
                )
              end
            else
              helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
            end
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
              print("Choose (l/g/s) [l]: ")
              choice = $stdin.gets&.strip
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
