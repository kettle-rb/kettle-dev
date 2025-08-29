# frozen_string_literal: true

# External stdlib
require "uri"
require "json"
require "net/http"

# Internal
require "kettle/dev/ci_helpers"
require "kettle/dev/exit_adapter"
require "kettle/dev/git_adapter"

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

      # Monitor both GitHub and GitLab CI for the current project/branch.
      # This mirrors ReleaseCLI behavior.
      #
      # @param restart_hint [String] guidance command shown on failure
      # @return [void]
      def monitor_all!(restart_hint: "bundle exec kettle-release start_step=10")
        checks_any = false
        checks_any |= monitor_github_internal!(restart_hint: restart_hint)
        checks_any |= monitor_gitlab_internal!(restart_hint: restart_hint)
        abort("CI configuration not detected (GitHub or GitLab). Ensure CI is configured and remotes point to the correct hosts.") unless checks_any
      end

      # Monitor only the GitLab pipeline for current project/branch.
      # Used by ci:act after running 'act'.
      #
      # @param restart_hint [String] guidance command shown on failure
      # @return [Boolean] true if check performed (gitlab configured), false otherwise
      def monitor_gitlab!(restart_hint: "bundle exec rake ci:act")
        monitor_gitlab_internal!(restart_hint: restart_hint)
      end

      # -- internals --

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
