# frozen_string_literal: true

# HOW TO UPDATE APPRAISALS (will run rubocop_gradual's autocorrect afterward):
#   bin/rake appraisals:update

# Lock/Unlock Deps Pattern
#
# Two often conflicting goals resolved!
#
#  - unlocked_deps.yml
#    - All runtime & dev dependencies, but does not have a `gemfiles/*.gemfile.lock` committed
#    - Uses an Appraisal2 "unlocked_deps" gemfile, and the current MRI Ruby release
#    - Know when new dependency releases will break local dev with unlocked dependencies
#    - Broken workflow indicates that new releases of dependencies may not work
#
#  - locked_deps.yml
#    - All runtime & dev dependencies, and has a `Gemfile.lock` committed
#    - Uses the project's main Gemfile, and the current MRI Ruby release
#    - Matches what contributors and maintainers use locally for development
#    - Broken workflow indicates that a new contributor will have a bad time
#
appraise "unlocked_deps" do
  gem "erb"
  eval_gemfile "modular/coverage.gemfile"
  eval_gemfile "modular/documentation.gemfile"
  eval_gemfile "modular/style.gemfile"
  eval_gemfile "modular/optional.gemfile"
  eval_gemfile "modular/recording/r3/recording.gemfile"
end

# Used for head (nightly) releases of ruby, truffleruby, and jruby.
# Split into discrete appraisals if one of them needs a dependency locked discretely.
appraise "head" do
  gem "erb"
  # See: https://github.com/vcr/vcr/issues/1057
  gem "cgi", ">= 0.5"
  gem "mutex_m", ">= 0.2"
  gem "stringio", ">= 3.0"
  gem "benchmark", "~> 0.4", ">= 0.4.1"
  eval_gemfile "modular/recording/r3/recording.gemfile"
end

# Used for current releases of ruby, truffleruby, and jruby.
# Split into discrete appraisals if one of them needs a dependency locked discretely.
appraise "current" do
  gem "erb"
  gem "mutex_m", ">= 0.2"
  gem "stringio", ">= 3.0"
  eval_gemfile "modular/recording/r3/recording.gemfile"
end

appraise "ruby-2-3" do
  # The cake is a lie. erb v2.2, the oldest release on RubyGems.org, was never compatible with Ruby 2.3.
  # This means we have no choice but to use the erb that shipped with Ruby 2.3
  # /opt/hostedtoolcache/Ruby/2.3.8/x64/lib/ruby/gems/2.3.0/gems/erb-2.2.2/lib/erb.rb:670:in `prepare_trim_mode': undefined method `match?' for "-":String (NoMethodError)
  # spec.add_development_dependency("erb", ">= 2.2")                                  # ruby >= 2.3.0, not SemVer, old rubies get dropped in a patch.
  eval_gemfile "modular/recording/r2.3/recording.gemfile"
end

appraise "ruby-2-4" do
  gem "erb"
  eval_gemfile "modular/recording/r2.4/recording.gemfile"
end

appraise "ruby-2-5" do
  gem "erb"
  eval_gemfile "modular/recording/r2.5/recording.gemfile"
end

appraise "ruby-2-6" do
  gem "erb"
  gem "mutex_m", "~> 0.2"
  gem "stringio", "~> 3.0"
  eval_gemfile "modular/recording/r2.5/recording.gemfile"
end

appraise "ruby-2-7" do
  gem "erb"
  gem "mutex_m", "~> 0.2"
  gem "stringio", "~> 3.0"
  eval_gemfile "modular/recording/r2.5/recording.gemfile"
end

appraise "ruby-3-0" do
  gem "erb"
  gem "mutex_m", "~> 0.2"
  gem "stringio", "~> 3.0"
  eval_gemfile "modular/recording/r3/recording.gemfile"
end

appraise "ruby-3-1" do
  # all versions of git gem are incompatible with truffleruby v23.0, syntactically.
  # So tests relying on the git gem are skipped, to avoid loading it.
  gem "erb"
  gem "mutex_m", "~> 0.2"
  gem "stringio", "~> 3.0"
  eval_gemfile "modular/recording/r3/recording.gemfile"
end

appraise "ruby-3-2" do
  # all versions of git gem are incompatible with truffleruby v23.1, syntactically.
  # So tests relying on the git gem are skipped, to avoid loading it.
  gem "erb"
  gem "mutex_m", "~> 0.2"
  gem "stringio", "~> 3.0"
  eval_gemfile "modular/recording/r3/recording.gemfile"
end

appraise "ruby-3-3" do
  eval_gemfile "modular/recording/r3/recording.gemfile"
  gem "erb"
  gem "mutex_m", "~> 0.2"
  gem "stringio", "~> 3.0"
end

# Only run security audit on the latest version of Ruby
appraise "audit" do
  gem "erb"
  gem "mutex_m", "~> 0.2"
  gem "stringio", "~> 3.0"
end

# Only run coverage on the latest version of Ruby
appraise "coverage" do
  gem "erb"
  gem "mutex_m", "~> 0.2"
  gem "stringio", "~> 3.0"
  eval_gemfile "modular/coverage.gemfile"
  eval_gemfile "modular/optional.gemfile"
  eval_gemfile "modular/recording/r3/recording.gemfile"
end

# Only run linter on the latest version of Ruby (but, in support of oldest supported Ruby version)
appraise "style" do
  gem "erb"
  gem "mutex_m", "~> 0.2"
  gem "stringio", "~> 3.0"
  eval_gemfile "modular/style.gemfile"
end
