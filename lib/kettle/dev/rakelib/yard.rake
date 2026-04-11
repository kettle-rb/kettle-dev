# frozen_string_literal: true

# Setup Yard
begin
  require "yard"

  YARD::Rake::YardocTask.new(:yard) do |t|
    # Keep .yardopts as the canonical source for included files, plugins,
    # readme selection, and output directory. Diverging task-local file lists
    # caused `rake yard` and `yard` to generate different docs sites.
    t.files = []
  end

  # Load yard-fence rake task if available (provides yard:fence:prepare).
  # The explicit enhance below is needed because yard-fence only auto-enhances
  # :yard when the task already exists at the time its rake task is loaded.
  begin
    require "yard/fence/rake_task"
    Yard::Fence::RakeTask.new unless Rake::Task.task_defined?("yard:fence:prepare")

    if Rake::Task.task_defined?(:yard) && Rake::Task.task_defined?("yard:fence:prepare")
      prereqs = Rake::Task[:yard].prerequisites
      Rake::Task[:yard].enhance(["yard:fence:prepare"]) unless prereqs.include?("yard:fence:prepare")
    end
  rescue LoadError
    # yard-fence not available or doesn't have rake_task - that's fine
  end
rescue LoadError
  warn("[kettle-dev][yard.rake] failed to load yard") if Kettle::Dev::DEBUGGING
  desc("(stub) yard is unavailable")
  task(:yard) do
    warn("NOTE: yard isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end
