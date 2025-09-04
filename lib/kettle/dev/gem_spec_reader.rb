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
            rescue StandardError => e
              Kettle::Dev.debug_error(e, __method__)
              spec = nil
            end
          end

          gem_name = spec&.name.to_s
          if gem_name.nil? || gem_name.strip.empty?
            # Be lenient here for tasks that can proceed without gem_name (e.g., choosing destination filenames).
            Kernel.warn("kettle-dev: Could not derive gem name. Ensure a valid <name> is set in the gemspec.\n  - Tip: set the gem name in your .gemspec file (spec.name).\n  - Path searched: #{gemspec_path || "(none found)"}")
            gem_name = ""
          end
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
              puts "WARNING: Minimum Ruby detection failed:"
              Kettle::Dev.debug_error(e, __method__)
              # Default to a minimum of Ruby 1.8
              DEFAULT_MINIMUM_RUBY
            end

          homepage_val = spec&.homepage.to_s

          # Derive org/repo from homepage or git remote
          forge_info = derive_forge_and_origin_repo(homepage_val)
          forge_org = forge_info[:forge_org]
          gh_repo = forge_info[:origin_repo]
          if forge_org.to_s.empty?
            Kernel.warn("kettle-dev: Could not determine forge org from spec.homepage or git remote.\n  - Ensure gemspec.homepage is set to a GitHub URL or that the git remote 'origin' points to GitHub.\n  - Example homepage: https://github.com/<org>/<repo>\n  - Proceeding with default org: kettle-rb.")
            forge_org = "kettle-rb"
          end

          camel = lambda do |s|
            s.to_s.split(/[_-]/).map { |p| p.gsub(/\b([a-z])/) { Regexp.last_match(1).upcase } }.join
          end
          namespace = gem_name.to_s.split("-").map { |seg| camel.call(seg) }.join("::")
          namespace_shield = namespace.gsub("::", "%3A%3A")
          entrypoint_require = gem_name.to_s.tr("-", "/")
          gem_shield = gem_name.to_s.gsub("-", "--").gsub("_", "__")

          # Funding org detection with bypass support.
          # By default a funding org must be discoverable, unless explicitly disabled by ENV['FUNDING_ORG'] == 'false'.
          funding_org_env = ENV["FUNDING_ORG"]
          funding_org = funding_org_env.to_s.strip
          begin
            # Handle bypass: allow explicit string 'false' (any case) to disable funding org requirement.
            if funding_org_env && funding_org_env.to_s.strip.casecmp("false").zero?
              funding_org = nil
            else
              funding_org = ENV["OPENCOLLECTIVE_HANDLE"].to_s.strip if funding_org.empty?
              if funding_org.to_s.empty?
                oc_path = File.join(root.to_s, ".opencollective.yml")
                if File.file?(oc_path)
                  txt = File.read(oc_path)
                  if (m = txt.match(/\borg:\s*([\w\-]+)/i))
                    funding_org = m[1].to_s
                  end
                end
              end
              # Be lenient: if funding_org cannot be determined, do not raise — leave it nil and warn.
              if funding_org.to_s.empty?
                Kernel.warn("kettle-dev: Could not determine funding org.\n  - Options:\n    * Set ENV['FUNDING_ORG'] to your funding handle (e.g., 'opencollective-handle').\n    * Or set ENV['OPENCOLLECTIVE_HANDLE'].\n    * Or add .opencollective.yml with: org: <handle>\n    * Or bypass by setting ENV['FUNDING_ORG']=false for gems without funding.")
                funding_org = nil
              end
            end
          rescue StandardError => error
            Kettle::Dev.debug_error(error, __method__)
            raise Error, "Unable to determine funding org from env or .opencollective.yml.\n\tError was: #{error.class}: #{error.message}"
          end

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

        private

        def derive_forge_and_origin_repo(homepage_val)
          forge_info = {}

          if homepage_val && !homepage_val.empty?
            m = homepage_val.match(%r{github\.com[/:]([^/]+)/([^/]+)}i)

            if m
              forge_info[:forge_org] = m[1]
              forge_info[:origin_repo] = m[2].to_s.sub(/\.git\z/, "")
            end
          end

          if forge_info[:forge_org].nil? || forge_info[:forge_org].to_s.empty?
            begin
              ga = Kettle::Dev::GitAdapter.new
              origin_url = ga.remote_url("origin") || ga.remotes_with_urls["origin"]
              origin_url = origin_url.to_s.strip
              if (m = origin_url.match(%r{github\.com[/:]([^/]+)/([^/]+)}i))
                forge_info[:forge_org] = m[1]
                forge_info[:origin_repo] = m[2].to_s.sub(/\.git\z/, "")
              end
            rescue StandardError => error
              Kettle::Dev.debug_error(error, __method__)
              # be lenient here; actual error raising will occur in caller if required
            end
          end

          forge_info
        end
      end
    end
  end
end
