# frozen_string_literal: true

# Setup Yard
begin
  require "yard"

  YARD::Rake::YardocTask.new(:yard) do |t|
    t.files = [
      # Source Splats (alphabetical)
      "lib/**/*.rb",
      "-", # source and extra docs are separated by "-"
      # Extra Files (alphabetical)
      "*.cff",
      "*.md",
      "*.txt",
      "checksums/**/*.sha256",
      "checksums/**/*.sha512",
      "REEK",
      "sig/**/*.rbs",
    ]

    # No need for this, due to plugin load in .yardopts
    # require "yard-junk/rake"
    # YardJunk::Rake.define_task
  end
  Kettle::Dev.register_default("yard")
rescue LoadError
  warn("[kettle-dev][yard.rake] failed to load yard") if Kettle::Dev::DEBUGGING
  desc("(stub) yard is unavailable")
  task(:yard) do
    warn("NOTE: yard isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end
