# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "rake yard" do # rubocop:disable RSpec/DescribeClass
  def bundled_gem?(name)
    # Appraisal slices intentionally omit unrelated modular dependencies. In
    # those bundles Bundler is the source of truth for whether yard.rake should
    # exercise the real YARD task wiring or the missing-YARD stub path.
    Bundler.locked_gems.specs.any? { |spec| spec.name == name }
  rescue
    false
  end

  around do |example|
    previous = Rake.application
    defaults = Kettle::Dev.defaults
    begin
      Rake.application = Rake::Application.new
      Kettle::Dev.instance_variable_set(:@defaults, [].freeze)
      Rake::Task.define_task(:default)
      example.run
    ensure
      Rake.application = previous
      Kettle::Dev.instance_variable_set(:@defaults, defaults)
    end
  end

  before do
    rakelib = File.expand_path("../../../../lib/kettle/dev/rakelib", __dir__)
    load File.join(rakelib, "yard.rake")
  end

  it "registers yard as a default task" do
    expect(Kettle::Dev.defaults).to include("yard")
    expect(Rake::Task[:default].prerequisites).to include("yard")
  end

  it "runs YARD lint before the default yard task" do
    default_prerequisites = Rake::Task[:default].prerequisites

    if bundled_gem?("yard")
      expect(Kettle::Dev.defaults).to include("yard:lint", "yard")
      expect(default_prerequisites).to include("yard:lint", "yard")
      expect(default_prerequisites.index("yard:lint")).to be < default_prerequisites.index("yard")
      expect(Rake::Task[:yard].prerequisites).to include("yard:lint")
    else
      expect(Kettle::Dev.defaults).to contain_exactly("yard")
      expect(default_prerequisites).to contain_exactly("yard")
      expect(Rake::Task.task_defined?("yard")).to be(true)
      expect(Rake::Task.task_defined?("yard:lint")).to be(false)
    end
  end

  it "skips YARD lint when the project has no lint policy" do
    Dir.mktmpdir("kettle-dev-yard-lint") do |root|
      Dir.chdir(root) do # rubocop:disable ThreadSafety/DirChdir
        expect { Rake::Task["yard:lint"].invoke }.not_to raise_error
      end
    end
  end
end
