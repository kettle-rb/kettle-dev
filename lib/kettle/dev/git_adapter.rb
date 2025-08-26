# frozen_string_literal: true

module Kettle
  module Dev
    # Minimal Git adapter used by kettle-dev to avoid invoking live shell commands
    # directly from the library code. In tests, mock this adapter's methods to
    # prevent any real network or repository mutations.
    #
    # This adapter requires the 'git' gem at runtime and does not shell out to
    # the system git. Specs should stub the git gem API to avoid real pushes.
    #
    # Public API is intentionally tiny and only includes what we need right now.
    class GitAdapter
      # Create a new adapter rooted at the current working directory.
      # @return [void]
      def initialize
        begin
          require "git"
          @git = ::Git.open(Dir.pwd)
        rescue LoadError
          raise Kettle::Dev::Error, "The 'git' gem is required at runtime. Please add it as a dependency."
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
        # git gem supports force: true option on push
        begin
          if remote
            @git.push(remote, branch, force: force)
          else
            # Default remote according to repo config
            @git.push(nil, branch, force: force)
          end
          true
        rescue StandardError
          false
        end
      end
    end
  end
end
