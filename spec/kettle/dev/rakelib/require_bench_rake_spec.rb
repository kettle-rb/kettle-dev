# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "require bench rake tasks" do # rubocop:disable RSpec/DescribeClass
  let(:fake_load_path) { File.expand_path("../../../../tmp/fake_require_bench_load_path", __dir__) }
  let(:fake_task_file) { File.join(fake_load_path, "require_bench/tasks.rb") }

  around do |example|
    previous_application = Rake.application
    begin
      Rake.application = Rake::Application.new
      example.run
    ensure
      Rake.application = previous_application
      $LOAD_PATH.delete(fake_load_path)
      $LOADED_FEATURES.reject! { |feature| feature.end_with?("require_bench/tasks.rb") }
    end
  end

  def load_require_bench_tasks
    load File.expand_path("../../../../lib/kettle/dev/rakelib/require_bench.rake", __dir__)
  end

  it "loads require_bench tasks when enabled" do
    FileUtils.mkdir_p(File.dirname(fake_task_file))
    File.write(fake_task_file, <<~RUBY)
      # frozen_string_literal: true

      Rake::Task.define_task("require_bench:run")
    RUBY
    $LOAD_PATH.unshift(fake_load_path)
    stub_const("Kettle::Dev::REQUIRE_BENCH", true)

    load_require_bench_tasks

    expect(Rake::Task.task_defined?("require_bench:run")).to be true
  end

  it "warns when require_bench is enabled but unavailable" do
    FileUtils.mkdir_p(File.dirname(fake_task_file))
    File.write(fake_task_file, <<~RUBY)
      # frozen_string_literal: true

      raise LoadError, "require_bench unavailable"
    RUBY
    $LOAD_PATH.unshift(fake_load_path)
    stub_const("Kettle::Dev::DEBUGGING", true)
    stub_const("Kettle::Dev::REQUIRE_BENCH", true)

    expect { load_require_bench_tasks }.to output(/failed to load require_bench\/tasks/).to_stderr
  end

  it "does nothing when require_bench is disabled" do
    stub_const("Kettle::Dev::REQUIRE_BENCH", false)

    expect { load_require_bench_tasks }.not_to raise_error
  end
end
