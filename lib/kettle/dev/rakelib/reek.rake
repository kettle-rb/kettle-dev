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
  require "rbconfig"
  desc("Run reek and store the output into the REEK file")
  task("reek:update") do
    # Resolve the gem executable directly. `bundle exec reek` may prefer a
    # project-local bin/reek binstub, and stale binstubs are a common failure
    # mode during template/bootstrap work.
    cmd = [RbConfig.ruby, Gem.bin_path("reek", "reek")]

    output, status = Open3.capture2e(*cmd)

    normalized_output = output.to_s.strip.empty? ? "" : output
    File.write("REEK", normalized_output)

    unless status.success? || status.exitstatus == 1
      raise("reek:update failed (reek executable failed with exit #{status.exitstatus}). Output written to REEK")
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
