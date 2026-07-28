# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

module Kettle
  module Dev
    class GemSourceProbe
      UNBUNDLED_ENV_KEYS = %w[
        BUNDLE_BIN_PATH
        BUNDLE_FROZEN
        BUNDLE_GEMFILE
        BUNDLE_LOCKFILE
        BUNDLER_SETUP
        BUNDLER_VERSION
        RUBYGEMS_GEMDEPS
        RUBYLIB
        RUBYOPT
      ].freeze

      def initialize(source_url:, ruby: Gem.ruby)
        @source_url = source_url
        @ruby = ruby
      end

      def available?(name, version)
        stderr = nil
        with_probe_gem_home do |gem_home|
          _stdout, stderr, status = Open3.capture3(
            probe_env(gem_home),
            "gem",
            "install",
            name,
            "-v",
            "= #{version}",
            "--source",
            source_url,
            "--clear-sources",
            "--ignore-dependencies",
            "--no-document",
            "--install-dir",
            gem_home
          )
          status.success?
        end
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

      def with_probe_gem_home
        base = File.join(Dir.pwd, "tmp")
        FileUtils.mkdir_p(base)
        Dir.mktmpdir("kettle-gem-source-probe-", base) do |gem_home|
          yield(gem_home)
        end
      end

      def probe_env(gem_home)
        unbundled_env.merge(
          "GEM_HOME" => gem_home,
          "GEM_PATH" => gem_home
        )
      end

      def unbundled_env
        UNBUNDLED_ENV_KEYS.each_with_object({}) do |key, env|
          env[key] = nil
        end
      end
    end
  end
end
