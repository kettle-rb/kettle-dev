# frozen_string_literal: true

RSpec.describe Kettle::Dev do
  describe "::register_default" do
    it "adds task and enhances :default when defined" do
      stub_const("Rake::Task", Class.new)
      allow(Rake::Task).to receive(:task_defined?).with(:default).and_return(true)
      default_task = instance_double(Rake::Task)
      allow(Rake::Task).to receive(:[]).with(:default).and_return(default_task)
      expect(default_task).to receive(:enhance).with(["foo"]).and_return(nil)
      expect(described_class.register_default(:foo)).to include("foo")
    end

    # Helper to stub a :default task that raises on enhance
    def stub_default_task_raising
      stub_const("Rake::Task", Class.new)
      allow(Rake::Task).to receive(:task_defined?).with(:default).and_return(true)
      default_task = instance_double(Rake::Task)
      allow(Rake::Task).to receive(:[]).with(:default).and_return(default_task)
      allow(default_task).to receive(:enhance).and_raise(StandardError, "boom")
    end

    it "rescues and does not warn when DEBUGGING is false" do
      stub_const("Kettle::Dev::DEBUGGING", false)
      stub_default_task_raising
      allow(Kernel).to receive(:warn)
      described_class.register_default(:bar)
      expect(Kernel).not_to have_received(:warn)
    end

    it "rescues and warns when DEBUGGING is true" do
      stub_const("Kettle::Dev::DEBUGGING", true)
      stub_default_task_raising
      allow(Kernel).to receive(:warn)
      described_class.register_default(:qux)
      expect(Kernel).to have_received(:warn).with(match(/kettle-dev: failed to enhance :default with qux: boom/))
    end

    it "does not enhance when :default is not defined" do
      stub_const("Rake::Task", Class.new)
      allow(Rake::Task).to receive(:task_defined?).with(:default).and_return(false)
      expect(described_class.register_default(:baz)).to include("baz")
    end
  end

  describe "linting and coverage tasks" do
    before do
      pending("RuboCop::Lts is only a dependency for Ruby >= 2.7") if RUBY_VERSION < "2.7"
      require "rubocop/lts" # have to require here so we can spy on it
      # stub register_default to observe calls without mutating global Rake
      allow(described_class).to receive(:register_default).and_call_original
      allow(Rubocop::Lts).to receive(:install_tasks)
    end

    it "registers autocorrect when not on CI" do
      stub_const("Kettle::Dev::IS_CI", false)
      described_class.send(:linting_tasks)
      expect(described_class.defaults).to include("rubocop_gradual:autocorrect")
    end

    it "registers check when on CI" do
      stub_const("Kettle::Dev::IS_CI", true)
      described_class.send(:linting_tasks)
      expect(described_class.defaults).to include("rubocop_gradual:check")
    end

    it "handles missing kettle-soup-cover (LoadError)" do
      # Force require to raise when asking for kettle-soup-cover
      allow(described_class).to receive(:require).with("kettle-soup-cover").and_raise(LoadError)
      expect { described_class.send(:coverage_tasks) }.not_to raise_error
    end

    it "registers coverage when kettle-soup-cover present and not CI" do
      stub_const("Kettle::Dev::IS_CI", false)
      Module.new do
        module Kettle; end
      end
      allow(described_class).to receive(:require).with("kettle-soup-cover").and_return(true)
      stub_const("Kettle::Soup::Cover", double("Cover", install_tasks: true))
      described_class.send(:coverage_tasks)
      expect(described_class.defaults).to include("coverage")
    end
  end
end
