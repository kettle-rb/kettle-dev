# frozen_string_literal: true

# External stdlib
require "open3"
require "net/http"
require "json"
require "uri"

module Kettle
  module Dev
    # CI-related helper functions used by Rake tasks and release tooling.
    #
    # This module only exposes module-functions (no instance state) and is
    # intentionally small so it can be required by both Rake tasks and the
    # kettle-release executable.
    module CIHelpers
      module_function

      # Determine the project root directory.
      # @return [String] absolute path to the project root
      def project_root
        # Too difficult to test every possible branch here, so ignoring
        # :nocov:
        dir = if defined?(Rake) && Rake&.application&.respond_to?(:original_dir)
          Rake.application.original_dir
        end
        # :nocov:
        dir || Dir.pwd
      end

      # Parse the GitHub owner/repo from the configured origin remote.
      # Supports SSH (git@github.com:owner/repo(.git)) and HTTPS
      # (https://github.com/owner/repo(.git)) forms.
      # @return [Array(String, String), nil] [owner, repo] or nil when unavailable
      def repo_info
        out, status = Open3.capture2("git", "config", "--get", "remote.origin.url")
        return unless status.success?
        url = out.strip
        if url =~ %r{git@github.com:(.+?)/(.+?)(\.git)?$}
          [Regexp.last_match(1), Regexp.last_match(2).sub(/\.git\z/, "")]
        elsif url =~ %r{https://github.com/(.+?)/(.+?)(\.git)?$}
          [Regexp.last_match(1), Regexp.last_match(2).sub(/\.git\z/, "")]
        end
      end

      # Current git branch name, or nil when not in a repository.
      # @return [String, nil]
      def current_branch
        out, status = Open3.capture2("git", "rev-parse", "--abbrev-ref", "HEAD")
        status.success? ? out.strip : nil
      end

      # List workflow YAML basenames under .github/workflows at the given root.
      # Excludes maintenance workflows defined by {#exclusions}.
      # @param root [String] project root (defaults to {#project_root})
      # @return [Array<String>] sorted list of basenames (e.g., "ci.yml")
      def workflows_list(root = project_root)
        workflows_dir = File.join(root, ".github", "workflows")
        files = if Dir.exist?(workflows_dir)
          Dir[File.join(workflows_dir, "*.yml")] + Dir[File.join(workflows_dir, "*.yaml")]
        else
          []
        end
        basenames = files.map { |p| File.basename(p) }
        basenames = basenames.uniq - exclusions
        basenames.sort
      end

      # List of workflow files to exclude from interactive menus and checks.
      # @return [Array<String>]
      def exclusions
        %w[
          auto-assign.yml
          codeql-analysis.yml
          danger.yml
          dependency-review.yml
          discord-notifier.yml
          opencollective.yml
        ]
      end

      # Fetch latest workflow run info for a given workflow and branch via GitHub API.
      # @param owner [String]
      # @param repo [String]
      # @param workflow_file [String] the workflow basename (e.g., "ci.yml")
      # @param branch [String, nil] branch to query; defaults to {#current_branch}
      # @param token [String, nil] OAuth token for higher rate limits; defaults to {#default_token}
      # @return [Hash{String=>String,Integer}, nil] minimal run info or nil on error/none
      def latest_run(owner:, repo:, workflow_file:, branch: nil, token: default_token)
        return unless owner && repo
        b = branch || current_branch
        return unless b
        # Scope to the exact commit SHA when available to avoid picking up a previous run on the same branch.
        sha_out, status = Open3.capture2("git", "rev-parse", "HEAD")
        sha = status.success? ? sha_out.strip : nil
        base_url = "https://api.github.com/repos/#{owner}/#{repo}/actions/workflows/#{workflow_file}/runs?branch=#{URI.encode_www_form_component(b)}&per_page=5"
        uri = URI(base_url)
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "kettle-dev/ci-helpers"
        req["Authorization"] = "token #{token}" if token && !token.empty?
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
        return unless res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body)
        runs = Array(data["workflow_runs"]) || []
        # Try to match by head_sha first; fall back to first run (branch-scoped) if none matches yet.
        run = if sha
          runs.find { |r| r["head_sha"] == sha } || runs.first
        else
          runs.first
        end
        return unless run
        {
          "status" => run["status"],
          "conclusion" => run["conclusion"],
          "html_url" => run["html_url"],
          "id" => run["id"],
        }
      rescue StandardError
        nil
      end

      # Whether a run has completed successfully.
      # @param run [Hash, nil]
      # @return [Boolean]
      def success?(run)
        run && run["status"] == "completed" && run["conclusion"] == "success"
      end

      # Whether a run has completed with a non-success conclusion.
      # @param run [Hash, nil]
      # @return [Boolean]
      def failed?(run)
        run && run["status"] == "completed" && run["conclusion"] && run["conclusion"] != "success"
      end

      # Default GitHub token sourced from environment.
      # @return [String, nil]
      def default_token
        ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"]
      end

      # --- GitLab support ---

      # Raw origin URL string from git config
      # @return [String, nil]
      def origin_url
        out, status = Open3.capture2("git", "config", "--get", "remote.origin.url")
        status.success? ? out.strip : nil
      end

      # Parse GitLab owner/repo from origin if pointing to gitlab.com
      # @return [Array(String, String), nil]
      def repo_info_gitlab
        url = origin_url
        return unless url
        if url =~ %r{git@gitlab.com:(.+?)/(.+?)(\.git)?$}
          [Regexp.last_match(1), Regexp.last_match(2).sub(/\.git\z/, "")]
        elsif url =~ %r{https://gitlab.com/(.+?)/(.+?)(\.git)?$}
          [Regexp.last_match(1), Regexp.last_match(2).sub(/\.git\z/, "")]
        end
      end

      # Default GitLab token from environment
      # @return [String, nil]
      def default_gitlab_token
        ENV["GITLAB_TOKEN"] || ENV["GL_TOKEN"]
      end

      # Fetch the latest pipeline for a branch on GitLab
      # @param owner [String]
      # @param repo [String]
      # @param branch [String, nil]
      # @param host [String]
      # @param token [String, nil]
      # @return [Hash{String=>String,Integer}, nil]
      def gitlab_latest_pipeline(owner:, repo:, branch: nil, host: "gitlab.com", token: default_gitlab_token)
        return unless owner && repo
        b = branch || current_branch
        return unless b
        project = URI.encode_www_form_component("#{owner}/#{repo}")
        uri = URI("https://#{host}/api/v4/projects/#{project}/pipelines?ref=#{URI.encode_www_form_component(b)}&per_page=1")
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "kettle-dev/ci-helpers"
        req["PRIVATE-TOKEN"] = token if token && !token.empty?
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
        return unless res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body)
        pipe = data&.first
        return unless pipe
        # Attempt to enrich with failure_reason by querying the single pipeline endpoint
        begin
          if pipe["id"]
            detail_uri = URI("https://#{host}/api/v4/projects/#{project}/pipelines/#{pipe["id"]}")
            dreq = Net::HTTP::Get.new(detail_uri)
            dreq["User-Agent"] = "kettle-dev/ci-helpers"
            dreq["PRIVATE-TOKEN"] = token if token && !token.empty?
            dres = Net::HTTP.start(detail_uri.hostname, detail_uri.port, use_ssl: true) { |http| http.request(dreq) }
            if dres.is_a?(Net::HTTPSuccess)
              det = JSON.parse(dres.body)
              pipe["failure_reason"] = det["failure_reason"] if det.is_a?(Hash)
              pipe["status"] = det["status"] if det["status"]
              pipe["web_url"] = det["web_url"] if det["web_url"]
            end
          end
        rescue StandardError
          # ignore enrichment errors; fall back to basic fields
        end
        {
          "status" => pipe["status"],
          "web_url" => pipe["web_url"],
          "id" => pipe["id"],
          "failure_reason" => pipe["failure_reason"],
        }
      rescue StandardError
        nil
      end

      # Whether a GitLab pipeline has succeeded
      # @param pipeline [Hash, nil]
      # @return [Boolean]
      def gitlab_success?(pipeline)
        pipeline && pipeline["status"] == "success"
      end

      # Whether a GitLab pipeline has failed
      # @param pipeline [Hash, nil]
      # @return [Boolean]
      def gitlab_failed?(pipeline)
        pipeline && pipeline["status"] == "failed"
      end
    end
  end
end
