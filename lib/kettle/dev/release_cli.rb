# frozen_string_literal: true

# External stdlib
require "digest"
require "open3"
require "shellwords"
require "time"
require "fileutils"
require "net/http"
require "json"
require "uri"

# External gems
require "ruby-progressbar"

# Internal
require "kettle/dev/git_adapter"
require "kettle/dev/exit_adapter"
require "kettle/dev/input_adapter"
require "kettle/dev/versioning"

module Kettle
  module Dev
    class ReleaseCLI
      private

      def abort(msg)
        Kettle::Dev::ExitAdapter.abort(msg)
      end

      public

      def initialize(start_step: 1)
        @root = Kettle::Dev::CIHelpers.project_root
        @git = Kettle::Dev::GitAdapter.new
        @start_step = (start_step || 1).to_i
        @start_step = 1 if @start_step < 1
      end

      def run
        # 1. Ensure Bundler version ✓
        ensure_bundler_2_7_plus!

        version = nil
        committed = nil
        trunk = nil
        feature = nil

        # 2. Version detection and sanity checks + prompt
        if @start_step <= 2
          version = detect_version
          puts "Detected version: #{version.inspect}"

          latest_overall = nil
          latest_for_series = nil
          begin
            gem_name = detect_gem_name
            latest_overall, latest_for_series = latest_released_versions(gem_name, version)
          rescue StandardError => e
            warn("Warning: failed to check RubyGems for latest version (#{e.class}: #{e.message}). Proceeding.")
          end

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
            if target
              bump = Kettle::Dev::Versioning.classify_bump(target, version)
              case bump
              when :same
                series = cur_series.join(".")
                warn("version.rb (#{version}) matches the latest released version for series #{series} (#{target}).")
                abort("Aborting: version bump required. Bump PATCH/MINOR/MAJOR/EPIC.")
              when :downgrade
                series = cur_series.join(".")
                warn("version.rb (#{version}) is lower than the latest released version for series #{series} (#{target}).")
                abort("Aborting: version must be bumped above #{target}.")
              else
                label = {epic: "EPIC", major: "MAJOR", minor: "MINOR", patch: "PATCH"}[bump] || bump.to_s.upcase
                puts "Proposed bump type: #{label} (from #{target} -> #{version})"
              end
            else
              puts "Could not determine latest released version from RubyGems (offline?). Proceeding without sanity check."
            end
          else
            puts "Could not determine latest released version from RubyGems (offline?). Proceeding without sanity check."
          end

          puts "Have you updated lib/**/version.rb and CHANGELOG.md for v#{version}? [y/N]"
          print("> ")
          ans = Kettle::Dev::InputAdapter.gets&.strip
          abort("Aborted: please update version.rb and CHANGELOG.md, then re-run.") unless ans&.downcase&.start_with?("y")
        end

        # 3. bin/setup
        run_cmd!("bin/setup") if @start_step <= 3
        # 4. bin/rake
        run_cmd!("bin/rake") if @start_step <= 4

        # 5. appraisal:update (optional)
        if @start_step <= 5
          appraisals_path = File.join(@root, "Appraisals")
          if File.file?(appraisals_path)
            puts "Appraisals detected at #{appraisals_path}. Running: bin/rake appraisal:update"
            run_cmd!("bin/rake appraisal:update")
          else
            puts "No Appraisals file found; skipping appraisal:update"
          end
        end

        # 6. git user + commit release prep
        if @start_step <= 6
          ensure_git_user!
          version ||= detect_version
          committed = commit_release_prep!(version)
        end

        # 7. optional local CI via act
        maybe_run_local_ci_before_push!(committed) if @start_step <= 7

        # 8. ensure trunk synced
        if @start_step <= 8
          trunk = detect_trunk_branch
          feature = current_branch
          puts "Trunk branch detected: #{trunk}"
          ensure_trunk_synced_before_push!(trunk, feature)
        end

        # 9. push branches
        push! if @start_step <= 9

        # 10. monitor CI after push
        monitor_workflows_after_push! if @start_step <= 10

        # 11. merge feature into trunk and push
        if @start_step <= 11
          trunk ||= detect_trunk_branch
          feature ||= current_branch
          merge_feature_into_trunk_and_push!(trunk, feature)
        end

        # 12. checkout trunk and pull
        if @start_step <= 12
          trunk ||= detect_trunk_branch
          checkout!(trunk)
          pull!(trunk)
        end

        # 13. signing guidance and checks
        if @start_step <= 13
          if ENV.fetch("SKIP_GEM_SIGNING", "false").casecmp("false").zero?
            puts "TIP: For local dry-runs or testing the release workflow, set SKIP_GEM_SIGNING=true to avoid PEM password prompts."
            if Kettle::Dev::InputAdapter.tty?
              # In CI, avoid interactive prompts when no TTY is present (e.g., act or GitHub Actions "CI validation").
              # Non-interactive CI runs should not abort here; later signing checks are either stubbed in tests
              # or will be handled explicitly by ensure_signing_setup_or_skip!.
              print("Proceed with signing enabled? This may hang waiting for a PEM password. [y/N]: ")
              ans = Kettle::Dev::InputAdapter.gets&.strip
              unless ans&.downcase&.start_with?("y")
                abort("Aborted. Re-run with SKIP_GEM_SIGNING=true bundle exec kettle-release (or set it in your environment).")
              end
            else
              warn("Non-interactive shell detected (non-TTY); skipping interactive signing confirmation.")
            end
          end

          ensure_signing_setup_or_skip!
        end

        # 14. build
        if @start_step <= 14
          puts "Running build (you may be prompted for the signing key password)..."
          run_cmd!("bundle exec rake build")
        end

        # 15. checksums validate
        if @start_step <= 15
          run_cmd!("bin/gem_checksums")
          version ||= detect_version
          validate_checksums!(version, stage: "after build + gem_checksums")
        end

        # 16. release and validate
        if @start_step <= 16
          puts "Running release (you may be prompted for signing key password and RubyGems MFA OTP)..."
          run_cmd!("bundle exec rake release")
          version ||= detect_version
          validate_checksums!(version, stage: "after release")
        end

        # 17. create GitHub release (optional)
        if @start_step <= 17
          version ||= detect_version
          maybe_create_github_release!(version)
        end

        # 18. push tags to remotes (new final step)
        push_tags! if @start_step <= 18

        # Final success message
        begin
          version ||= detect_version
          gem_name = detect_gem_name
          puts "\n🚀 Release #{gem_name} v#{version} Complete 🚀"
        rescue StandardError
          # Fallback if detection fails for any reason
          puts "\n🚀 Release v#{version || "unknown"} Complete 🚀"
        end
      end

      private

      def monitor_workflows_after_push!
        # Delegate to shared CI monitor to keep logic DRY across release flow and rake tasks
        require "kettle/dev/ci_monitor"
        Kettle::Dev::CIMonitor.monitor_all!(restart_hint: "bundle exec kettle-release start_step=10")
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
          ans = Kettle::Dev::InputAdapter.gets&.strip
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
        Kettle::Dev::Versioning.detect_version(@root)
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
        # Stage all changes (including new/untracked files) prior to committing
        run_cmd!("git add -A")
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
          success = @git.push("all", branch)
          unless success
            warn("Normal push to 'all' failed; retrying with force push...")
            @git.push("all", branch, force: true)
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
          success = @git.push(nil, branch)
          unless success
            warn("Normal push failed; retrying with force push...")
            @git.push(nil, branch, force: true)
          end
          return
        end

        remotes.each do |remote|
          puts "$ git push #{remote} #{branch}"
          success = @git.push(remote, branch)
          unless success
            warn("Push to #{remote} failed; retrying with force push...")
            @git.push(remote, branch, force: true)
          end
        end
      end

      def push_tags!
        # After release, push tags to remotes according to policy:
        # 1) If a remote named "all" exists, push tags only to it.
        # 2) Otherwise, if other remotes exist, push tags to each of them.
        # 3) If no remotes are configured, push tags using default remote.
        if has_remote?("all")
          run_cmd!("git push all --tags")
          return
        end

        remotes = list_remotes
        remotes -= ["all"] if remotes
        if remotes.nil? || remotes.empty?
          run_cmd!("git push --tags")
        else
          remotes.each do |remote|
            run_cmd!("git push #{Shellwords.escape(remote)} --tags")
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
        ok = @git.checkout(branch)
        abort("Failed to checkout #{branch}") unless ok
      end

      def pull!(branch)
        ok = @git.pull("origin", branch)
        abort("Failed to pull origin #{branch}") unless ok
      end

      def current_branch
        @git.current_branch
      end

      def list_remotes
        @git.remotes
      end

      def remotes_with_urls
        @git.remotes_with_urls
      end

      def remote_url(name)
        @git.remote_url(name)
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
        # Prefer explicitly named GitHub remotes first, then origin (only if it points to GitHub), else the first candidate
        explicit = cands.find { |n| n == "github" } || cands.find { |n| n == "gh" }
        return explicit if explicit
        return "origin" if cands.include?("origin")
        cands.first
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
            choice = Kettle::Dev::InputAdapter.gets&.strip&.downcase
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
        # Treat any non-/true/i value as an explicit skip signal
        return if ENV.fetch("SKIP_GEM_SIGNING", "").casecmp("true").zero?

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

      # If GITHUB_TOKEN is present, create a GitHub release for the given version tag.
      # Title: v<version>
      # Body: the CHANGELOG section for this version, followed by the two link references for this version.
      def maybe_create_github_release!(version)
        token = ENV.fetch("GITHUB_TOKEN", "").to_s
        return if token.strip.empty?

        gh_remote = preferred_github_remote
        url = remote_url(gh_remote || "origin")
        owner, repo = parse_github_owner_repo(url)
        unless owner && repo
          warn("GITHUB_TOKEN present but could not determine GitHub owner/repo from remotes. Skipping release creation.")
          return
        end

        section, compare_ref, tag_ref = extract_changelog_for_version(version)
        unless section
          warn("CHANGELOG.md does not contain a section for #{version}. Skipping GitHub release creation.")
          return
        end

        body = +""
        body << section.rstrip
        body << "\n\n"
        body << compare_ref if compare_ref
        body << tag_ref if tag_ref

        tag = "v#{version}"
        puts "Creating GitHub release #{owner}/#{repo} #{tag}..."
        ok, msg = github_create_release(owner: owner, repo: repo, token: token, tag: tag, title: tag, body: body)
        if ok
          puts "GitHub release created for #{tag}."
        else
          warn("GitHub release creation skipped/failed: #{msg}")
        end
      end

      # Returns [section_text, compare_ref_line, tag_ref_line]
      def extract_changelog_for_version(version)
        path = File.join(@root, "CHANGELOG.md")
        return [nil, nil, nil] unless File.file?(path)
        content = File.read(path)
        lines = content.lines

        # Find section start
        start_idx = lines.index { |l| l.start_with?("## [#{version}]") }
        return [nil, nil, nil] unless start_idx
        i = start_idx + 1
        # Find next section heading or EOF
        while i < lines.length && !lines[i].start_with?("## [")
          i += 1
        end
        section = lines[start_idx...(i)].join

        # Find link refs (anywhere after Unreleased or at end; simple global scan acceptable)
        compare_ref = lines.find { |l| l.start_with?("[#{version}]: ") }
        tag_ref = lines.find { |l| l.start_with?("[#{version}t]: ") }
        # Ensure newline termination
        compare_ref = compare_ref&.end_with?("\n") ? compare_ref : (compare_ref && compare_ref + "\n")
        tag_ref = tag_ref&.end_with?("\n") ? tag_ref : (tag_ref && tag_ref + "\n")
        [section, compare_ref, tag_ref]
      rescue StandardError => e
        warn("Failed to parse CHANGELOG.md: #{e.class}: #{e.message}")
        [nil, nil, nil]
      end

      # POST to GitHub Releases API
      # Returns [ok(Boolean), message(String)]
      def github_create_release(owner:, repo:, token:, tag:, title:, body:)
        uri = URI("https://api.github.com/repos/#{owner}/#{repo}/releases")
        req = Net::HTTP::Post.new(uri)
        req["Accept"] = "application/vnd.github+json"
        req["Authorization"] = "token #{token}"
        req["User-Agent"] = "kettle-dev-release-cli"
        req.body = JSON.dump({
          tag_name: tag,
          name: title,
          body: body,
          draft: false,
          prerelease: false,
        })

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(req)
        end

        case res
        when Net::HTTPSuccess, Net::HTTPCreated
          [true, "created"]
        else
          # If release already exists, treat as non-fatal
          if res.code.to_s == "422" && res.body.to_s.include?("already_exists")
            [true, "already exists"]
          else
            [false, "HTTP #{res.code}: #{res.body}"]
          end
        end
      rescue StandardError => e
        [false, "#{e.class}: #{e.message}"]
      end
    end
  end
end
