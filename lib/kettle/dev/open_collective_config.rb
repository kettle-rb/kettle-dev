# frozen_string_literal: true

require "yaml"

module Kettle
  module Dev
    # Shared utility for resolving Open Collective configuration for this repository.
    # Centralizes the logic for locating and reading .opencollective.yml and
    # for deriving the handle from environment or the YAML file.
    module OpenCollectiveConfig
      module_function

      # Absolute path to a .opencollective.yml
      # @param root [String, nil] optional project root to resolve against; when nil, uses this repo root
      # @return [String]
      def yaml_path(root = nil)
        return File.expand_path(".opencollective.yml", root) if root
        File.expand_path("../../../.opencollective.yml", __dir__)
      end

      # Determine the Open Collective handle.
      # Precedence:
      #   1) ENV["OPENCOLLECTIVE_HANDLE"] when set and non-empty
      #   2) .opencollective.yml key "collective" (or :collective)
      #
      # @param required [Boolean] when true, aborts the process if not found; when false, returns nil
      # @param root [String, nil] optional project root to look for .opencollective.yml
      # @return [String, nil] the handle, or nil when not required and not discoverable
      def handle(required: false, root: nil, strict: false)
        env = ENV["OPENCOLLECTIVE_HANDLE"]
        return env unless env.nil? || env.to_s.strip.empty?

        ypath = yaml_path(root)
        if strict
          yml = YAML.safe_load(File.read(ypath))
          if yml.is_a?(Hash)
            handle = yml["collective"] || yml[:collective] || yml["org"] || yml[:org]
            return handle.to_s unless handle.nil? || handle.to_s.strip.empty?
          end
        else
          if File.file?(ypath)
            begin
              yml = YAML.safe_load(File.read(ypath))
              if yml.is_a?(Hash)
                handle = yml["collective"] || yml[:collective] || yml["org"] || yml[:org]
                return handle.to_s unless handle.nil? || handle.to_s.strip.empty?
              end
            rescue StandardError => e
              Kettle::Dev.debug_error(e, __method__) if Kettle::Dev.respond_to?(:debug_error)
              # fall through to required check
            end
          end
        end

        if required
          Kettle::Dev::ExitAdapter.abort("ERROR: Open Collective handle not provided. Set OPENCOLLECTIVE_HANDLE or add 'collective: <handle>' to .opencollective.yml.")
        end
        nil
      end
    end
  end
end
