# kettle-dev:freeze
# To retain chunks of comments & code during kettle-dev templating:
# Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
# kettle-dev will then preserve content between those markers across template runs.
# kettle-dev:unfreeze

require "kettle/soup/cover/config"

# Minimum coverage thresholds are set by kettle-soup-cover.
# It is controlled by ENV variables, which are set in .envrc and loaded via `direnv allow`
# If the values for minimum coverage need to change, they should be changed both there,
#   and in 2 places in .github/workflows/coverage.yml.
SimpleCov.start do
  track_files "lib/**/*.rb"
  track_files "lib/**/*.rake"
  track_files "exe/*.rb"

  # Version *is* tested (see spec/kettle/dev/version_spec.rb).
  # Due to early loading, the Version class can't be tracked by SimpleCov.
  # So we disable coverage here.
  add_filter "lib/kettle/dev/version.rb"
end
