# frozen_string_literal: true

require "rubygems"

module Kettle
  module Dev
    # Unified gemspec reader using RubyGems loader instead of regex parsing.
    # Returns a Hash with all data used by this project from gemspecs.
    # Cache within the process to avoid repeated loads.
    class GemSpecReader
      DEFAULT_MINIMUM_RUBY = Gem::Version.new("1.8").freeze
      class << self
        # Load gemspec data for the project at root.
        # @param root [String]
        # @return [Hash]
        def load(root)
          gemspec_path = Dir.glob(File.join(root.to_s, "*.gemspec")).first
          spec = nil
          if gemspec_path && File.file?(gemspec_path)
            begin
              spec = Gem::Specification.load(gemspec_path)
            rescue StandardError
              spec = nil
            end
          end

          gem_name = spec&.name.to_s
          # minimum ruby version: derived from spec.required_ruby_version
          # Always an instance of Gem::Version
          min_ruby =
            begin
              # irb(main):004> Gem::Requirement.parse(spec.required_ruby_version)
              # => [">=", Gem::Version.new("2.3.0")]
              requirement = spec&.required_ruby_version
              if requirement
                tuple = Gem::Requirement.parse(requirement)
                tuple[1] # an instance of Gem::Version
              else
                # Default to a minimum of Ruby 1.8
                puts "WARNING: Minimum Ruby not detected"
                DEFAULT_MINIMUM_RUBY
              end
            rescue StandardError => e
              # Default to a minimum of Ruby 1.8
              puts "WARNING: Minimum Ruby detection failed: #{e.class}: #{e.message}"
              DEFAULT_MINIMUM_RUBY
            end

          homepage_val = spec&.homepage.to_s

          # Derive org/repo from homepage or git remote
          forge_org = nil
          gh_repo = nil
          if homepage_val && !homepage_val.empty?
            if (m = homepage_val.match(%r{github\.com[/:]([^/]+)/([^/]+)}i))
              forge_org = m[1]
              gh_repo = m[2].to_s.sub(/\.git\z/, "")
            end
          end
          if forge_org.nil?
            begin
              origin_out = IO.popen(["git", "-C", root.to_s, "remote", "get-url", "origin"], &:read)
              origin_out = origin_out.read if origin_out.respond_to?(:read)
              origin_url = origin_out.to_s.strip
              if (m = origin_url.match(%r{github\.com[/:]([^/]+)/([^/]+)}i))
                forge_org = m[1]
                gh_repo = m[2].to_s.sub(/\.git\z/, "")
              end
            rescue StandardError
              # ignore
            end
          end

          camel = lambda do |s|
            s.to_s.split(/[_-]/).map { |p| p.gsub(/\b([a-z])/) { Regexp.last_match(1).upcase } }.join
          end
          namespace = gem_name.to_s.split("-").map { |seg| camel.call(seg) }.join("::")
          namespace_shield = namespace.gsub("::", "%3A%3A")
          entrypoint_require = gem_name.to_s.tr("-", "/")
          gem_shield = gem_name.to_s.gsub("-", "--").gsub("_", "__")

          # Funding org detection (ENV, .opencollective.yml, fallback to forge_org)
          funding_org = ENV["FUNDING_ORG"].to_s.strip
          funding_org = ENV["OPENCOLLECTIVE_ORG"].to_s.strip if funding_org.empty?
          funding_org = ENV["OPENCOLLECTIVE_HANDLE"].to_s.strip if funding_org.empty?
          if funding_org.empty?
            begin
              oc_path = File.join(root.to_s, ".opencollective.yml")
              if File.file?(oc_path)
                txt = File.read(oc_path)
                if (m = txt.match(/\borg:\s*([\w\-]+)/i))
                  funding_org = m[1].to_s
                end
              end
            rescue StandardError
              # ignore
            end
          end
          funding_org = forge_org.to_s if funding_org.to_s.empty?

          {
            gemspec_path: gemspec_path,
            gem_name: gem_name,
            min_ruby: min_ruby, # Gem::Version instance
            homepage: homepage_val.to_s,
            gh_org: forge_org, # Might allow divergence from forge_org someday
            forge_org: forge_org,
            funding_org: funding_org,
            gh_repo: gh_repo,
            namespace: namespace,
            namespace_shield: namespace_shield,
            entrypoint_require: entrypoint_require,
            gem_shield: gem_shield,
            # Additional fields sourced from the gemspec for templating carry-over
            authors: Array(spec&.authors).compact.uniq,
            email: Array(spec&.email).compact.uniq,
            summary: spec&.summary.to_s,
            description: spec&.description.to_s,
            licenses: Array(spec&.licenses), # licenses will include any specified as license (singular)
            required_ruby_version: spec&.required_ruby_version, # Gem::Requirement instance
            require_paths: Array(spec&.require_paths),
            bindir: (spec&.bindir || "").to_s,
            executables: Array(spec&.executables),
          }
        end
      end
    end
  end
end
