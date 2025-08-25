# frozen_string_literal: true

# External stdlib
require "open3"
require "shellwords"
require "time"
require "fileutils"
require "net/http"
require "json"
require "uri"

# External gems
require "ruby-progressbar"

module Kettle
  module Dev
    class ReleaseCLI
      def initialize
        @root = Kettle::Dev::CIHelpers.project_root
      end

      def run
        puts "== kettle-release =="

        ensure_bundler_2_7_plus!

        version = detect_version
        puts "Detected version: #{version.inspect}"

        begin
          gem_name = detect_gem_name
          latest_overall, latest_for_series = latest_released_versions(gem_name, version)
          if latest_overall
            msg = "Latest released: #{latest_overall}"
            if latest_for_series && latest_for_series != latest_overall
              msg += " | Latest for series #{Gem::Version.new(version).segments[0, 2].join(".")}.x: #{latest_for_series}"
            elsif latest_for_series
              msg += " (matches current series)"
            end
            puts msg

            cur = Gem::Version.new(version)
            overall = Gem::Version.new(latest_overall)
            cur_series = cur.segments[0, 2]
            overall_series = overall.segments[0, 2]
            target = if (cur_series <=> overall_series) == -1
              latest_for_series
            else
              latest_overall
            end
            if target && Gem::Version.new(version) <= Gem::Version.new(target)
              series = cur_series.join(".")
              warn("version.rb (#{version}) must be greater than the latest released version for series #{series}. Latest for series: #{target}.")
              warn("Tip: bump PATCH for a stable branch release, or bump MINOR/MAJOR when on trunk.")
              abort("Aborting: version bump required.")
            end
          else
            puts "Could not determine latest released version from RubyGems (offline?). Proceeding without sanity check."
          end
        rescue StandardError => e
          warn("Warning: failed to check RubyGems for latest version (#{e.class}: #{e.message}). Proceeding.")
        end

        puts "Have you updated lib/**/version.rb and CHANGELOG.md for v#{version}? [y/N]"
        print("> ")
        ans = $stdin.gets&.strip
        abort("Aborted: please update version.rb and CHANGELOG.md, then re-run.") unless ans&.downcase&.start_with?("y")

        run_cmd!("bin/setup")
        run_cmd!("bin/rake")

        appraisals_path = File.join(@root, "Appraisals")
        if File.file?(appraisals_path)
          puts "Appraisals detected at #{appraisals_path}. Running: bin/rake appraisal:update"
          run_cmd!("bin/rake appraisal:update")
        else
          puts "No Appraisals file found; skipping appraisal:update"
        end

        ensure_git_user!
        committed = commit_release_prep!(version)

        maybe_run_local_ci_before_push!(committed)

        trunk = detect_trunk_branch
        feature = current_branch
        puts "Trunk branch detected: #{trunk}"
        ensure_trunk_synced_before_push!(trunk, feature)

        push!

        monitor_workflows_after_push!

        merge_feature_into_trunk_and_push!(trunk, feature)

        checkout!(trunk)
        pull!(trunk)

        # Strong reminder for local runs: skip signing when testing a release flow
        unless ENV.key?("SKIP_GEM_SIGNING")
          puts "TIP: For local dry-runs or testing the release workflow, set SKIP_GEM_SIGNING=true to avoid PEM password prompts."
          unless ENV.fetch("CI", "false").casecmp("true").zero?
            print("Proceed with signing enabled? This may hang waiting for a PEM password. [y/N]: ")
            ans = $stdin.gets&.strip
            unless ans&.downcase&.start_with?("y")
              abort("Aborted. Re-run with SKIP_GEM_SIGNING=true bundle exec kettle-release (or set it in your environment).")
            end
          end
        end

        ensure_signing_setup_or_skip!
        puts "Running build (you may be prompted for the signing key password)..."
        run_cmd!("bundle exec rake build")

        run_cmd!("bin/gem_checksums")
        validate_checksums!(version, stage: "after build + gem_checksums")

        puts "Running release (you may be prompted for signing key password and RubyGems MFA OTP)..."
        run_cmd!("bundle exec rake release")
        validate_checksums!(version, stage: "after release")

        puts "\nRelease complete. Don't forget to push the checksums commit if needed."
      end

      private

      def monitor_workflows_after_push!
        root = Kettle::Dev::CIHelpers.project_root
        workflows = Kettle::Dev::CIHelpers.workflows_list(root)
        gitlab_ci = File.exist?(File.join(root, ".gitlab-ci.yml"))

        branch = Kettle::Dev::CIHelpers.current_branch
        abort("Could not determine current branch for CI checks.") unless branch

        gh_remote = preferred_github_remote
        gh_owner = nil
        gh_repo = nil
        if gh_remote && !workflows.empty?
          url = remote_url(gh_remote)
          gh_owner, gh_repo = parse_github_owner_repo(url)
        end

        checks_any = false

        if gh_owner && gh_repo && !workflows.empty?
          checks_any = true
          total = workflows.size
          abort("No GitHub workflows found under .github/workflows; aborting.") if total.zero?

          passed = {}
          idx = 0
          puts "Ensuring GitHub Actions workflows pass on #{branch} (#{gh_owner}/#{gh_repo}) via remote '#{gh_remote}'"
          pbar = if defined?(ProgressBar)
            ProgressBar.create(title: "CI", total: total, format: "%t %b %c/%C", length: 30)
          end

          loop do
            wf = workflows[idx]
            run = Kettle::Dev::CIHelpers.latest_run(owner: gh_owner, repo: gh_repo, workflow_file: wf, branch: branch)
            if run
              if Kettle::Dev::CIHelpers.success?(run)
                unless passed[wf]
                  passed[wf] = true
                  pbar&.increment
                end
              elsif Kettle::Dev::CIHelpers.failed?(run)
                puts
                url = run["html_url"] || "https://github.com/#{gh_owner}/#{gh_repo}/actions/workflows/#{wf}"
                abort("Workflow failed: #{wf} -> #{url}")
              end
            end
            break if passed.size == total
            idx = (idx + 1) % total
            sleep(1)
          end
          pbar&.finish unless pbar&.finished?
          puts "\nAll GitHub workflows passing (#{passed.size}/#{total})."
        end

        gl_remote = gitlab_remote_candidates.first
        if gitlab_ci && gl_remote
          owner, repo = Kettle::Dev::CIHelpers.repo_info_gitlab
          if owner && repo
            checks_any = true
            puts "Ensuring GitLab pipeline passes on #{branch} (#{owner}/#{repo}) via remote '#{gl_remote}'"
            pbar = if defined?(ProgressBar)
              ProgressBar.create(title: "CI", total: 1, format: "%t %b %c/%C", length: 30)
            end
            loop do
              pipe = Kettle::Dev::CIHelpers.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch)
              if pipe
                if Kettle::Dev::CIHelpers.gitlab_success?(pipe)
                  pbar&.increment unless pbar&.finished?
                  break
                elsif Kettle::Dev::CIHelpers.gitlab_failed?(pipe)
                  puts
                  url = pipe["web_url"] || "https://gitlab.com/#{owner}/#{repo}/-/pipelines"
                  abort("Pipeline failed: #{url}")
                end
              end
              sleep(1)
            end
            pbar&.finish unless pbar&.finished?
            puts "\nGitLab pipeline passing."
          end
        end

        abort("CI configuration not detected (GitHub or GitLab). Ensure CI is configured and remotes point to the correct hosts.") unless checks_any
      end

      def run_cmd!(cmd)
        # For Bundler-invoked build/release, explicitly prefix SKIP_GEM_SIGNING so
        # the signing step is skipped even when Bundler scrubs ENV.
        if ENV["SKIP_GEM_SIGNING"] && cmd =~ /\Abundle(\s+exec)?\s+rake\s+(build|release)\b/
          cmd = "SKIP_GEM_SIGNING=true #{cmd}"
        end
        puts "$ #{cmd}"
        # Pass a plain Hash for the environment to satisfy tests and avoid ENV object oddities
        env_hash = ENV.respond_to?(:to_hash) ? ENV.to_hash : ENV.to_h
        success = system(env_hash, cmd)
        abort("Command failed: #{cmd}") unless success
      end

      def git_output(args)
        out, status = Open3.capture2("git", *args)
        [out.strip, status.success?]
      end

      def ensure_git_user!
        name, ok1 = git_output(["config", "user.name"])
        email, ok2 = git_output(["config", "user.email"])
        abort("Git user.name or user.email not configured.") unless ok1 && ok2 && !name.empty? && !email.empty?
      end

      def ensure_bundler_2_7_plus!
        begin
          require "bundler"
        rescue LoadError
          abort("Bundler is required. Please install bundler >= 2.7.0 and try again.")
        end
        ver = Gem::Version.new(Bundler::VERSION)
        min = Gem::Version.new("2.7.0")
        if ver < min
          abort("kettle-release requires Bundler >= 2.7.0 for reproducible builds by default. Current: #{Bundler::VERSION}. Please upgrade bundler.")
        end
      end

      def maybe_run_local_ci_before_push!(committed)
        mode = (ENV["K_RELEASE_LOCAL_CI"] || "").strip.downcase
        run_it = case mode
        when "true", "1", "yes", "y" then true
        when "ask"
          print("Run local CI with 'act' before pushing? [Y/n] ")
          ans = $stdin.gets&.strip
          ans.nil? || ans.empty? || ans =~ /\Ay(es)?\z/i
        else
          false
        end
        return unless run_it

        act_ok = begin
          system("act", "--version", out: File::NULL, err: File::NULL)
        rescue StandardError
          false
        end
        unless act_ok
          puts "Skipping local CI: 'act' command not found. Install https://github.com/nektos/act to enable."
          return
        end

        root = Kettle::Dev::CIHelpers.project_root
        workflows_dir = File.join(root, ".github", "workflows")
        candidates = Kettle::Dev::CIHelpers.workflows_list(root)

        chosen = (ENV["K_RELEASE_LOCAL_CI_WORKFLOW"] || "").strip
        if !chosen.empty?
          chosen = "#{chosen}.yml" unless chosen =~ /\.ya?ml\z/
        else
          chosen = if candidates.include?("locked_deps.yml")
            "locked_deps.yml"
          elsif candidates.include?("locked_deps.yaml")
            "locked_deps.yaml"
          else
            candidates.first
          end
        end

        unless chosen
          puts "Skipping local CI: no workflows found under .github/workflows."
          return
        end

        file_path = File.join(workflows_dir, chosen)
        unless File.file?(file_path)
          puts "Skipping local CI: selected workflow not found: #{file_path}"
          return
        end

        puts "== Running local CI with act on #{chosen} =="
        ok = system("act", "-W", file_path)
        if ok
          puts "Local CI succeeded for #{chosen}."
        else
          puts "Local CI failed for #{chosen}."
          if committed
            puts "Rolling back release prep commit (soft reset)..."
            system("git", "reset", "--soft", "HEAD^")
          end
          abort("Aborting due to local CI failure.")
        end
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

      def detect_gem_name
        gemspecs = Dir[File.join(@root, "*.gemspec")]
        abort("Could not find a .gemspec in project root.") if gemspecs.empty?
        path = gemspecs.min
        content = File.read(path)
        m = content.match(/spec\.name\s*=\s*(["'])([^"']+)\1/)
        abort("Could not determine gem name from #{path}.") unless m
        m[2]
      end

      def latest_released_versions(gem_name, current_version)
        uri = URI("https://rubygems.org/api/v1/versions/#{gem_name}.json")
        res = Net::HTTP.get_response(uri)
        return [nil, nil] unless res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body)
        versions = data.map { |h| h["number"] }.compact
        versions.reject! { |v| v.to_s.include?("-pre") || v.to_s.include?(".pre") || v.to_s =~ /[a-zA-Z]/ }
        gversions = versions.map { |s| Gem::Version.new(s) }.sort
        latest_overall = gversions.last&.to_s

        cur = Gem::Version.new(current_version)
        series = cur.segments[0, 2]
        series_versions = gversions.select { |gv| gv.segments[0, 2] == series }
        latest_series = series_versions.last&.to_s
        [latest_overall, latest_series]
      rescue StandardError
        [nil, nil]
      end

      def commit_release_prep!(version)
        msg = "🔖 Prepare release v#{version}"
        out, _ = git_output(["status", "--porcelain"])
        if out.empty?
          puts "No changes to commit for release prep (continuing)."
          false
        else
          run_cmd!(%(git commit -am #{Shellwords.escape(msg)}))
          true
        end
      end

      def push!
        branch = current_branch
        abort("Could not determine current branch to push.") unless branch

        if has_remote?("all")
          puts "$ git push all #{branch}"
          success = system("git push all #{Shellwords.escape(branch)}")
          unless success
            warn("Normal push to 'all' failed; retrying with force push...")
            run_cmd!("git push -f all #{Shellwords.escape(branch)}")
          end
          return
        end

        remotes = []
        remotes << "origin" if has_remote?("origin")
        remotes |= github_remote_candidates
        remotes |= gitlab_remote_candidates
        remotes |= codeberg_remote_candidates
        remotes.uniq!

        if remotes.empty?
          puts "$ git push #{branch}"
          success = system("git push #{Shellwords.escape(branch)}")
          unless success
            warn("Normal push failed; retrying with force push...")
            run_cmd!("git push -f #{Shellwords.escape(branch)}")
          end
          return
        end

        remotes.each do |remote|
          puts "$ git push #{remote} #{branch}"
          success = system("git push #{Shellwords.escape(remote)} #{Shellwords.escape(branch)}")
          unless success
            warn("Push to #{remote} failed; retrying with force push...")
            run_cmd!("git push -f #{Shellwords.escape(remote)} #{Shellwords.escape(branch)}")
          end
        end
      end

      def detect_trunk_branch
        out, ok = git_output(["remote", "show", "origin"])
        abort("Failed to get origin remote info.") unless ok
        m = out.lines.find { |l| l.include?("HEAD branch") }
        abort("Unable to detect trunk branch from origin.") unless m
        m.split.last
      end

      def checkout!(branch)
        run_cmd!("git checkout #{Shellwords.escape(branch)}")
      end

      def pull!(branch)
        run_cmd!("git pull origin #{Shellwords.escape(branch)}")
      end

      def current_branch
        out, ok = git_output(["rev-parse", "--abbrev-ref", "HEAD"])
        ok ? out : nil
      end

      def list_remotes
        out, ok = git_output(["remote"])
        ok ? out.split(/\s+/).reject(&:empty?) : []
      end

      def remotes_with_urls
        out, ok = git_output(["remote", "-v"])
        return {} unless ok
        urls = {}
        out.each_line do |line|
          if line =~ /(\S+)\s+(\S+)\s+\((fetch|push)\)/
            name = Regexp.last_match(1)
            url = Regexp.last_match(2)
            kind = Regexp.last_match(3)
            urls[name] = url if kind == "fetch" || !urls.key?(name)
          end
        end
        urls
      end

      def remote_url(name)
        remotes_with_urls[name]
      end

      def github_remote_candidates
        remotes_with_urls.select { |n, u| u.include?("github.com") }.keys
      end

      def gitlab_remote_candidates
        remotes_with_urls.select { |n, u| u.include?("gitlab.com") }.keys
      end

      def codeberg_remote_candidates
        remotes_with_urls.select { |n, u| u.include?("codeberg.org") }.keys
      end

      def preferred_github_remote
        cands = github_remote_candidates
        return if cands.empty?
        cands.find { |n| n == "github" } || cands.first
      end

      def parse_github_owner_repo(url)
        return [nil, nil] unless url
        if url =~ %r{git@github.com:(.+?)/(.+?)(\.git)?$}
          [Regexp.last_match(1), Regexp.last_match(2).sub(/\.git\z/, "")]
        elsif url =~ %r{https://github.com/(.+?)/(.+?)(\.git)?$}
          [Regexp.last_match(1), Regexp.last_match(2).sub(/\.git\z/, "")]
        else
          [nil, nil]
        end
      end

      def has_remote?(name)
        list_remotes.include?(name)
      end

      def remote_branch_exists?(remote, branch)
        _out, ok = git_output(["show-ref", "--verify", "--quiet", "refs/remotes/#{remote}/#{branch}"])
        ok
      end

      def ahead_behind_counts(local_ref, remote_ref)
        out, ok = git_output(["rev-list", "--left-right", "--count", "#{local_ref}...#{remote_ref}"])
        return [0, 0] unless ok && !out.empty?
        parts = out.split
        left = parts[0].to_i
        right = parts[1].to_i
        [left, right]
      end

      def trunk_behind_remote?(trunk, remote)
        return false unless remote_branch_exists?(remote, trunk)
        _ahead, behind = ahead_behind_counts(trunk, "#{remote}/#{trunk}")
        behind.positive?
      end

      def ensure_trunk_synced_before_push!(trunk, feature)
        if has_remote?("all")
          puts "Remote 'all' detected. Fetching from all remotes and enforcing strict trunk parity..."
          run_cmd!("git fetch --all")
          remotes = list_remotes
          missing_from = []
          remotes.each do |r|
            next if r == "all"
            if remote_branch_exists?(r, trunk)
              _ahead, behind = ahead_behind_counts(trunk, "#{r}/#{trunk}")
              missing_from << r if behind.positive?
            end
          end
          unless missing_from.empty?
            abort("Local #{trunk} is missing commits present on: #{missing_from.join(", ")}. Please sync trunk first.")
          end
          puts "Local #{trunk} has all commits from remotes: #{(remotes - ["all"]).join(", ")}"
          return
        end

        run_cmd!("git fetch origin #{Shellwords.escape(trunk)}")
        if trunk_behind_remote?(trunk, "origin")
          puts "Local #{trunk} is behind origin/#{trunk}. Rebasing..."
          cur = current_branch
          checkout!(trunk) unless cur == trunk
          run_cmd!("git pull --rebase origin #{Shellwords.escape(trunk)}")
          checkout!(feature) unless feature.nil? || feature == trunk
          run_cmd!("git rebase #{Shellwords.escape(trunk)}")
          puts "Rebase complete. Will push updated branch next."
        else
          puts "Local #{trunk} is up to date with origin/#{trunk}."
        end

        gh_remote = preferred_github_remote
        if gh_remote && gh_remote != "origin"
          puts "GitHub remote detected: #{gh_remote}. Fetching #{trunk}..."
          run_cmd!("git fetch #{gh_remote} #{Shellwords.escape(trunk)}")

          left, right = ahead_behind_counts("origin/#{trunk}", "#{gh_remote}/#{trunk}")
          if left.zero? && right.zero?
            puts "origin/#{trunk} and #{gh_remote}/#{trunk} are already in sync."
            return
          end

          checkout!(trunk)
          run_cmd!("git pull --rebase origin #{Shellwords.escape(trunk)}")

          if left.positive? && right.positive?
            puts "origin/#{trunk} and #{gh_remote}/#{trunk} have diverged (#{left} ahead of GH, #{right} behind GH)."
            puts "Choose how to reconcile:"
            puts "  [r] Rebase local/#{trunk} on top of #{gh_remote}/#{trunk} (push to origin)"
            puts "  [m] Merge --no-ff #{gh_remote}/#{trunk} into #{trunk} (push to origin and #{gh_remote})"
            puts "  [a] Abort"
            print("> ")
            choice = $stdin.gets&.strip&.downcase
            case choice
            when "r"
              run_cmd!("git rebase #{Shellwords.escape("#{gh_remote}/#{trunk}")}")
              run_cmd!("git push origin #{Shellwords.escape(trunk)}")
              puts "Rebased #{trunk} onto #{gh_remote}/#{trunk} and pushed to origin."
            when "m"
              run_cmd!("git merge --no-ff #{Shellwords.escape("#{gh_remote}/#{trunk}")}")
              run_cmd!("git push origin #{Shellwords.escape(trunk)}")
              run_cmd!("git push #{Shellwords.escape(gh_remote)} #{Shellwords.escape(trunk)}")
              puts "Merged #{gh_remote}/#{trunk} into #{trunk} and pushed to origin and #{gh_remote}."
            else
              abort("Aborted by user. Please reconcile trunks and re-run.")
            end
          elsif right.positive? && left.zero?
            puts "Fast-forwarding #{trunk} to include #{gh_remote}/#{trunk}..."
            run_cmd!("git merge --ff-only #{Shellwords.escape("#{gh_remote}/#{trunk}")}")
            run_cmd!("git push origin #{Shellwords.escape(trunk)}")
          elsif left.positive? && right.zero?
            puts "origin/#{trunk} is ahead of #{gh_remote}/#{trunk}; no action required before push."
          end
        end
      end

      def merge_feature_into_trunk_and_push!(trunk, feature)
        return if feature.nil? || feature == trunk
        puts "Merging #{feature} into #{trunk} (after CI success)..."
        checkout!(trunk)
        run_cmd!("git pull --rebase origin #{Shellwords.escape(trunk)}")
        run_cmd!("git merge #{Shellwords.escape(feature)}")
        run_cmd!("git push origin #{Shellwords.escape(trunk)}")
        puts "Merged #{feature} into #{trunk} and pushed. The PR (if any) should auto-close."
      end

      def ensure_signing_setup_or_skip!
        return if ENV.key?("SKIP_GEM_SIGNING")

        user = ENV.fetch("GEM_CERT_USER", ENV["USER"])
        cert_path = File.join(@root, "certs", "#{user}.pem")
        unless File.exist?(cert_path)
          abort(<<~MSG)
            Gem signing appears enabled but no public cert found at:
              #{cert_path}
            Add your public key to certs/<USER>.pem (or set GEM_CERT_USER), or set SKIP_GEM_SIGNING to build unsigned.
          MSG
        end
        puts "Found signing cert: #{cert_path}"
        puts "When prompted during build/release, enter the PEM password for ~/.ssh/gem-private_key.pem"
      end

      def validate_checksums!(version, stage: "")
        gem_path = gem_file_for_version(version)
        unless gem_path && File.file?(gem_path)
          abort("Unable to locate built gem for version #{version} in pkg/. Did the build succeed?")
        end
        actual = compute_sha256(gem_path)
        checks_path = File.join(@root, "checksums", "#{File.basename(gem_path)}.sha256")
        unless File.file?(checks_path)
          abort("Expected checksum file not found: #{checks_path}. Did bin/gem_checksums run?")
        end
        expected = File.read(checks_path).strip
        if actual != expected
          abort(<<~MSG)
            SHA256 mismatch #{stage}:
              gem:   #{gem_path}
              sha256sum: #{actual}
              file: #{checks_path}
              file: #{expected}
            The artifact being released must match the checksummed artifact exactly.
            Retry locally: bundle exec rake build && bin/gem_checksums && bundle exec rake release
          MSG
        else
          puts "Checksum OK #{stage}: #{File.basename(gem_path)}"
        end
      end

      def gem_file_for_version(version)
        pkg = File.join(@root, "pkg")
        pattern = File.join(pkg, "*.gem")
        gems = Dir[pattern].select { |p| File.basename(p).include?("-#{version}.gem") }
        gems.sort.last
      end

      def compute_sha256(path)
        if system("which sha256sum > /dev/null 2>&1")
          out, _ = Open3.capture2e("sha256sum", path)
          out.split.first
        elsif system("which shasum > /dev/null 2>&1")
          out, _ = Open3.capture2e("shasum", "-a", "256", path)
          out.split.first
        else
          require "digest"
          Digest::SHA256.file(path).hexdigest
        end
      end
    end
  end
end
