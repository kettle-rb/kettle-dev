# frozen_string_literal: true

require "optparse"
require "uri"
require "net/http"
require "openssl"

module Kettle
  module Dev
    # PreReleaseCLI: run pre-release checks before invoking full release workflow.
    # Currently validates Markdown image links resolve via HTTP(S) HEAD.
    #
    # Usage: Kettle::Dev::PreReleaseCLI.new(check_num: 1).run
    class PreReleaseCLI
      # Simple HTTP helpers for link validation
      module HTTP
        module_function

        # Perform HTTP HEAD against the given url.
        # Falls back to GET when HEAD is not allowed.
        # @param url_str [String]
        # @param limit [Integer] max redirects
        # @param timeout [Integer] per-request timeout seconds
        # @return [Boolean] true when successful (2xx) after following redirects
        def head_ok?(url_str, limit: 5, timeout: 10)
          uri = URI.parse(url_str)
          raise ArgumentError, "unsupported URI scheme: #{uri.scheme.inspect}" unless %w[http https].include?(uri.scheme)

          request = Net::HTTP::Head.new(uri)
          perform(uri, request, limit: limit, timeout: timeout)
        end

        # @api private
        def perform(uri, request, limit:, timeout:)
          raise ArgumentError, "too many redirects" if limit <= 0

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.read_timeout = timeout
          http.open_timeout = timeout
          http.ssl_timeout = timeout if http.respond_to?(:ssl_timeout=)
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?

          response = http.start { |h| h.request(request) }

          case response
          when Net::HTTPRedirection
            location = response["location"]
            return false unless location
            new_uri = URI.parse(location)
            new_uri = uri + location if new_uri.relative?
            head_ok?(new_uri.to_s, limit: limit - 1, timeout: timeout)
          when Net::HTTPSuccess
            true
          else
            if response.is_a?(Net::HTTPMethodNotAllowed)
              get_req = Net::HTTP::Get.new(uri)
              get_resp = http.start { |h| h.request(get_req) }
              return get_resp.is_a?(Net::HTTPSuccess)
            end
            false
          end
        rescue StandardError => e
          warn("[kettle-pre-release] HTTP error for #{uri}: #{e.class}: #{e.message}")
          false
        end
      end

      # Markdown parsing helpers
      module Markdown
        module_function

        # Extract unique remote HTTP(S) image URLs from markdown or HTML images.
        # @param text [String]
        # @return [Array<String>]
        def extract_image_urls_from_text(text)
          urls = []

          # Inline image syntax
          text.scan(/!\[[^\]]*\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)/) { |m| urls << m[0] }

          # Reference definitions
          ref_defs = {}
          text.scan(/^\s*\[([^\]]+)\]:\s*(\S+)/) { |m| ref_defs[m[0]] = m[1] }

          # Reference image usage
          text.scan(/!\[[^\]]*\]\[([^\]]+)\]/) do |m|
            id = m[0]
            url = ref_defs[id]
            urls << url if url
          end

          # HTML <img src="...">
          text.scan(/<img\b[^>]*\bsrc\s*=\s*\"([^\"]+)\"[^>]*>/i) { |m| urls << m[0] }
          text.scan(/<img\b[^>]*\bsrc\s*=\s*\'([^\']+)\'[^>]*>/i) { |m| urls << m[0] }

          urls.reject! { |u| u.nil? || u.strip.empty? }
          urls.select! { |u| u =~ %r{^https?://}i }
          urls.uniq
        end

        # Extract from files matching glob.
        # @param glob_pattern [String]
        # @return [Array<String>]
        def extract_image_urls_from_files(glob_pattern = "*.md")
          files = Dir.glob(glob_pattern)
          urls = files.flat_map do |f|
            begin
              extract_image_urls_from_text(File.read(f))
            rescue StandardError => e
              warn("[kettle-pre-release] Could not read #{f}: #{e.class}: #{e.message}")
              []
            end
          end
          urls.uniq
        end
      end

      # @param check_num [Integer] 1-based index to resume from
      def initialize(check_num: 1)
        @check_num = (check_num || 1).to_i
        @check_num = 1 if @check_num < 1
      end

      # Execute configured checks starting from @check_num.
      # @return [void]
      def run
        checks = []
        checks << method(:check_markdown_images!)

        start = @check_num
        raise ArgumentError, "check_num must be >= 1" if start < 1
        begin_idx = start - 1
        checks[begin_idx..-1].each_with_index do |check, i|
          idx = begin_idx + i + 1
          puts "[kettle-pre-release] Running check ##{idx} of #{checks.size}"
          check.call
        end
        nil
      end

      # Check 1: Validate Markdown image links
      # @return [void]
      def check_markdown_images!
        puts "[kettle-pre-release] Check 1: Validate Markdown image links (HTTP HEAD)"
        urls = Markdown.extract_image_urls_from_files("**/*.md")
        puts "[kettle-pre-release] Found #{urls.size} unique image URL(s)."
        failures = []
        urls.each do |url|
          print("  -> #{url} … ")
          ok = HTTP.head_ok?(url)
          if ok
            puts "OK"
          else
            puts "FAIL"
            failures << url
          end
        end
        if failures.any?
          warn("[kettle-pre-release] #{failures.size} image URL(s) failed validation:")
          failures.each { |u| warn("  - #{u}") }
          Kettle::Dev::ExitAdapter.abort("Image link validation failed")
        else
          puts "[kettle-pre-release] All image links validated."
        end
        nil
      end
    end
  end
end
