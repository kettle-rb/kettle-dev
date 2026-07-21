# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "time"
require "uri"

module Kettle
  module Dev
    module GemCoopVersions
      CACHE_BUST_TTL_SECONDS = 15 * 60
      ENV_REFRESH = "KETTLE_GEM_COOP_REFRESH"
      ENV_MARKER_PATH = "KETTLE_GEM_COOP_CACHE_BUST_PATH"

      class << self
        def fetch(gem_name, version_hint: nil, refresh: false)
          cache_bust = refresh || env_refresh? || fresh_release_marker?(gem_name, version_hint)
          uri = versions_uri(gem_name, cache_bust: cache_bust)
          request = Net::HTTP::Get.new(uri)
          if cache_bust
            request["Cache-Control"] = "no-cache"
            request["Pragma"] = "no-cache"
          end
          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
            http.request(request)
          end
          return nil unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        end

        def mark_released(gem_name, version)
          return if gem_name.to_s.empty? || version.to_s.empty?

          path = marker_path
          data = read_marker(path)
          data["releases"] ||= {}
          data["releases"][gem_name.to_s] = {
            "version" => version.to_s,
            "released_at" => Time.now.utc.iso8601
          }
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, JSON.pretty_generate(data) << "\n")
        rescue => error
          warn("[kettle-dev] could not update gem.coop cache-bust marker: #{error.class}: #{error.message}") if Kettle::Dev::DEBUGGING
        end

        def marker_path
          configured = ENV.fetch(ENV_MARKER_PATH, "").to_s
          return configured unless configured.empty?

          state_home = ENV["XDG_STATE_HOME"]
          state_home = File.join(Dir.home, ".local", "state") if state_home.to_s.empty?
          File.join(state_home, "kettle-dev", "gem-coop-cache-bust.json")
        end

        private

        def versions_uri(gem_name, cache_bust:)
          uri = URI("https://gem.coop/api/v1/versions/#{gem_name}.json")
          uri.query = "_kettle_cache_bust=#{Time.now.to_i}" if cache_bust
          uri
        end

        def fresh_release_marker?(gem_name, version_hint)
          entry = read_marker(marker_path).fetch("releases", {})[gem_name.to_s]
          return false unless entry
          return false if version_hint && entry["version"].to_s != version_hint.to_s

          released_at = Time.iso8601(entry["released_at"].to_s)
          released_at >= Time.now.utc - CACHE_BUST_TTL_SECONDS
        rescue ArgumentError
          false
        end

        def read_marker(path)
          return {} unless File.file?(path)

          parsed = JSON.parse(File.read(path))
          parsed.is_a?(Hash) ? parsed : {}
        rescue JSON::ParserError
          {}
        end

        def env_refresh?
          ENV.fetch(ENV_REFRESH, "").match?(Kettle::Dev::ENV_TRUE_RE)
        end
      end
    end
  end
end
