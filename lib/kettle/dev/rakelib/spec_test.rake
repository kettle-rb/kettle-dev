# frozen_string_literal: true

require "fileutils"

# Setup RSpec
begin
  require "rspec/core/rake_task"

  RSpec::Core::RakeTask.new(:spec)
  # This takes the place of `coverage` task when running as CI=true
  Kettle::Dev.register_default("spec") if Kettle::Dev::IS_CI
rescue LoadError
  warn("[kettle-dev][spec_test.rake] failed to load rspec/core/rake_task") if Kettle::Dev::DEBUGGING
  desc("spec task stub")
  task(:spec) do
    warn("NOTE: rspec isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end

# Setup MiniTest
begin
  require "rake/testtask"

  Rake::TestTask.new(:test) do |t|
    t.libs << "test"
    t.test_files = FileList["test/**/*test*.rb"]
    t.verbose = true
  end
rescue LoadError
  warn("[kettle-dev][spec_test.rake] failed to load rake/testtask") if Kettle::Dev::DEBUGGING
  desc("test task stub")
  task(:test) do
    warn("NOTE: minitest isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end
