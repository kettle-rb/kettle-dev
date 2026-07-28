# frozen_string_literal: true

require "open3"

module Kettle
  module Dev
    class GemSourceProbe
      UNBUNDLED_ENV_KEYS = %w[
        BUNDLE_BIN_PATH
        BUNDLE_FROZEN
        BUNDLER_VERSION
        RUBYOPT
      ].freeze

      def initialize(source_url:, ruby: Gem.ruby)
        @source_url = source_url
        @ruby = ruby
      end

      def available?(name, version)
        _stdout, stderr, status = Open3.capture3(unbundled_env, ruby, "-e", self.class.bundler_inline_script(name: name, version: version, source_url: source_url))
        status.success?
      rescue SystemCallError => error
        raise Error, "Could not verify #{name} #{version} from #{source_url}: #{error.message}"
      ensure
        warn(stderr) if ENV["KETTLE_DEV_DEBUG"] == "true" && stderr && !stderr.empty?
      end

      def self.bundler_inline_script(name:, version:, source_url:)
        <<~RUBY
          # frozen_string_literal: true

          require "bundler/inline"

          gem_name = #{name.dump}
          version = #{version.dump}

          gemfile(true) do
            source #{source_url.dump}
            gem gem_name, "= \#{version}", require: false
          end

          spec = Gem::Specification.find_all_by_name(gem_name, "= \#{version}").first
          abort("resolved no \#{gem_name} \#{version} spec from #{source_url}") unless spec
          puts "Validated \#{gem_name} \#{version} from #{source_url}"
        RUBY
      end

      private

      attr_reader :source_url, :ruby

      def unbundled_env
        UNBUNDLED_ENV_KEYS.each_with_object({}) do |key, env|
          env[key] = nil
        end.merge(
          "BUNDLE_GEMFILE" => nil,
          "BUNDLE_LOCKFILE" => nil
        )
      end
    end
  end
end
