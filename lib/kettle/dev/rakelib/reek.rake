# frozen_string_literal: true

# Setup Reek
begin
  require "reek/rake/task"

  Reek::Rake::Task.new do |t|
    t.fail_on_error = true
    t.verbose = false
    t.source_files = "{lib,spec,tests}/**/*.rb"
  end

  # Store current Reek output into REEK file
  require "open3"
  desc("Run reek and store the output into the REEK file")
  task("reek:update") do
    # Run via Bundler if available to ensure the right gem version is used
    cmd = %w[bundle exec reek]

    output, status = Open3.capture2e(*cmd)

    File.write("REEK", output)

    # Mirror the failure semantics of the standard reek task
    unless status.success?
      abort("reek:update failed (reek reported smells). Output written to REEK")
    end
  end
  Kettle::Dev.register_default("reek:update") unless Kettle::Dev::IS_CI
rescue LoadError
  warn("[kettle-dev][reek.rake] failed to load reek/rake/task") if Kettle::Dev::DEBUGGING
  desc("(stub) reek is unavailable")
  task(:reek) do
    warn("NOTE: reek isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end
