# frozen_string_literal: true

require "open3"

module Kettle
  module Dev
    # Minimal Git adapter used by kettle-dev to avoid invoking live shell commands
    # directly from the higher-level library code. In tests, mock this adapter's
    # methods to prevent any real network or repository mutations.
    #
    # Behavior:
    # - Prefer the 'git' gem when available.
    # - If the 'git' gem is not present (LoadError), fall back to shelling out to
    #   the system `git` executable for the small set of operations we need.
    #
    # Public API is intentionally small and only includes what we need right now.
    class GitAdapter
      # Determine whether the working tree is clean (no unstaged, staged, or untracked changes).
      # @return [Boolean] true if clean, false if any changes or on error
      def clean?
        if @backend == :gem
          begin
            status = @git.status
            # git gem's Status responds to changed, added, deleted, untracked, etc.
            status.changed.empty? && status.added.empty? && status.deleted.empty? && status.untracked.empty?
          rescue StandardError => e
            Kettle::Dev.debug_error(e, __method__)
            false
          end
        else
          out, st = Open3.capture2("git", "status", "--porcelain")
          st.success? && out.strip.empty?
        end
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        false
      end

      # Execute a git command and capture its stdout and success flag.
      # This is a generic escape hatch used by higher-level code for read-only
      # queries that aren't covered by the explicit adapter API. Tests can stub
      # this method to avoid shelling out.
      # @param args [Array<String>]
      # @return [Array<(String, Boolean)>] [output, success]
      def capture(args)
        out, status = Open3.capture2("git", *args)
        [out.strip, status.success?]
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        ["", false]
      end

      # Create a new adapter rooted at the current working directory.
      # @return [void]
      def initialize
        begin
          # Allow users/CI to opt out of using the 'git' gem even when available.
          # Set KETTLE_DEV_DISABLE_GIT_GEM to a truthy value ("1", "true", "yes") to force CLI backend.
          env_val = ENV["KETTLE_DEV_DISABLE_GIT_GEM"]
          # Ruby 2.3 compatibility: String#match? was added in 2.4; use Regexp#=== / =~ instead
          disable_gem = env_val && !!(/\A(1|true|yes)\z/i =~ env_val)
          if disable_gem
            @backend = :cli
          else
            Kernel.require "git"
            @backend = :gem
            @git = ::Git.open(Dir.pwd)
          end
        rescue LoadError => e
          Kettle::Dev.debug_error(e, __method__)
          # Optional dependency: fall back to CLI
          @backend = :cli
        rescue StandardError => e
          raise Kettle::Dev::Error, "Failed to open git repository: #{e.message}"
        end
      end

      # Push a branch to a remote.
      # @param remote [String, nil] remote name (nil means default remote)
      # @param branch [String] branch name (required)
      # @param force [Boolean] whether to force push
      # @return [Boolean] true when the push is reported successful
      def push(remote, branch, force: false)
        if @backend == :gem
          begin
            if remote
              @git.push(remote, branch, force: force)
            else
              # Default remote according to repo config
              @git.push(nil, branch, force: force)
            end
            true
          rescue StandardError => e
            Kettle::Dev.debug_error(e, __method__)
            false
          end
        else
          args = ["git", "push"]
          args << "--force" if force
          if remote
            args << remote.to_s << branch.to_s
          end
          system(*args)
        end
      end

      # Push all tags to a remote.
      # Notes:
      # - The ruby-git gem does not provide a stable API for pushing all tags across
      #   versions, so we intentionally shell out to `git push --tags` for both
      #   backends. Tests should stub this method in higher-level code to avoid
      #   mutating any repositories.
      #
      # @param remote [String, nil] The remote name. When nil or empty, uses the
      #   repository's default remote (same behavior as running `git push --tags`)
      #   which typically uses the current branch's upstream.
      # @return [Boolean] true if the system call reports success; false on failure
      def push_tags(remote)
        if @backend == :gem
          # The ruby-git gem does not expose a dedicated API for "--tags" consistently across versions.
          # Use a shell fallback even when the gem backend is active. Tests should stub this method.
          if remote && !remote.to_s.empty?
            system("git", "push", remote.to_s, "--tags")
          else
            system("git", "push", "--tags")
          end
        elsif remote && !remote.to_s.empty?
          system("git", "push", remote.to_s, "--tags")
        else
          system("git", "push", "--tags")
        end
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        false
      end

      # @return [String, nil] current branch name, or nil on error
      def current_branch
        if @backend == :gem
          @git.current_branch
        else
          out, status = Open3.capture2("git", "rev-parse", "--abbrev-ref", "HEAD")
          status.success? ? out.strip : nil
        end
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        nil
      end

      # @return [Array<String>] list of remote names
      def remotes
        if @backend == :gem
          @git.remotes.map(&:name)
        else
          out, status = Open3.capture2("git", "remote")
          status.success? ? out.split(/\r?\n/).map(&:strip).reject(&:empty?) : []
        end
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        []
      end

      # @return [Hash{String=>String}] remote name => fetch URL
      def remotes_with_urls
        if @backend == :gem
          @git.remotes.each_with_object({}) do |r, h|
            begin
              h[r.name] = r.url
            rescue StandardError => e
              Kettle::Dev.debug_error(e, __method__)
              # ignore
            end
          end
        else
          out, status = Open3.capture2("git", "remote", "-v")
          return {} unless status.success?

          urls = {}
          out.each_line do |line|
            # Example: origin https://github.com/me/repo.git (fetch)
            if line =~ /^(\S+)\s+(\S+)\s+\(fetch\)/
              urls[Regexp.last_match(1)] = Regexp.last_match(2)
            end
          end
          urls
        end
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        {}
      end

      # @param name [String]
      # @return [String, nil]
      def remote_url(name)
        if @backend == :gem
          r = @git.remotes.find { |x| x.name == name }
          r&.url
        else
          out, status = Open3.capture2("git", "config", "--get", "remote.#{name}.url")
          status.success? ? out.strip : nil
        end
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        nil
      end

      # Checkout the given branch
      # @param branch [String]
      # @return [Boolean]
      def checkout(branch)
        if @backend == :gem
          @git.checkout(branch)
          true
        else
          system("git", "checkout", branch.to_s)
        end
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        false
      end

      # Pull from a remote/branch
      # @param remote [String]
      # @param branch [String]
      # @return [Boolean]
      def pull(remote, branch)
        if @backend == :gem
          @git.pull(remote, branch)
          true
        else
          system("git", "pull", remote.to_s, branch.to_s)
        end
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        false
      end

      # Fetch a ref from a remote (or everything if ref is nil)
      # @param remote [String]
      # @param ref [String, nil]
      # @return [Boolean]
      def fetch(remote, ref = nil)
        if @backend == :gem
          if ref
            @git.fetch(remote, ref)
          else
            @git.fetch(remote)
          end
          true
        elsif ref
          system("git", "fetch", remote.to_s, ref.to_s)
        else
          system("git", "fetch", remote.to_s)
        end
      rescue StandardError => e
        Kettle::Dev.debug_error(e, __method__)
        false
      end
    end
  end
end
