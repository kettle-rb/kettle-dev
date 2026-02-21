# frozen_string_literal: true

# Setup Yard
begin
  require "yard"

  # Load yard-fence rake task if available (provides yard:fence:prepare)
  # NOTE: yard-fence >= 0.9 auto-registers its rake task when Rake is available,
  # so this explicit require may be redundant. We keep it for backward compatibility
  # with older yard-fence versions that don't auto-register.
  # The yard:fence:prepare task handles:
  # - Cleaning docs/ directory (if YARD_FENCE_CLEAN_DOCS=true)
  # - Preparing tmp/yard-fence/ with sanitized markdown files
  begin
    require "yard/fence/rake_task"
    # Only create if not already defined (yard-fence may have auto-registered)
    Yard::Fence::RakeTask.new unless Rake::Task.task_defined?("yard:fence:prepare")
  rescue LoadError
    # yard-fence not available or doesn't have rake_task - that's fine
  end

  YARD::Rake::YardocTask.new(:yard) do |t|
    t.files = [
      # Source Splats (alphabetical)
      "lib/**/*.rb",
      "-", # source and extra docs are separated by "-"
      # Extra Files (alphabetical)
      "*.cff",
      "*.md",
      "*.txt",
      # NOTE: checksums/**/* removed - it's in .yardignore and was causing
      # file.<gem>.html pages to be generated for each checksum file
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
