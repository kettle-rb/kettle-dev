# frozen_string_literal: true

require "rubygems"

module Kettle
  module Dev
    # Unified gemspec reader using RubyGems loader instead of regex parsing.
    # Returns a Hash with all data used by this project from gemspecs.
    # Cache within the process to avoid repeated loads.
    class GemSpecReader
      # Default minimum Ruby version to assume when a gemspec doesn't specify one.
      # @return [Gem::Version]
      DEFAULT_MINIMUM_RUBY = Gem::Version.new("1.8").freeze
      class << self
        # Load gemspec data for the project at root using RubyGems.
        # The reader is lenient: failures to load or missing fields are handled with defaults and warnings.
        #
        # @param root [String] project root containing a *.gemspec file
        # @return [Hash{Symbol=>Object}] a Hash of gem metadata used by templating and tasks
        # @option return [String, nil] :gemspec_path absolute path to gemspec or nil when not found
        # @option return [String] :gem_name gem name ("" when not derivable)
        # @option return [Gem::Version] :min_ruby minimum Ruby version derived or DEFAULT_MINIMUM_RUBY
        # @option return [String] :homepage homepage string (may be "")
        # @option return [String] :gh_org GitHub org (falls back to "kettle-rb")
        # @option return [String] :forge_org primary forge org (currently same as gh_org)
        # @option return [String, nil] :funding_org OpenCollective/org handle or nil when not discovered
        # @option return [String, nil] :gh_repo GitHub repo name, if discoverable
        # @option return [String] :namespace Ruby namespace derived from gem name (e.g., "Kettle::Dev")
        # @option return [String] :namespace_shield URL-escaped namespace for shields
        # @option return [String] :entrypoint_require require path for gem (e.g., "kettle/dev")
        # @option return [String] :gem_shield shield-safe gem name
        # @option return [Array<String>] :authors
        # @option return [Array<String>] :email
        # @option return [String] :summary
        # @option return [String] :description
        # @option return [Array<String>] :licenses includes both license and licenses values
        # @option return [Gem::Requirement, nil] :required_ruby_version
        # @option return [Array<String>] :require_paths
        # @option return [String] :bindir
        # @option return [Array<String>] :executables
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

          # Funding org (Open Collective handle) detection.
          # Precedence:
          #   1) OpenCollectiveConfig.disabled? - when true, funding_org is nil
          #   2) ENV["FUNDING_ORG"] when set and non-empty (unless already disabled above)
          #   3) OpenCollectiveConfig.handle(required: false)
          # Be lenient: allow nil when not discoverable, with a concise warning.
          begin
            # Check if Open Collective is explicitly disabled via environment variables
            if OpenCollectiveConfig.disabled?
              funding_org = nil
            else
              env_funding = ENV["FUNDING_ORG"]
              if env_funding && !env_funding.to_s.strip.empty?
                # FUNDING_ORG is set and non-empty; use it as-is (already filtered by opencollective_disabled?)
                funding_org = env_funding.to_s
              else
                # Preflight: if a YAML exists under the provided root, attempt to read it here so
                # unexpected file IO errors surface within this rescue block (see specs).
                oc_path = OpenCollectiveConfig.yaml_path(root)
                File.read(oc_path) if File.file?(oc_path)

                funding_org = OpenCollectiveConfig.handle(required: false, root: root)
                if funding_org.to_s.strip.empty?
                  Kernel.warn("kettle-dev: Could not determine funding org.\n  - Options:\n    * Set ENV['FUNDING_ORG'] to your funding handle, or 'false' to disable.\n    * Or set ENV['OPENCOLLECTIVE_HANDLE'].\n    * Or add .opencollective.yml with: collective: <handle> (or org: <handle>).\n    * Or proceed without funding if not applicable.")
                  funding_org = nil
                end
              end
            end
          rescue StandardError => error
            Kettle::Dev.debug_error(error, __method__)
            # In an unexpected exception path, escalate to a domain error to aid callers/specs
            raise Kettle::Dev::Error, "Unable to determine funding org: #{error.message}"
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

        # Derive the forge organization and origin repository name using homepage or git remotes.
        # Prefers GitHub-style URLs.
        #
        # @param homepage_val [String] the homepage string from the gemspec (may be empty)
        # @return [Hash{Symbol=>String,nil}] keys: :forge_org, :origin_repo (both may be nil when not discoverable)
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
