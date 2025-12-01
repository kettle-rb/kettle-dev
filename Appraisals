# frozen_string_literal: true
# kettle-dev:freeze
# To retain chunks of comments & code during kettle-dev templating:
# Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
# kettle-dev will then preserve content between those markers across template runs.
# kettle-dev:unfreeze
# HOW TO UPDATE APPRAISALS (will run rubocop_gradual's autocorrect afterward):
#   bin/rake appraisals:update

# Lock/Unlock Deps Pattern
#
# Two often conflicting goals resolved!
#  - unlocked_deps.yml
#    - All runtime & dev dependencies, but does not have a `gemfiles/*.gemfile.lock` committed
#    - Uses an Appraisal2 "unlocked_deps" gemfile, and the current MRI Ruby release
#    - Know when new dependency releases will break local dev with unlocked dependencies
#    - Broken workflow indicates that new releases of dependencies may not work
#  - locked_deps.yml
#    - All runtime & dev dependencies, and has a `Gemfile.lock` committed
#    - Uses the project's main Gemfile, and the current MRI Ruby release
#    - Matches what contributors and maintainers use locally for development
#    - Broken workflow indicates that a new contributor will have a bad time
appraise("unlocked_deps") {
  eval_gemfile("modular/coverage.gemfile")
  eval_gemfile("modular/documentation.gemfile")
  eval_gemfile("modular/optional.gemfile")
  eval_gemfile("modular/recording/r3/recording.gemfile")
  eval_gemfile("modular/style.gemfile")
  eval_gemfile("modular/x_std_libs.gemfile")
}

# Used for head (nightly) releases of ruby, truffleruby, and jruby.
# Split into discrete appraisals if one of them needs a dependency locked discretely.
appraise("head") {
  gem("benchmark", "~> 0.4", ">= 0.4.1")
  # Why is cgi gem here? See: https://github.com/vcr/vcr/issues/1057
  gem("cgi", ">= 0.5")
  eval_gemfile("modular/recording/r3/recording.gemfile")
  eval_gemfile("modular/x_std_libs.gemfile")
}

# Used for current releases of ruby, truffleruby, and jruby.
# Split into discrete appraisals if one of them needs a dependency locked discretely.
appraise("current") {
  eval_gemfile("modular/recording/r3/recording.gemfile")
  eval_gemfile("modular/x_std_libs.gemfile")
}

# Test current Rubies against head versions of runtime dependencies
appraise("dep-heads") {
  eval_gemfile("modular/runtime_heads.gemfile")
}

appraise("ruby-2-3") {
  eval_gemfile("modular/recording/r2.3/recording.gemfile")
  eval_gemfile("modular/x_std_libs/r2.3/libs.gemfile")
}

appraise("ruby-2-4") {
  eval_gemfile("modular/recording/r2.4/recording.gemfile")
  eval_gemfile("modular/x_std_libs/r2.4/libs.gemfile")
}

appraise("ruby-2-5") {
  eval_gemfile("modular/recording/r2.5/recording.gemfile")
  eval_gemfile("modular/x_std_libs/r2.6/libs.gemfile")
}

appraise("ruby-2-6") {
  eval_gemfile("modular/recording/r2.5/recording.gemfile")
  eval_gemfile("modular/x_std_libs/r2.6/libs.gemfile")
}

appraise("ruby-2-7") {
  eval_gemfile("modular/recording/r2.5/recording.gemfile")
  eval_gemfile("modular/x_std_libs/r2/libs.gemfile")
}

appraise("ruby-3-0") {
  eval_gemfile("modular/recording/r3/recording.gemfile")
  eval_gemfile("modular/x_std_libs/r3.1/libs.gemfile")
}

appraise("ruby-3-1") {
  eval_gemfile("modular/recording/r3/recording.gemfile")
  eval_gemfile("modular/x_std_libs/r3.1/libs.gemfile")
}

appraise("ruby-3-2") {
  eval_gemfile("modular/recording/r3/recording.gemfile")
  eval_gemfile("modular/x_std_libs/r3/libs.gemfile")
}

appraise("ruby-3-3") {
  eval_gemfile("modular/recording/r3/recording.gemfile")
  eval_gemfile("modular/x_std_libs/r3/libs.gemfile")
}

# Only run security audit on the latest version of Ruby
appraise("audit") {
  eval_gemfile("modular/x_std_libs.gemfile")
}

# Only run coverage on the latest version of Ruby
appraise("coverage") {
  eval_gemfile("modular/coverage.gemfile")
  eval_gemfile("modular/optional.gemfile")
  eval_gemfile("modular/recording/r3/recording.gemfile")
  eval_gemfile("modular/x_std_libs.gemfile")
  # Normally style is included in coverage runs only, but we need it for the test suite to get full coverage
  eval_gemfile("modular/style.gemfile")
}

# Only run linter on the latest version of Ruby (but, in support of oldest supported Ruby version)
appraise("style") {
  eval_gemfile("modular/style.gemfile")
  eval_gemfile("modular/x_std_libs.gemfile")
}
