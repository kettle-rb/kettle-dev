require "optparse"

module Kettle
  module Dev
    # CLI to normalize git remotes across GitHub, GitLab, and Codeberg.
    # - Defaults: origin=github, protocol=ssh, gitlab remote name=gl, codeberg remote name=cb
    # - Creates/aligns remotes and an 'all' remote that pulls only from origin, pushes to all
    #
    # Usage:
    #   kettle-dvcs [options] [ORG] [REPO]
    #
    # Options:
    #   --origin [github|gitlab|codeberg]   Choose which forge is origin (default: github)
    #   --protocol [ssh|https]              Use git+ssh or HTTPS URLs (default: ssh)
    #   --gitlab-name NAME                  Remote name for GitLab (default: gl)
    #   --codeberg-name NAME                Remote name for Codeberg (default: cb)
    #   --force                             Accept defaults; non-interactive
    #
    # Behavior:
    # - Aligns or creates remotes for github, gitlab, and codeberg with consistent org/repo and protocol
    # - Renames existing remotes to match chosen naming scheme when URLs already match
    # - Creates an "all" remote that fetches from origin only and pushes to all three forges
    # - Attempts to fetch from each forge to determine availability and updates README federation summary
    #
    # @example Non-interactive run with defaults (origin: github, protocol: ssh)
    #   kettle-dvcs --force my-org my-repo
    #
    # @example Use GitLab as origin and HTTPS URLs
    #   kettle-dvcs --origin gitlab --protocol https my-org my-repo
    class DvcsCLI
      DEFAULTS = {
        origin: "github",
        protocol: "ssh",
        gh_name: "gh",
        gl_name: "gl",
        cb_name: "cb",
        force: false,
        status: false,
      }.freeze

      # Create the CLI with argv-like arguments
      # @param argv [Array<String>] the command-line arguments (without program name)
      def initialize(argv)
        @argv = argv
        @opts = DEFAULTS.dup
      end

      # Execute the CLI command.
      # Aligns remotes, configures the `all` remote, prints remotes, attempts fetches,
      # and updates README federation status accordingly.
      # @return [Integer] exit status code (0 on success; may abort with non-zero)
      def run!
        parse!
        git = ensure_git_adapter!

        if @opts[:status]
          # Status mode: no working tree mutation beyond fetch. Don't require clean tree.
          _, _ = resolve_org_repo(git)
          names = remote_names
          branch = detect_default_branch!(git)
          say("Fetching all remotes for status...")
          # Fetch origin first to ensure origin/<branch> is up to date
          git.fetch(names[:origin]) if names[:origin]
          %i[github gitlab codeberg].each do |forge|
            r = names[forge]
            next unless r && r != names[:origin]
            git.fetch(r)
          end
          show_status!(git, names, branch)
          return 0
        end

        abort!("Working tree is not clean; commit or stash changes before proceeding") unless git.clean?

        org, repo = resolve_org_repo(git)

        names = remote_names
        urls = forge_urls(org, repo)

        # Ensure remotes exist and have desired names/urls
        ensure_remote_alignment!(git, names[:origin], urls[@opts[:origin].to_sym])
        ensure_remote_alignment!(git, names[:github], urls[:github]) if names[:github] && names[:github] != names[:origin]
        ensure_remote_alignment!(git, names[:gitlab], urls[:gitlab]) if names[:gitlab]
        ensure_remote_alignment!(git, names[:codeberg], urls[:codeberg]) if names[:codeberg]

        # Configure "all" remote: fetch only from origin, push to all three
        configure_all_remote!(git, names, urls)

        say("Remotes normalized. Origin: #{names[:origin]} (#{urls[@opts[:origin].to_sym]})")
        show_remotes!(git)
        fetch_results = attempt_fetches!(git, names)
        update_readme_federation_status!(org, repo, fetch_results)
        0
      end

      private

      # Determine default branch to compare against. Prefer 'main', fallback to 'master'.
      # Uses origin to check existence.
      def detect_default_branch!(git)
        _out, ok = git.capture(["rev-parse", "--verify", "origin/main"])
        return "main" if ok
        _out2, ok2 = git.capture(["rev-parse", "--verify", "origin/master"])
        return "master" if ok2
        # Default to main if neither verifies
        "main"
      end

      # Show ahead/behind status for each configured forge remote relative to origin/<branch>
      def show_status!(git, names, branch)
        base = "origin/#{branch}"
        say("\nRemote status relative to #{base}:")
        {
          github: names[:github],
          gitlab: names[:gitlab],
          codeberg: names[:codeberg],
        }.each do |forge, remote|
          next unless remote
          next if remote == names[:origin]
          ref = "#{remote}/#{branch}"
          out, ok = git.capture(["rev-list", "--left-right", "--count", "#{base}...#{ref}"])
          if ok && !out.strip.empty?
            parts = out.strip.split(/\s+/)
            left = parts[0].to_i
            right = parts[1].to_i
            # left = commits only in base (origin) => remote is behind by left
            # right = commits only in remote => remote is ahead by right
            if left.zero? && right.zero?
              say("  - #{forge} (#{remote}): in sync")
            else
              say("  - #{forge} (#{remote}): ahead by #{right}, behind by #{left}")
            end
          else
            say("  - #{forge} (#{remote}): no data (branch missing?)")
          end
        end
      end

      def parse!
        parser = OptionParser.new do |o|
          o.banner = "Usage: kettle-dvcs [options] [ORG] [REPO]"
          o.on("--origin NAME", %w[github gitlab codeberg], "Choose origin forge (default: github)") { |v| @opts[:origin] = v }
          o.on("--protocol NAME", %w[ssh https], "Protocol (default: ssh)") { |v| @opts[:protocol] = v }
          o.on("--github-name NAME", "Remote name for GitHub when not origin (default: gh)") { |v| @opts[:gh_name] = v }
          o.on("--gitlab-name NAME", "Remote name for GitLab (default: gl)") { |v| @opts[:gl_name] = v }
          o.on("--codeberg-name NAME", "Remote name for Codeberg (default: cb)") { |v| @opts[:cb_name] = v }
          o.on("--status", "Fetch remotes and show ahead/behind relative to origin/main") { @opts[:status] = true }
          o.on("--force", "Accept defaults; non-interactive") { @opts[:force] = true }
          o.on("-h", "--help", "Show help") {
            puts o
            exit(0)
          }
        end
        rest = parser.parse(@argv)
        @opts[:org] = rest[0] if rest[0]
        @opts[:repo] = rest[1] if rest[1]

        unless %w[github gitlab codeberg].include?(@opts[:origin])
          abort!("Invalid origin: #{@opts[:origin]}")
        end
      end

      def ensure_git_adapter!
        unless defined?(Kettle::Dev::GitAdapter)
          abort!("Kettle::Dev::GitAdapter is required and not available")
        end
        Kettle::Dev::GitAdapter.new
      end

      def remote_names
        {
          origin: "origin",
          github: (@opts[:origin] == "github") ? "origin" : @opts[:gh_name],
          gitlab: (@opts[:origin] == "gitlab") ? "origin" : @opts[:gl_name],
          codeberg: (@opts[:origin] == "codeberg") ? "origin" : @opts[:cb_name],
          all: "all",
        }
      end

      def forge_urls(org, repo)
        case @opts[:protocol]
        when "ssh"
          {
            github: "git@github.com:#{org}/#{repo}.git",
            gitlab: "git@gitlab.com:#{org}/#{repo}.git",
            codeberg: "git@codeberg.org:#{org}/#{repo}.git",
          }
        else # https
          {
            github: "https://github.com/#{org}/#{repo}.git",
            gitlab: "https://gitlab.com/#{org}/#{repo}.git",
            codeberg: "https://codeberg.org/#{org}/#{repo}.git",
          }
        end
      end

      def resolve_org_repo(git)
        org = @opts[:org]
        repo = @opts[:repo]
        if org && repo
          return [org, repo]
        end
        # Try to infer from any existing remote url
        urls = git.remotes_with_urls
        sample = urls["origin"] || urls.values.first
        if sample && sample =~ %r{[:/](?<org>[^/]+)/(?<repo>[^/]+?)(?:\.git)?$}
          org ||= Regexp.last_match(:org)
          repo ||= Regexp.last_match(:repo)
        end
        if !org || !repo
          if @opts[:force]
            abort!("ORG and REPO could not be inferred; supply them or ensure an existing remote URL")
          else
            org = prompt("Organization name", default: org)
            repo = prompt("Repository name", default: repo)
          end
        end
        [org, repo]
      end

      def prompt(label, default: nil)
        return default if @opts[:force]
        print("#{label}#{default ? " [#{default}]" : ""}: ")
        ans = $stdin.gets&.strip
        ans = nil if ans == ""
        ans || default || abort!("#{label} is required")
      end

      def ensure_remote_alignment!(git, name, url)
        # Validate URL presence to avoid passing nil to Open3
        abort!("Internal error: URL for remote '#{name}' is empty") if url.nil? || url.to_s.strip.empty?
        # We need remote management capabilities via capture to avoid adding adapter methods right now.
        # Fails if GitAdapter is not present as required.
        existing = git.remotes
        if existing.include?(name)
          current = git.remote_url(name)
          if current != url
            sh_git!(git, ["remote", "set-url", name, url])
          end
        else
          # Check if any remote already points to this URL under a different name; rename it
          urls = git.remotes_with_urls
          if (pair = urls.find { |_n, u| u == url })
            old = pair[0]
            sh_git!(git, ["remote", "rename", old, name]) unless old == name
          else
            sh_git!(git, ["remote", "add", name, url])
          end
        end
      end

      def configure_all_remote!(git, names, urls)
        all = names[:all]
        # Remove existing 'all' to recreate cleanly
        if git.remotes.include?(all)
          sh_git!(git, ["remote", "remove", all])
        end
        # Create with origin fetch URL; we will add multiple pushurls
        origin_url = urls[@opts[:origin].to_sym]
        sh_git!(git, ["remote", "add", all, origin_url])
        # Ensure fetch only from origin (set fetch refspec to match origin's default)
        # We'll reset fetch to +refs/heads/*:refs/remotes/all/* from origin remote
        # Simpler: disable fetch by clearing fetch then add one matching origin
        sh_git!(git, ["config", "--unset-all", "remote.#{all}.fetch"]) # ignore failure
        # Emulate origin default fetch
        sh_git!(git, ["config", "--add", "remote.#{all}.fetch", "+refs/heads/*:refs/remotes/#{all}/*"])
        # Configure push to all forges
        %i[github gitlab codeberg].each do |forge|
          sh_git!(git, ["config", "--add", "remote.#{all}.pushurl", forge_urls_entry(forge, urls)])
        end
      end

      def forge_urls_entry(forge, urls)
        urls[forge]
      end

      def sh_git!(git, args)
        # Ensure no nil sneaks into the argv to Open3 (TypeError avoidance)
        if args.any? { |a| a.nil? || (a.respond_to?(:strip) && a.strip.empty?) }
          abort!("Internal error: Attempted to run 'git #{args.inspect}' with an empty argument")
        end
        out, ok = git.capture(args)
        unless ok
          abort!("git #{args.join(" ")} failed: #{out}")
        end
        out
      end

      def show_remotes!(git)
        out, ok = git.capture(["remote", "-v"])
        if ok && !out.to_s.strip.empty?
          say("\nCurrent remotes (git remote -v):")
          puts out
        else
          # Fallback: print the fetch URLs mapping
          say("\nCurrent remotes (name => fetch URL):")
          git.remotes_with_urls.each do |name, url|
            puts "  #{name}\t#{url} (fetch)"
          end
        end
      end

      # Try fetching from each configured forge remote. Returns a hash of forge=>boolean
      def attempt_fetches!(git, names)
        results = {}
        {
          github: names[:github],
          gitlab: names[:gitlab],
          codeberg: names[:codeberg],
        }.each do |forge, remote_name|
          next unless remote_name
          ok = git.fetch(remote_name)
          results[forge] = !!ok
          say("Fetched from #{forge} (remote: #{remote_name}) => #{ok ? "OK" : "FAILED"}")
        end
        results
      end

      # Update README federation disclosure based on fetch results
      def update_readme_federation_status!(org, repo, results)
        readme_path = File.join(Dir.pwd, "README.md")
        return unless File.exist?(readme_path)
        content = File.read(readme_path)
        # Determine if all succeeded
        forges = [:github, :gitlab, :codeberg]
        all_ok = forges.all? { |f| results[f] }
        new_content = content.dup
        summary_line_with_cs = /<summary>Find this repo on other forges \(Coming soon!\)<\/summary>/
        summary_line_no_cs = "<summary>Find this repo on other forges</summary>"
        if all_ok
          new_content.gsub!(summary_line_with_cs, summary_line_no_cs)
        else
          # Ensure the line contains (Coming soon!) so readers know it's partial
          unless content =~ summary_line_with_cs
            new_content.gsub!("<summary>Find this repo on other forges</summary>", "<summary>Find this repo on other forges (Coming soon!)</summary>")
          end
        end
        if new_content != content
          File.write(readme_path, new_content)
          say("Updated README federation summary to reflect current forge status")
        end
        # Print import links for any failed forge
        unless all_ok
          say("\nSome forges are not yet available. Use these import links to create mirrors:")
          import_links = {
            github: "https://github.com/new/import",
            gitlab: "https://gitlab.com/projects/new#import_project",
            codeberg: "https://codeberg.org/repo/create?scm=git&name=#{repo}&migration=true",
          }
          [:github, :gitlab, :codeberg].each do |forge|
            next if results[forge]
            say("  - #{forge.capitalize} import: #{import_links[forge]}")
          end
        end
      rescue StandardError => e
        warn("Failed to update README federation status: #{e.message}")
      end

      def say(msg)
        puts msg
      end

      def abort!(msg)
        warn(msg)
        exit(1)
      end
    end
  end
end
