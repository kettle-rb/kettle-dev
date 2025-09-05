# frozen_string_literal: true

# External stdlib
require "uri"
require "json"
require "net/http"

module Kettle
  module Dev
    # CIMonitor centralizes CI monitoring logic (GitHub Actions and GitLab pipelines)
    # so it can be reused by both kettle-release and Rake tasks (e.g., ci:act).
    #
    # Public API is intentionally small and based on environment/project introspection
    # via CIHelpers, matching the behavior historically implemented in ReleaseCLI.
    module CIMonitor
      module_function

      # Abort helper (delegates through ExitAdapter so specs can trap exits)
      def abort(msg)
        Kettle::Dev::ExitAdapter.abort(msg)
      end
      module_function :abort

      # Small helper to map CI run status/conclusion to an emoji.
      # Reused by ci:act and release summary.
      # @param status [String, nil]
      # @param conclusion [String, nil]
      # @return [String]
      def status_emoji(status, conclusion)
        case status.to_s
        when "queued" then "⏳️"
        when "in_progress", "running" then "👟"
        when "completed"
          (conclusion.to_s == "success") ? "✅" : "🍅"
        else
          # Some APIs report only a final state string like "success"/"failed"
          return "✅" if conclusion.to_s == "success" || status.to_s == "success"
          return "🍅" if conclusion.to_s == "failure" || status.to_s == "failed"
          "⏳️"
        end
      end
      module_function :status_emoji

      # Monitor both GitHub and GitLab CI for the current project/branch.
      # This mirrors ReleaseCLI behavior and aborts on first failure.
      #
      # @param restart_hint [String] guidance command shown on failure
      # @return [void]
      def monitor_all!(restart_hint: "bundle exec kettle-release start_step=10")
        checks_any = false
        checks_any |= monitor_github_internal!(restart_hint: restart_hint)
        checks_any |= monitor_gitlab_internal!(restart_hint: restart_hint)
        abort("CI configuration not detected (GitHub or GitLab). Ensure CI is configured and remotes point to the correct hosts.") unless checks_any
      end

      # Public wrapper to monitor GitLab pipeline with abort-on-failure semantics.
      # Matches RBS and call sites expecting ::monitor_gitlab!
      # Returns false when GitLab is not configured for this repo/branch.
      # @param restart_hint [String]
      # @return [Boolean]
      def monitor_gitlab!(restart_hint: "bundle exec kettle-release start_step=10")
        monitor_gitlab_internal!(restart_hint: restart_hint)
      end
      module_function :monitor_gitlab!

      # Non-aborting collection across GH and GL, returning a compact results hash.
      # Results format:
      #   {
      #     github: [ {workflow: "file.yml", status: "completed", conclusion: "success"|"failure"|nil, url: String} ],
      #     gitlab: { status: "success"|"failed"|"blocked"|"unknown"|nil, url: String }
      #   }
      # @return [Hash]
      def collect_all
        results = {github: [], gitlab: nil}
        begin
          gh = collect_github
          results[:github] = gh if gh
        rescue StandardError => e
          Kettle::Dev.debug_error(e, __method__)
        end
        begin
          gl = collect_gitlab
          results[:gitlab] = gl if gl
        rescue StandardError => e
          Kettle::Dev.debug_error(e, __method__)
        end
        results
      end
      module_function :collect_all

      # Print a concise summary like ci:act and return whether everything is green.
      # @param results [Hash]
      # @return [Boolean] true when all checks passed or were unknown, false when any failed
      def summarize_results(results)
        all_ok = true
        gh_items = results[:github] || []
        unless gh_items.empty?
          puts "GitHub Actions:"
          gh_items.each do |it|
            emoji = status_emoji(it[:status], it[:conclusion])
            details = [it[:status], it[:conclusion]].compact.join("/")
            wf = it[:workflow]
            puts "  - #{wf}: #{emoji} (#{details}) #{it[:url] ? "-> #{it[:url]}" : ""}"
            all_ok &&= (it[:conclusion] == "success")
          end
        end
        gl = results[:gitlab]
        if gl
          status = if gl[:status] == "success"
            "success"
          else
            ((gl[:status] == "failed") ? "failure" : nil)
          end
          emoji = status_emoji(gl[:status], status)
          details = gl[:status].to_s
          puts "GitLab Pipeline: #{emoji} (#{details}) #{gl[:url] ? "-> #{gl[:url]}" : ""}"
          all_ok &&= (gl[:status] != "failed")
        end
        all_ok
      end
      module_function :summarize_results

      # Prompt user to continue or quit when failures are present; otherwise return.
      # Designed for kettle-release.
      # @param restart_hint [String]
      # @return [void]
      def monitor_and_prompt_for_release!(restart_hint: "bundle exec kettle-release start_step=10")
        results = collect_all
        any_checks = !(results[:github].nil? || results[:github].empty?) || !!results[:gitlab]
        abort("CI configuration not detected (GitHub or GitLab). Ensure CI is configured and remotes point to the correct hosts.") unless any_checks

        ok = summarize_results(results)
        return if ok

        # Non-interactive environments default to quitting unless explicitly allowed
        env_val = ENV.fetch("K_RELEASE_CI_CONTINUE", "false")
        non_interactive_continue = !!(Kettle::Dev::ENV_TRUE_RE =~ env_val)
        if !$stdin.tty?
          abort("CI checks reported failures. Fix and restart from CI validation (#{restart_hint}).") unless non_interactive_continue
          puts "CI checks reported failures, but continuing due to K_RELEASE_CI_CONTINUE=true."
          return
        end

        # Prompt exactly once; avoid repeated printing in case of unexpected input buffering.
        # Accept c/continue to proceed or q/quit to abort. Any other input defaults to quit with a message.
        print("One or more CI checks failed. (c)ontinue or (q)uit? ")
        ans = Kettle::Dev::InputAdapter.gets
        if ans.nil?
          abort("Aborting (no input available). Fix CI, then restart with: #{restart_hint}")
        end
        ans = ans.strip.downcase
        if ans == "c" || ans == "continue"
          puts "Continuing release despite CI failures."
        elsif ans == "q" || ans == "quit"
          abort("Aborting per user choice. Fix CI, then restart with: #{restart_hint}")
        else
          abort("Unrecognized input '#{ans}'. Aborting. Fix CI, then restart with: #{restart_hint}")
        end
      end
      module_function :monitor_and_prompt_for_release!

      # --- Collectors ---
      def collect_github
        root = Kettle::Dev::CIHelpers.project_root
        workflows = Kettle::Dev::CIHelpers.workflows_list(root)
        gh_remote = preferred_github_remote
        return unless gh_remote && !workflows.empty?

        branch = Kettle::Dev::CIHelpers.current_branch
        abort("Could not determine current branch for CI checks.") unless branch

        url = remote_url(gh_remote)
        owner, repo = parse_github_owner_repo(url)
        return unless owner && repo

        total = workflows.size
        return [] if total.zero?

        puts "Checking GitHub Actions workflows on #{branch} (#{owner}/#{repo}) via remote '#{gh_remote}'"
        pbar = if defined?(ProgressBar)
          ProgressBar.create(title: "GHA", total: total, format: "%t %b %c/%C", length: 30)
        end
        # Initial sleep same as aborting path
        begin
          initial_sleep = Integer(ENV["K_RELEASE_CI_INITIAL_SLEEP"])
        rescue
          initial_sleep = nil
        end
        sleep((initial_sleep && initial_sleep >= 0) ? initial_sleep : 3)

        results = {}
        idx = 0
        loop do
          wf = workflows[idx]
          run = Kettle::Dev::CIHelpers.latest_run(owner: owner, repo: repo, workflow_file: wf, branch: branch)
          if run
            if Kettle::Dev::CIHelpers.success?(run)
              unless results[wf]
                status = run["status"] || "completed"
                conclusion = run["conclusion"] || "success"
                results[wf] = {workflow: wf, status: status, conclusion: conclusion, url: run["html_url"]}
                pbar&.increment
              end
            elsif Kettle::Dev::CIHelpers.failed?(run)
              unless results[wf]
                results[wf] = {workflow: wf, status: run["status"], conclusion: run["conclusion"] || "failure", url: run["html_url"] || "https://github.com/#{owner}/#{repo}/actions/workflows/#{wf}"}
                pbar&.increment
              end
            end
          end
          break if results.size == total
          idx = (idx + 1) % total
          sleep(1)
        end
        pbar&.finish unless pbar&.finished?
        results.values
      end
      module_function :collect_github

      def collect_gitlab
        root = Kettle::Dev::CIHelpers.project_root
        gitlab_ci = File.exist?(File.join(root, ".gitlab-ci.yml"))
        gl_remote = gitlab_remote_candidates.first
        return unless gitlab_ci && gl_remote

        branch = Kettle::Dev::CIHelpers.current_branch
        abort("Could not determine current branch for CI checks.") unless branch

        owner, repo = Kettle::Dev::CIHelpers.repo_info_gitlab
        return unless owner && repo

        puts "Checking GitLab pipeline on #{branch} (#{owner}/#{repo}) via remote '#{gl_remote}'"
        pbar = if defined?(ProgressBar)
          ProgressBar.create(title: "GL", total: 1, format: "%t %b %c/%C", length: 30)
        end
        result = {status: "unknown", url: nil}
        loop do
          pipe = Kettle::Dev::CIHelpers.gitlab_latest_pipeline(owner: owner, repo: repo, branch: branch)
          if pipe
            result[:url] ||= pipe["web_url"] || "https://gitlab.com/#{owner}/#{repo}/-/pipelines"
            if Kettle::Dev::CIHelpers.gitlab_success?(pipe)
              result[:status] = "success"
              pbar&.increment unless pbar&.finished?
            elsif Kettle::Dev::CIHelpers.gitlab_failed?(pipe)
              reason = (pipe["failure_reason"] || "").to_s
              if reason =~ /insufficient|quota|minute/i
                result[:status] = "unknown"
                pbar&.finish unless pbar&.finished?
              else
                result[:status] = "failed"
                pbar&.increment unless pbar&.finished?
              end
            elsif pipe["status"] == "blocked"
              result[:status] = "blocked"
              pbar&.finish unless pbar&.finished?
            end
            break
          end
          sleep(1)
        end
        pbar&.finish unless pbar&.finished?
        result
      end
      module_function :collect_gitlab

      # -- internals (abort-on-failure legacy paths used elsewhere) --

      def monitor_github_internal!(restart_hint:)
        root = Kettle::Dev::CIHelpers.project_root
        workflows = Kettle::Dev::CIHelpers.workflows_list(root)
        gh_remote = preferred_github_remote
        return false unless gh_remote && !workflows.empty?

        branch = Kettle::Dev::CIHelpers.current_branch
        abort("Could not determine current branch for CI checks.") unless branch

        url = remote_url(gh_remote)
        owner, repo = parse_github_owner_repo(url)
        return false unless owner && repo

        total = workflows.size
        abort("No GitHub workflows found under .github/workflows; aborting.") if total.zero?

        passed = {}
        puts "Ensuring GitHub Actions workflows pass on #{branch} (#{owner}/#{repo}) via remote '#{gh_remote}'"
        pbar = if defined?(ProgressBar)
          ProgressBar.create(title: "CI", total: total, format: "%t %b %c/%C", length: 30)
        end
        # Small initial delay to allow GitHub to register the newly pushed commit and enqueue workflows.
        # Configurable via K_RELEASE_CI_INITIAL_SLEEP (seconds); defaults to 3s.
        begin
          initial_sleep = begin
            Integer(ENV["K_RELEASE_CI_INITIAL_SLEEP"])
          rescue
            nil
          end
        end
        sleep((initial_sleep && initial_sleep >= 0) ? initial_sleep : 3)
        idx = 0
        loop do
          wf = workflows[idx]
          run = Kettle::Dev::CIHelpers.latest_run(owner: owner, repo: repo, workflow_file: wf, branch: branch)
          if run
            if Kettle::Dev::CIHelpers.success?(run)
              unless passed[wf]
                passed[wf] = true
                pbar&.increment
              end
            elsif Kettle::Dev::CIHelpers.failed?(run)
              puts
              wf_url = run["html_url"] || "https://github.com/#{owner}/#{repo}/actions/workflows/#{wf}"
              abort("Workflow failed: #{wf} -> #{wf_url} Fix the workflow, then restart this tool from CI validation with: #{restart_hint}")
            end
          end
          break if passed.size == total
          idx = (idx + 1) % total
          sleep(1)
        end
        pbar&.finish unless pbar&.finished?
        puts "\nAll GitHub workflows passing (#{passed.size}/#{total})."
        true
      end
      module_function :monitor_github_internal!

      def monitor_gitlab_internal!(restart_hint:)
        root = Kettle::Dev::CIHelpers.project_root
        gitlab_ci = File.exist?(File.join(root, ".gitlab-ci.yml"))
        gl_remote = gitlab_remote_candidates.first
        return false unless gitlab_ci && gl_remote

        branch = Kettle::Dev::CIHelpers.current_branch
        abort("Could not determine current branch for CI checks.") unless branch

        owner, repo = Kettle::Dev::CIHelpers.repo_info_gitlab
        return false unless owner && repo

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
              # Special-case: if failure is due to exhausted minutes/insufficient quota, treat as unknown and continue
              reason = (pipe["failure_reason"] || "").to_s
              if reason =~ /insufficient|quota|minute/i
                puts "\nGitLab reports pipeline cannot run due to quota/minutes exhaustion. Result is unknown; continuing."
                pbar&.finish unless pbar&.finished?
                break
              else
                puts
                url = pipe["web_url"] || "https://gitlab.com/#{owner}/#{repo}/-/pipelines"
                abort("Pipeline failed: #{url} Fix the pipeline, then restart this tool from CI validation with: #{restart_hint}")
              end
            elsif pipe["status"] == "blocked"
              # Blocked pipeline (e.g., awaiting approvals) — treat as unknown and continue
              puts "\nGitLab pipeline is blocked. Result is unknown; continuing."
              pbar&.finish unless pbar&.finished?
              break
            end
          end
          sleep(1)
        end
        pbar&.finish unless pbar&.finished?
        puts "\nGitLab pipeline passing."
        true
      end
      module_function :monitor_gitlab_internal!

      # -- tiny wrappers around GitAdapter-like helpers used by ReleaseCLI --
      def remotes_with_urls
        Kettle::Dev::GitAdapter.new.remotes_with_urls
      end
      module_function :remotes_with_urls

      def remote_url(name)
        Kettle::Dev::GitAdapter.new.remote_url(name)
      end
      module_function :remote_url

      def github_remote_candidates
        remotes_with_urls.select { |n, u| u.include?("github.com") }.keys
      end
      module_function :github_remote_candidates

      def gitlab_remote_candidates
        remotes_with_urls.select { |n, u| u.include?("gitlab.com") }.keys
      end
      module_function :gitlab_remote_candidates

      def preferred_github_remote
        cands = github_remote_candidates
        return if cands.empty?
        explicit = cands.find { |n| n == "github" } || cands.find { |n| n == "gh" }
        return explicit if explicit
        return "origin" if cands.include?("origin")
        cands.first
      end
      module_function :preferred_github_remote

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
      module_function :parse_github_owner_repo
    end
  end
end
