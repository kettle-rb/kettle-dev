# frozen_string_literal: true

require "fileutils"

# rubocop:disable Rake/DuplicateTask
# Set up MiniTest
begin
  require "rake/testtask"

  Rake::TestTask.new(:test) do |t|
    t.libs << "test"
    t.test_files = FileList["test/**/*test*.rb"]
    t.verbose = true
  end
  Kettle::Dev.register_default("test")
rescue LoadError
  warn("[kettle-dev][spec_test.rake] failed to load rake/testtask") if Kettle::Dev::DEBUGGING
  desc("test task stub")
  task(:test) do
    warn("NOTE: minitest isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end

# Setup RSpec
begin
  require "rspec/core/rake_task"

  RSpec::Core::RakeTask.new(:spec)
  # This takes the place of `coverage` task it hasn't been registered yet.
  Kettle::Dev.register_default("spec") unless Kettle::Dev.default_registered?("coverage")
rescue LoadError
  warn("[kettle-dev][spec_test.rake] failed to load rspec/core/rake_task") if Kettle::Dev::DEBUGGING
  desc("spec task stub")
  task(:spec) do
    warn("NOTE: rspec isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end

spec_registered = Kettle::Dev.default_registered?("spec")
coverage_registered = Kettle::Dev.default_registered?("coverage")
test_registered = Kettle::Dev.default_registered?("test")
spec_or_coverage = spec_registered || coverage_registered

if spec_or_coverage && !test_registered
  task test: :spec
elsif test_registered && !spec_or_coverage
  task spec: :test
elsif test_registered && spec_or_coverage
  # When we have both tasks registered, make spec run as part of the test task
  task test: :spec
else
  puts "No test task is registered."
end
# rubocop:enable Rake/DuplicateTask
