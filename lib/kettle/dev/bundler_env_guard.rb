# frozen_string_literal: true

module Kettle
  module Dev
    module BundlerEnvGuard
      RESET_ENV_KEYS = %w[
        BUNDLE_BIN_PATH
        BUNDLE_FROZEN
        BUNDLE_GEMFILE
        BUNDLE_LOCKFILE
        BUNDLER_SETUP
        BUNDLER_VERSION
      ].freeze

      # Bundler uses these markers to restore the environment of the parent
      # bundle. They are not inert when a child explicitly selects another
      # Gemfile: Bundler can use BUNDLER_ORIG_BUNDLE_GEMFILE to reselect the
      # parent bundle. Clear the dynamic keys along with RESET_ENV_KEYS.
      RESET_ENV_PREFIXES = %w[
        BUNDLER_ORIG_
      ].freeze

      INERT_ENV_KEYS = %w[
        BUNDLE_DEBUG
        BUNDLE_DISABLE_CHECKSUM_VALIDATION
        BUNDLE_QUIET
        BUNDLE_SILENCE_DEPRECATIONS
        BUNDLE_SILENCE_ROOT_WARNING
        BUNDLE_SUPPRESS_INSTALL_USING_MESSAGES
        BUNDLE_VERBOSE
        BUNDLER_DEBUG
      ].freeze

      module_function

      def unbundled_env
        env = RESET_ENV_KEYS.each_with_object({}) do |key, result|
          result[key] = nil
        end
        ENV.each_key do |key|
          next unless RESET_ENV_PREFIXES.any? { |prefix| key.start_with?(prefix) }

          env[key] = nil
        end
        env
      end

      def warn_unexpected_env!(stream: $stderr)
        unexpected = unexpected_env_keys
        return if unexpected.empty?
        return if warned_unexpected_env?(unexpected)

        stream.puts(
          "[kettle-dev] Unexpected Bundler environment variable(s) present while preparing an unbundled subprocess: #{unexpected.join(", ")}. " \
            "If this variable is safe, add it to BundlerEnvGuard::INERT_ENV_KEYS; otherwise add it to RESET_ENV_KEYS."
        )
      end

      # rubocop:disable ThreadSafety/ClassInstanceVariable -- warning state is intentionally shared by module functions.
      def reset_warning_cache!
        @warned_unexpected_env_keys = {}
      end

      def unexpected_env_keys
        ENV.to_hash.keys.grep(/\ABUNDLE(?:R)?_/).reject { |key| expected_env_key?(key) }.sort
      end

      def expected_env_key?(key)
        RESET_ENV_KEYS.include?(key) ||
          INERT_ENV_KEYS.include?(key) ||
          RESET_ENV_PREFIXES.any? { |prefix| key.start_with?(prefix) }
      end

      def warned_unexpected_env?(keys)
        @warned_unexpected_env_keys ||= {}
        signature = keys.join("\0")
        return true if @warned_unexpected_env_keys[signature]

        @warned_unexpected_env_keys[signature] = true
        false
      end
      # rubocop:enable ThreadSafety/ClassInstanceVariable
    end
  end
end
