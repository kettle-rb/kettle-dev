# frozen_string_literal: true

require "open3"

module Kettle
  module Dev
    module ReleaseSecrets
      class Provider
        def gem_signing_passphrase
          nil
        end

        def rubygems_otp
          nil
        end
      end

      class OnePassword < Provider
        PROVIDER_NAMES = %w[1password onepassword op].freeze
        DEFAULTS = {
          "item" => "Rubygems",
          "gem_signing_passphrase_field" => "GEM-SIGN-PASSPHRASE",
          "rubygems_otp_field" => "one-time password"
        }.freeze

        def self.configured?(name)
          PROVIDER_NAMES.include?(name.to_s.downcase)
        end

        def initialize(config)
          @config = DEFAULTS.merge(config || {})
          @gem_signing_passphrase = nil
          @gem_signing_passphrase_loaded = false
        end

        def gem_signing_passphrase
          return @gem_signing_passphrase if @gem_signing_passphrase_loaded

          return cached_gem_signing_passphrase if cached_gem_signing_passphrase?

          reference = string_config("gem_signing_passphrase_reference")
          value = if reference.empty?
            item_field("gem_signing_passphrase_field")
          else
            read_reference(reference)
          end

          @gem_signing_passphrase = value
          @gem_signing_passphrase_loaded = true
          value
        end

        def rubygems_otp
          reference = string_config("rubygems_otp_reference")
          return read_reference(reference) unless reference.empty?

          item = required_config("item")
          argv = ["op", "item", "get", item, "--otp"]
          account = string_config("account")
          argv.concat(["--account", account]) unless account.empty?
          run_op(argv, purpose: "RubyGems OTP")
        end

        private

        attr_reader :config

        def cached_gem_signing_passphrase?
          %w[cached family kettle-family].include?(string_config("gem_signing_passphrase_source").downcase)
        end

        def cached_gem_signing_passphrase
          value = ENV.fetch("KETTLE_RELEASE_GEM_SIGNING_PASSPHRASE", "").to_s
          raise Error, "cached gem signing passphrase was requested but KETTLE_RELEASE_GEM_SIGNING_PASSPHRASE is empty" if value.empty?

          value
        end

        def item_field(field_key)
          item = required_config("item")
          field = required_config(field_key)
          argv = ["op", "item", "get", item, "--fields", "label=#{field}", "--reveal"]
          account = string_config("account")
          argv.concat(["--account", account]) unless account.empty?
          run_op(argv, purpose: field_key.tr("_", " "))
        end

        def read_reference(reference)
          argv = ["op", "read", reference]
          account = string_config("account")
          argv.concat(["--account", account]) unless account.empty?
          run_op(argv, purpose: "secret reference")
        end

        def run_op(argv, purpose:)
          stdout, stderr, status = Open3.capture3(*argv)
          return stdout.to_s.strip if status.success? && !stdout.to_s.strip.empty?

          details = stderr.to_s.strip
          details = "op exited #{status.exitstatus}" if details.empty?
          raise Error, "1Password #{purpose} lookup failed: #{details}"
        rescue Errno::ENOENT
          raise Error, "1Password CLI executable `op` was not found"
        end

        def required_config(key)
          value = string_config(key)
          raise Error, "1Password release secrets require #{key}" if value.empty?

          value
        end

        def string_config(key)
          config.fetch(key, "").to_s
        end
      end

      class Factory
        ENV_KEYS = {
          "account" => "KETTLE_RELEASE_1PASSWORD_ACCOUNT",
          "item" => "KETTLE_RELEASE_1PASSWORD_ITEM",
          "gem_signing_passphrase_field" => "KETTLE_RELEASE_1PASSWORD_GEM_SIGNING_PASSPHRASE_FIELD",
          "rubygems_otp_field" => "KETTLE_RELEASE_1PASSWORD_RUBYGEMS_OTP_FIELD",
          "gem_signing_passphrase_reference" => "KETTLE_RELEASE_1PASSWORD_GEM_SIGNING_PASSPHRASE_REFERENCE",
          "rubygems_otp_reference" => "KETTLE_RELEASE_1PASSWORD_RUBYGEMS_OTP_REFERENCE",
          "gem_signing_passphrase_source" => "KETTLE_RELEASE_GEM_SIGNING_PASSPHRASE_SOURCE"
        }.freeze

        def self.build(provider_name: nil, config: nil)
          name = provider_name.to_s.empty? ? ENV.fetch("KETTLE_RELEASE_SECRETS_PROVIDER", "") : provider_name.to_s
          return Provider.new if name.empty? || name == "interactive"
          return OnePassword.new(env_config.merge(config || {})) if OnePassword.configured?(name)

          raise Error, "unsupported release secrets provider #{name.inspect}"
        end

        def self.env_config
          ENV_KEYS.each_with_object({}) do |(key, env_key), memo|
            value = ENV.fetch(env_key, "").to_s
            memo[key] = value unless value.empty?
          end
        end
      end
    end
  end
end
