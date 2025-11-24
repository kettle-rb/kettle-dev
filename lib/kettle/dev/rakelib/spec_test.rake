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
  # The test task is invoked by the coverage task, so of the two, (i.e., when outside CI),
  #   only coverage should be registered as default.
  Kettle::Dev.register_default("test") unless Kettle::Dev.default_registered?("coverage")
rescue LoadError
  warn("[kettle-dev][spec_test.rake] failed to load rake/testtask") if Kettle::Dev::DEBUGGING
  desc("test task stub")
  task(:test) do
    warn("NOTE: minitest isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
  end
end

setup_spec_task = ->(default:) {
  begin
    require "rspec/core/rake_task"

    RSpec::Core::RakeTask.new(:spec)
    if default
      # This takes the place of the `coverage` task if/when it isn't already registered.
      # This is because spec and coverage run the same tests
      # (via the coverage task invoking the test task which invokes the spec task),
      # so we can't have both in the default task.
      Kettle::Dev.register_default("spec") unless Kettle::Dev.default_registered?("coverage")
    end
  rescue LoadError
    warn("[kettle-dev][spec_test.rake] failed to load rspec/core/rake_task") if Kettle::Dev::DEBUGGING
    desc("spec task stub")
    task(:spec) do
      warn("NOTE: rspec isn't installed, or is disabled for #{RUBY_VERSION} in the current environment")
    end
  end
}

# Setup RSpec
if defined?(Kettle::Dev::IS_CI)
  if Kettle::Dev::IS_CI
    # then we should not have a coverage task, but do want a spec test.
    setup_spec_task.call(default: true)
  else
    # then we should have a coverage task.
    # The coverage task will invoke the "test" task, which will invoke the spec task.
    setup_spec_task.call(default: false)
  end
else
  # then we do not have a coverage task setup by this gem, and are not in a coverage context.
  # So setup a spec test.
  setup_spec_task.call(default: true)
end

spec_registered = Kettle::Dev.default_registered?("spec")
coverage_registered = Kettle::Dev.default_registered?("coverage")
test_registered = Kettle::Dev.default_registered?("test")
spec_and_coverage = spec_registered && coverage_registered
spec_or_coverage = spec_registered || coverage_registered

if test_registered && !spec_or_coverage
  task spec: :test
# elsif test_registered && spec_registered
#   # When we have both tasks registered as default, making spec run as part of test would be redundant.
#   # task test: :spec
# elsif test_registered && coverage_registered
#   # When we have both tasks registered as default, making coverage run as part of test would be circular.
#   # task test: :coverage
elsif !test_registered
  if spec_registered && !coverage_registered
    puts "Spec task is registered as default task. Creating test task with spec as pre-requisite" if Kettle::Dev::DEBUGGING
    # If spec is registered as default, it should be invoked by the test task when test is not default,
    #   because some CI workflows will be configured to run bin/rake test.
    desc "A test task with spec as prerequisite"
    task test: :spec
  elsif coverage_registered && !spec_registered
    puts "Coverage task is registered as default task, and will call test task, with spec as pre-requisite." if Kettle::Dev::DEBUGGING
    # If coverage is registered as default, it will invoke test.
    # We need to make spec a prerequisite of test so that it runs as part of the test task,
    # which will be invoked by the coverage task.
    desc "A test task with spec as prerequisite"
    task test: :spec
  end
end
# rubocop:enable Rake/DuplicateTask

if spec_and_coverage
  # They should not both be registered as default tasks, as they run the same tests.
  warn("[kettle-dev][spec_test.rake] both spec and coverage are registered as default tasks!") if Kettle::Dev::DEBUGGING
elsif test_registered && spec_registered
  # They should not both be registered as default tasks, as they will be setup to run the same tests.
  warn("[kettle-dev][spec_test.rake] both test and spec are registered as default tasks!") if Kettle::Dev::DEBUGGING
elsif test_registered && coverage_registered
  # They should not both be registered as default tasks, coverage invokes the test task.
  warn("[kettle-dev][spec_test.rake] both test and coverage are registered as default tasks!") if Kettle::Dev::DEBUGGING
end
