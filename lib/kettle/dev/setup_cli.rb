# frozen_string_literal: true

require "fileutils"
require "shellwords"
require "open3"
require "optparse"

module Kettle
  module Dev
    # SetupCLI bootstraps a host gem repository to use kettle-dev tooling.
    # It performs prechecks, syncs development dependencies, ensures bin/setup and
    # Rakefile templates, runs setup tasks, and invokes kettle:dev:install.
    #
    # Usage:
    #   Kettle::Dev::SetupCLI.new(ARGV).run!
    #
    # Options are parsed from argv and passed through to the rake task as
    # key=value pairs (e.g., --force => force=true).
    class SetupCLI
      # @param argv [Array<String>] CLI arguments
      def initialize(argv)
        @argv = argv
        @passthrough = []
        @options = {}
        parse!
      end

      # Execute the full setup workflow.
      # @return [void]
      def run!
        say("Starting kettle-dev setup…")
        prechecks!
        ensure_dev_deps!
        ensure_gemfile_from_example!
        ensure_modular_gemfiles!
        ensure_bin_setup!
        ensure_rakefile!
        run_bin_setup!
        run_bundle_binstubs!
        commit_bootstrap_changes!
        run_kettle_install!
        say("kettle-dev setup complete.")
      end

      private

      def debug(msg)
        return if ENV.fetch("DEBUG", "false").casecmp("true").nonzero?
        $stderr.puts("[kettle-dev-setup] DEBUG: #{msg}")
      end

      # Attempt to derive a funding organization from the git remote 'origin' when
      # not explicitly provided via env or .opencollective.yml.
      # This is a soft helper that only sets ENV["FUNDING_ORG"] if a plausible
      # GitHub org can be parsed from the origin URL.
      # @return [void]
      def derive_funding_org_from_git_if_missing!
        # Respect explicit bypass
        env_val = ENV["FUNDING_ORG"]
        return if env_val && env_val.to_s.strip.casecmp("false").zero?

        # If already provided via env, do nothing
        return if ENV["FUNDING_ORG"].to_s.strip != ""
        return if ENV["OPENCOLLECTIVE_HANDLE"].to_s.strip != ""

        # If project provides an .opencollective.yml with org, do nothing
        begin
          oc_path = File.join(Dir.pwd, ".opencollective.yml")
          if File.file?(oc_path)
            txt = File.read(oc_path)
            return if txt =~ /\borg:\s*([\w\-]+)/i
          end
        rescue StandardError => e
          debug("Reading .opencollective.yml failed: #{e.class}: #{e.message}")
        end

        # Attempt to get origin URL and parse GitHub org
        begin
          ga = Kettle::Dev::GitAdapter.new
          origin_url = nil
          origin_url = ga.remote_url("origin") if ga.respond_to?(:remote_url)
          if origin_url.nil? && ga.respond_to?(:remotes_with_urls)
            begin
              urls = ga.remotes_with_urls
              origin_url = urls["origin"] if urls
            rescue StandardError => e
              # graceful fallback if adapter backend errs; keep silent behavior
              debug("remotes_with_urls failed: #{e.class}: #{e.message}")
            end
          end
          origin_url = origin_url.to_s.strip
          if (m = origin_url.match(%r{github\.com[/:]([^/]+)/}i))
            org = m[1].to_s
            if !org.empty?
              ENV["FUNDING_ORG"] = org
              debug("Derived FUNDING_ORG from git origin: #{org}")
            end
          end
        rescue StandardError => e
          # Be silent; this is a best-effort and shouldn't fail setup
          debug("Could not derive funding org from git: #{e.class}: #{e.message}")
        end
      end

      def parse!
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: kettle-dev-setup [options]"
          opts.on("--allowed=VAL", "Pass through to kettle:dev:install") { |v| @passthrough << "allowed=#{v}" }
          opts.on("--force", "Pass through to kettle:dev:install") do
            # Ensure in-process helpers (TemplateHelpers.ask) also see force mode
            ENV["force"] = "true"
            @passthrough << "force=true"
          end
          opts.on("--hook_templates=VAL", "Pass through to kettle:dev:install") { |v| @passthrough << "hook_templates=#{v}" }
          opts.on("--only=VAL", "Pass through to kettle:dev:install") { |v| @passthrough << "only=#{v}" }
          opts.on("-h", "--help", "Show help") do
            puts opts
            Kettle::Dev::ExitAdapter.exit(0)
          end
        end
        begin
          parser.parse!(@argv)
        rescue OptionParser::ParseError => e
          warn("[kettle-dev-setup] #{e.class}: #{e.message}")
          puts parser
          Kettle::Dev::ExitAdapter.exit(2)
        end
        @passthrough.concat(@argv)
      end

      def say(msg)
        puts "[kettle-dev-setup] #{msg}"
      end

      def abort!(msg)
        Kettle::Dev::ExitAdapter.abort("[kettle-dev-setup] ERROR: #{msg}")
      end

      def sh!(cmd, env: {})
        say("exec: #{cmd}")
        stdout_str, stderr_str, status = Open3.capture3(env, cmd)
        $stdout.print(stdout_str) unless stdout_str.empty?
        $stderr.print(stderr_str) unless stderr_str.empty?
        abort!("Command failed: #{cmd}") unless status.success?
      end

      # 1. Prechecks
      def prechecks!
        abort!("Not inside a git repository (missing .git).") unless Dir.exist?(".git")

        # Ensure clean working tree
        begin
          if defined?(Kettle::Dev::GitAdapter)
            dirty = !Kettle::Dev::GitAdapter.new.clean?
          else
            stdout, _stderr, _status = Open3.capture3("git status --porcelain")
            dirty = !stdout.strip.empty?
          end
          abort!("Git working tree is not clean. Please commit/stash changes and try again.") if dirty
        rescue StandardError
          stdout, _stderr, _status = Open3.capture3("git status --porcelain")
          abort!("Git working tree is not clean. Please commit/stash changes and try again.") unless stdout.strip.empty?
        end

        # gemspec
        gemspecs = Dir["*.gemspec"]
        abort!("No gemspec found in current directory.") if gemspecs.empty?
        @gemspec_path = gemspecs.first

        # Gemfile
        abort!("No Gemfile found; bundler is required.") unless File.exist?("Gemfile")

        # Seed FUNDING_ORG from git remote origin org when not provided elsewhere
        derive_funding_org_from_git_if_missing!
      end

      # 3. Sync dev dependencies from this gem's example gemspec into target gemspec
      def ensure_dev_deps!
        source_example = installed_path("kettle-dev.gemspec.example")
        abort!("Internal error: kettle-dev.gemspec.example not found within the installed gem.") unless source_example && File.exist?(source_example)

        example = File.read(source_example)
        example = example.gsub("{KETTLE|DEV|GEM}", "kettle-dev")

        wanted_lines = example.each_line.map(&:rstrip).select { |line| line =~ /add_development_dependency\s*\(?/ }
        return if wanted_lines.empty?

        target = File.read(@gemspec_path)

        # Build gem=>desired line map
        wanted = {}
        wanted_lines.each do |line|
          if (m = line.match(/add_development_dependency\s*\(?\s*["']([^"']+)["']/))
            wanted[m[1]] = line
          end
        end

        modified = target.dup
        wanted.each do |gem_name, desired_line|
          lines = modified.lines
          found = false
          lines.map! do |ln|
            if ln =~ /add_development_dependency\s*\(?\s*["']#{Regexp.escape(gem_name)}["']/
              found = true
              indent = ln[/^\s*/] || ""
              "#{indent}#{desired_line.strip}\n"
            else
              ln
            end
          end
          modified = lines.join

          next if found

          if (idx = modified.rindex(/\nend\s*\z/))
            before = modified[0...idx]
            after = modified[idx..-1]
            insertion = "\n  #{desired_line.strip}\n"
            modified = before + insertion + after
          else
            modified << "\n#{desired_line}\n"
          end
        end

        if modified != target
          File.write(@gemspec_path, modified)
          say("Updated development dependencies in #{@gemspec_path}.")
        else
          say("Development dependencies already up to date.")
        end
      end

      # 4. Ensure bin/setup present (copy from gem if missing)
      def ensure_bin_setup!
        target = File.join("bin", "setup")
        return say("bin/setup present.") if File.exist?(target)

        source = installed_path(File.join("bin", "setup"))
        abort!("Internal error: source bin/setup not found within installed gem.") unless source && File.exist?(source)
        FileUtils.mkdir_p("bin")
        FileUtils.cp(source, target)
        FileUtils.chmod("+x", target)
        say("Copied bin/setup.")
      end

      # 3b. Ensure Gemfile contains required lines from example without duplicating directives
      #    - Copies source, git_source, gemspec, and eval_gemfile lines that are missing
      #    - Idempotent (running multiple times does not duplicate entries)
      def ensure_gemfile_from_example!
        source_path = installed_path("Gemfile.example")
        abort!("Internal error: Gemfile.example not found within installed gem.") unless source_path && File.exist?(source_path)

        example = File.read(source_path)
        target_path = "Gemfile"
        target = File.exist?(target_path) ? File.read(target_path) : ""

        # Extract interesting lines from example
        ex_sources = []
        ex_git_sources = [] # names (e.g., :github)
        ex_git_source_lines = {}
        ex_has_gemspec = false
        ex_eval_paths = []

        example.each_line do |ln|
          s = ln.strip
          next if s.empty?
          if s.start_with?("source ")
            ex_sources << ln.rstrip
          elsif (m = s.match(/^git_source\(\s*:(\w+)\s*\)/))
            name = m[1]
            ex_git_sources << name
            ex_git_source_lines[name] = ln.rstrip
          elsif s.start_with?("gemspec")
            ex_has_gemspec = true
          elsif (m = s.match(/^eval_gemfile\s+["']([^"']+)["']/))
            ex_eval_paths << m[1]
          end
        end

        # Scan target for presence
        tg_sources = target.each_line.map(&:rstrip).select { |l| l.strip.start_with?("source ") }
        tg_git_sources = {}
        target.each_line do |ln|
          if (m = ln.strip.match(/^git_source\(\s*:(\w+)\s*\)/))
            tg_git_sources[m[1]] = true
          end
        end
        tg_has_gemspec = !!target.each_line.find { |l| l.strip.start_with?("gemspec") }
        tg_eval_paths = target.each_line.map do |ln|
          if (m = ln.strip.match(/^eval_gemfile\s+["']([^"']+)["']/))
            m[1]
          end
        end.compact

        additions = []
        # Add missing sources (exact line match)
        ex_sources.each do |src_line|
          additions << src_line unless tg_sources.include?(src_line)
        end
        # Add missing git_source by name
        ex_git_sources.each do |name|
          additions << ex_git_source_lines[name] unless tg_git_sources[name]
        end
        # Add gemspec if example has it and target lacks it
        additions << "gemspec" if ex_has_gemspec && !tg_has_gemspec
        # Add missing eval_gemfile paths (recreate the exact example line when possible)
        ex_eval_paths.each do |path|
          next if tg_eval_paths.include?(path)
          additions << "eval_gemfile \"#{path}\""
        end

        return say("Gemfile already contains required entries from example.") if additions.empty?

        # Ensure file ends with a newline
        target << "\n" unless target.end_with?("\n") || target.empty?
        new_content = target + additions.join("\n") + "\n"
        File.write(target_path, new_content)
        say("Updated Gemfile with entries from Gemfile.example (added #{additions.size}).")
      end

      # 3c. Ensure gemfiles/modular/* are present (copied like template task)
      def ensure_modular_gemfiles!
        helpers = Kettle::Dev::TemplateHelpers
        project_root = helpers.project_root
        gem_checkout_root = helpers.gem_checkout_root
        # Gather min_ruby for style.gemfile adjustments
        min_ruby = begin
          md = helpers.gemspec_metadata(project_root)
          md[:min_ruby]
        rescue StandardError
          nil
        end
        Kettle::Dev::ModularGemfiles.sync!(
          helpers: helpers,
          project_root: project_root,
          gem_checkout_root: gem_checkout_root,
          min_ruby: min_ruby,
        )
      end

      # 5. Ensure Rakefile matches example (replace or create)
      def ensure_rakefile!
        source = installed_path("Rakefile.example")
        abort!("Internal error: Rakefile.example not found within installed gem.") unless source && File.exist?(source)

        content = File.read(source)
        if File.exist?("Rakefile")
          say("Replacing existing Rakefile with kettle-dev Rakefile.example.")
        else
          say("Creating Rakefile from kettle-dev Rakefile.example.")
        end
        File.write("Rakefile", content)
      end

      # 6. Run bin/setup
      def run_bin_setup!
        sh!(Shellwords.join([File.join("bin", "setup")]))
      end

      # 7. Run bundle binstubs --all
      def run_bundle_binstubs!
        sh!("bundle exec bundle binstubs --all")
      end

      # 8. Commit template bootstrap changes if any
      def commit_bootstrap_changes!
        dirty = begin
          if defined?(Kettle::Dev::GitAdapter)
            !Kettle::Dev::GitAdapter.new.clean?
          else
            out, _st = Open3.capture2("git", "status", "--porcelain")
            !out.strip.empty?
          end
        rescue StandardError
          out, _st = Open3.capture2("git", "status", "--porcelain")
          !out.strip.empty?
        end
        unless dirty
          say("No changes to commit from template bootstrap.")
          return
        end
        sh!(Shellwords.join(["git", "add", "-A"]))
        msg = "🎨 Template bootstrap by kettle-dev-setup v#{Kettle::Dev::Version::VERSION}"
        sh!(Shellwords.join(["git", "commit", "-m", msg]))
        say("Committed template bootstrap changes.")
      end

      # 9. Invoke rake install task with passthrough
      def run_kettle_install!
        cmd = ["bin/rake", "kettle:dev:install"] + @passthrough
        sh!(Shellwords.join(cmd))
      end

      # Resolve a path to files shipped within the gem or repo checkout
      # @param rel [String]
      # @return [String, nil]
      def installed_path(rel)
        if defined?(Gem) && (spec = Gem.loaded_specs["kettle-dev"])
          path = File.join(spec.full_gem_path, rel)
          return path if File.exist?(path)
        end
        here = File.expand_path(File.join(__dir__, "..", "..", "..")) # lib/kettle/dev/ -> project root
        path = File.join(here, rel)
        return path if File.exist?(path)
        nil
      end
    end
  end
end
