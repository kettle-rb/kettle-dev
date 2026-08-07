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

  begin
    require "yard/fence"
    Yard::Fence.install_rake_tasks!(:yard)
    # simplecov:disable -- optional plugin availability is environment-specific.
  rescue LoadError
    # yard-fence not available - that's fine
    # simplecov:enable
  end

  begin
    require "yard/timekeeper"
    Yard::Timekeeper.install_rake_tasks!(:yard)
    # simplecov:disable -- optional plugin availability is environment-specific.
  rescue LoadError
    # yard-timekeeper not available - that's fine
    # simplecov:enable
  end

  namespace :yard do
    desc "Lint YARD Documentation"
    task :lint do
      next unless File.file?(".yard-lint.yml")

      # Keep warning-only lint runs compact in default/release flows, but rerun
      # with full output when lint fails so the blocking diagnostics are visible.
      sh("bundle", "exec", "yard-lint", "lib") unless system("bundle", "exec", "yard-lint", "--quiet", "lib")
    end
  end

  desc "Generate YARD documentation and run YARD lint"
  task yard: "yard:lint"
  Kettle::Dev.register_default("yard:lint")
  Kettle::Dev.register_default("yard")
rescue LoadError
  # simplecov:disable -- YARD is an optional development dependency.
  warn("[kettle-dev][yard.rake] failed to load yard") if Kettle::Dev::DEBUGGING
  desc("(stub) yard is unavailable")
  task(:yard) do # rubocop:disable Rake/DuplicateTask -- fallback when the real YARD task cannot load
    warn("NOTE: yard isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
  Kettle::Dev.register_default("yard")
  # simplecov:enable
end
