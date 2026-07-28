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

      INERT_ENV_KEYS = %w[
        BUNDLE_DEBUG
        BUNDLE_QUIET
        BUNDLE_SILENCE_DEPRECATIONS
        BUNDLE_SILENCE_ROOT_WARNING
        BUNDLE_SUPPRESS_INSTALL_USING_MESSAGES
        BUNDLE_VERBOSE
      ].freeze

      INERT_ENV_PREFIXES = %w[
        BUNDLER_ORIG_
      ].freeze

      module_function

      def unbundled_env
        RESET_ENV_KEYS.each_with_object({}) do |key, env|
          env[key] = nil
        end
      end

      def warn_unexpected_env!(stream: $stderr)
        unexpected = unexpected_env_keys
        return if unexpected.empty?
        return if @warned_unexpected_env_keys == unexpected

        @warned_unexpected_env_keys = unexpected
        stream.puts(
          "[kettle-dev] Unexpected Bundler environment variable(s) present while preparing an unbundled subprocess: #{unexpected.join(", ")}. " \
            "If this variable is safe, add it to BundlerEnvGuard::INERT_ENV_KEYS; otherwise add it to RESET_ENV_KEYS."
        )
      end

      def unexpected_env_keys
        ENV.to_hash.keys.grep(/\ABUNDLE(?:R)?_/).reject { |key| expected_env_key?(key) }.sort
      end

      def expected_env_key?(key)
        RESET_ENV_KEYS.include?(key) ||
          INERT_ENV_KEYS.include?(key) ||
          INERT_ENV_PREFIXES.any? { |prefix| key.start_with?(prefix) }
      end
    end
  end
end
