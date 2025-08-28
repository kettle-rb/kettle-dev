# coding: utf-8
# frozen_string_literal: true

gem_version =
  if RUBY_VERSION >= "3.1" # rubocop:disable Gemspec/RubyVersionGlobalsUsage
    # Loading Version into an anonymous module allows version.rb to get code coverage from SimpleCov!
    # See: https://github.com/simplecov-ruby/simplecov/issues/557#issuecomment-2630782358
    # See: https://github.com/panorama-ed/memo_wise/pull/397
    Module.new.tap { |mod| Kernel.load("#{__dir__}/lib/kettle/dev/version.rb", mod) }::Kettle::Dev::Version::VERSION
  else
    # NOTE: Use __FILE__ or __dir__ until removal of Ruby 1.x support
    # __dir__ introduced in Ruby 1.9.1
    # lib = File.expand_path("../lib", __FILE__)
    lib = File.expand_path("lib", __dir__)
    $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
    require "kettle/dev/version"
    Kettle::Dev::Version::VERSION
  end

Gem::Specification.new do |spec|
  spec.name = "kettle-dev"
  spec.version = gem_version
  spec.authors = ["Peter H. Boling"]
  spec.email = ["floss@galtzo.com"]

  spec.summary = "🍲 A kettle-rb meta tool to streamline development and testing"
  spec.description = "🍲 Kettle::Dev is a meta tool from kettle-rb to streamline development and testing. " \
    "Acts as a shim dependency, pulling in many other dependencies, to give you OOTB productivity with a RubyGem, or Ruby app project. " \
    "Configures a complete set of Rake tasks, for all the libraries is brings in, so they arrive ready to go. " \
    "Fund overlooked open source projects - bottom of stack, dev/test dependencies: floss-funding.dev"
  spec.homepage = "https://github.com/kettle-rb/kettle-dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.3.0"

  # Linux distros often package gems and securely certify them independent
  #   of the official RubyGem certification process. Allowed via ENV["SKIP_GEM_SIGNING"]
  # Ref: https://gitlab.com/oauth-xx/version_gem/-/issues/3
  # Hence, only enable signing if `SKIP_GEM_SIGNING` is not set in ENV.
  # See CONTRIBUTING.md
  unless ENV.include?("SKIP_GEM_SIGNING")
    user_cert = "certs/#{ENV.fetch("GEM_CERT_USER", ENV["USER"])}.pem"
    cert_file_path = File.join(__dir__, user_cert)
    cert_chain = cert_file_path.split(",")
    cert_chain.select! { |fp| File.exist?(fp) }
    if cert_file_path && cert_chain.any?
      spec.cert_chain = cert_chain
      if $PROGRAM_NAME.end_with?("gem") && ARGV[0] == "build"
        spec.signing_key = File.join(Gem.user_home, ".ssh", "gem-private_key.pem")
      end
    end
  end

  spec.metadata["homepage_uri"] = "https://#{spec.name.tr("_", "-")}.galtzo.com/"
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/v#{spec.version}"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/v#{spec.version}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "https://www.rubydoc.info/gems/#{spec.name}/#{spec.version}"
  spec.metadata["funding_uri"] = "https://github.com/sponsors/pboling"
  spec.metadata["wiki_uri"] = "#{spec.homepage}/wiki"
  spec.metadata["news_uri"] = "https://www.railsbling.com/tags/#{spec.name}"
  spec.metadata["discord_uri"] = "https://discord.gg/3qme4XHNKN"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files are part of the released package.
  # Include all sources required by install/template tasks so they work from the shipped gem.
  spec.files = Dir[
    # Executables and tasks
    "exe/*",
    "lib/**/*.rb",
    "lib/**/*.rake",
    # Signatures
    "sig/**/*.rbs",
    # Template-able project assets
    ".devcontainer/**/*",
    ".github/**/*",
    ".git-hooks/*",
    ".qlty/**/*",
    "gemfiles/modular/*.gemfile",
    # Example templates
    "*.example",
    "lib/**/*.example",
    # Root files used by template tasks
    ".envrc",
    ".gitignore",
    ".opencollective.yml",
    ".rspec",
    ".rubocop.yml",
    ".simplecov",
    ".tool-versions",
    ".yard_gfm_support.rb",
    ".yardopts",
    "Appraisal.root.gemfile",
    "Appraisals",
    "CHANGELOG.md",
    "CITATION.cff",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "Gemfile",
    "README.md",
    "RUBOCOP.md",
    "SECURITY.md",
    ".junie/guidelines.md",
    ".junie/guidelines-rbs.md",
  ]
  # Automatically included with gem package, normally no need to list again in files.
  # But this gem acts as a pseudo-template, so we include some in both places.
  spec.extra_rdoc_files = Dir[
    # Files (alphabetical)
    "CHANGELOG.md",
    "CITATION.cff",
    "CODE_OF_CONDUCT.md",
    "CONTRIBUTING.md",
    "LICENSE.txt",
    "README.md",
    "REEK",
    "RUBOCOP.md",
    "SECURITY.md",
  ]
  spec.rdoc_options += [
    "--title",
    "#{spec.name} - #{spec.summary}",
    "--main",
    "README.md",
    "--exclude",
    "^sig/",
    "--line-numbers",
    "--inline-source",
    "--quiet",
  ]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  # files listed are relative paths from bindir above.
  spec.executables = [
    "kettle-commit-msg",
    "kettle-readme-backers",
    "kettle-release",
  ]

  # Utilities
  spec.add_dependency("version_gem", "~> 1.1", ">= 1.1.8")              # ruby >= 2.2.0

  # Security
  spec.add_dependency("bundler-audit", "~> 0.9.2")                      # ruby >= 2.0.0

  # Tasks
  spec.add_dependency("rake", "~> 13.0")                                # ruby >= 2.2.0

  # Debugging
  spec.add_dependency("require_bench", "~> 1.0", ">= 1.0.4")            # ruby >= 2.2.0

  # Testing
  spec.add_dependency("appraisal2", "~> 3.0")                           # ruby >= 1.8.7, for testing against multiple versions of dependencies
  spec.add_dependency("kettle-test", "~> 1.0")                          # ruby >= 2.3
  spec.add_dependency("rspec-pending_for")                                # ruby >= 2.3, used to skip specs on incompatible Rubies

  # Releasing
  spec.add_dependency("ruby-progressbar", "~> 1.13")                    # ruby >= 0
  spec.add_dependency("stone_checksums", "~> 1.0", ">= 1.0.2")          # ruby >= 2.2.0

  # Git integration (optional)
  # The 'git' gem is optional; kettle-dev falls back to shelling out to `git` if it is not present.
  # The current release of the git gem depends on activesupport, which makes it too heavy to depend on directly
  # Compatibility with the git gem is tested via appraisals instead.
  # spec.add_dependency("git", ">= 1.19.1")                               # ruby >= 2.3

  # Development tasks
  # The cake is a lie. erb v2.2, the oldest release on RubyGems.org, was never compatible with Ruby 2.3.
  # This means we have no choice but to use the erb that shipped with Ruby 2.3
  # /opt/hostedtoolcache/Ruby/2.3.8/x64/lib/ruby/gems/2.3.0/gems/erb-2.2.2/lib/erb.rb:670:in `prepare_trim_mode': undefined method `match?' for "-":String (NoMethodError)
  # spec.add_development_dependency("erb", ">= 2.2")                                  # ruby >= 2.3.0, not SemVer, old rubies get dropped in a patch.
  spec.add_dependency("gitmoji-regex", "~> 1.0", ">= 1.0.3")            # ruby >= 2.3.0

  # NOTE: It is preferable to list development dependencies in the gemspec due to increased
  #       visibility and discoverability on RubyGems.org.
  #       However, development dependencies in gemspec will install on
  #       all versions of Ruby that will run in CI.
  #       This gem, and its gemspec runtime dependencies, will install on Ruby down to 2.3.x.
  #       This gem, and its gemspec development dependencies, will install on Ruby down to 2.3.x.
  #       This is because in CI easy installation of Ruby, via setup-ruby, is for >= 2.3.
  #       Thus, dev dependencies in gemspec must have
  #
  #       required_ruby_version ">= 2.3" (or lower)
  #
  #       Development dependencies that require strictly newer Ruby versions should be in a "gemfile",
  #       and preferably a modular one (see gemfiles/modular/*.gemfile).
end
