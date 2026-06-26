# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "spec and test rake tasks" do # rubocop:disable RSpec/DescribeClass
  let(:rakelib) { File.expand_path("../../../../lib/kettle/dev/rakelib", __dir__) }

  around do |example|
    previous_application = Rake.application
    previous_defaults = Kettle::Dev.defaults
    tmp_root = File.expand_path("../../../../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-dev-spec-test-rake", tmp_root) do |dir|
      @project_dir = dir
      Dir.chdir(dir) do # rubocop:disable ThreadSafety/DirChdir
        Rake.application = Rake::Application.new
        Rake::Task.define_task(:default)
        Kettle::Dev.instance_variable_set(:@defaults, [].freeze)
        example.run
      end
    ensure
      Rake.application = previous_application
      Kettle::Dev.instance_variable_set(:@defaults, previous_defaults)
    end
  end

  def load_spec_test_tasks
    load File.join(rakelib, "spec_test.rake")
  end

  it "defines a MiniTest test task without synthesizing a kettle-test RSpec task for MiniTest-only projects" do
    FileUtils.mkdir_p("test")
    File.write("test/test_example.rb", "# frozen_string_literal: true\n")

    load_spec_test_tasks

    expect(Rake::Task.task_defined?(:test)).to be true
    expect(Rake::Task.task_defined?(:spec)).to be true
    expect(Rake::Task[:spec].prerequisites).to eq(["test"])
    expect(Kettle::Dev.defaults).to include("test")
    expect(Kettle::Dev.defaults).not_to include("spec")
  end

  it "keeps the historical kettle-test spec task for RSpec projects" do
    FileUtils.mkdir_p("spec")
    File.write("spec/example_spec.rb", "# frozen_string_literal: true\n")

    load_spec_test_tasks

    expect(Rake::Task.task_defined?(:spec)).to be true
    expect(Rake::Task[:spec].prerequisites).to be_empty
  end

  it "registers spec as the default RSpec task on CI" do
    stub_const("Kettle::Dev::IS_CI", true)
    FileUtils.mkdir_p("spec")
    File.write("spec/example_spec.rb", "# frozen_string_literal: true\n")

    load_spec_test_tasks

    expect(Rake::Task.task_defined?(:spec)).to be true
    expect(Kettle::Dev.defaults).to include("spec")
  end

  it "wires test to spec when coverage is already registered as the default" do
    FileUtils.mkdir_p("spec")
    File.write("spec/example_spec.rb", "# frozen_string_literal: true\n")
    Kettle::Dev.register_default("coverage")

    load_spec_test_tasks

    expect(Rake::Task.task_defined?(:test)).to be true
    expect(Rake::Task[:test].prerequisites).to include("spec")
    expect(Kettle::Dev.defaults).to include("coverage")
    expect(Kettle::Dev.defaults).not_to include("spec")
  end
end
