# frozen_string_literal: true

require "fileutils"
require "spec_helper"
require "rake"

RSpec.describe "rake yard:lint" do # rubocop:disable RSpec/DescribeClass
  let(:fake_load_path) { File.expand_path("../../../../tmp/fake_yard_load_path", __dir__) }

  around do |example|
    previous_application = Rake.application
    previous_defaults = Kettle::Dev.defaults
    begin
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:default)
      Kettle::Dev.instance_variable_set(:@defaults, [].freeze)
      FileUtils.mkdir_p(File.join(fake_load_path, "yard"))
      File.write(File.join(fake_load_path, "yard.rb"), <<~RUBY)
        # frozen_string_literal: true

        module YARD
          module Rake
            class YardocTask
              attr_accessor :files

              def initialize(name)
                ::Rake::Task.define_task(name)
                yield(self) if block_given?
              end
            end
          end
        end
      RUBY
      File.write(File.join(fake_load_path, "yard", "fence.rb"), "raise LoadError, \"optional\"\n")
      File.write(File.join(fake_load_path, "yard", "timekeeper.rb"), "raise LoadError, \"optional\"\n")
      $LOAD_PATH.unshift(fake_load_path)
      example.run
    ensure
      $LOAD_PATH.delete(fake_load_path)
      $LOADED_FEATURES.reject! { |feature| feature.end_with?("yard.rb", "yard/fence.rb", "yard/timekeeper.rb") }
      Rake.application = previous_application
      Kettle::Dev.instance_variable_set(:@defaults, previous_defaults)
      Object.send(:remove_const, :YARD) if Object.const_defined?(:YARD, false) # rubocop:disable RSpec/RemoveConst
    end
  end

  before do
    rakelib = File.expand_path("../../../../lib/kettle/dev/rakelib", __dir__)
    load File.join(rakelib, "yard.rake")
  end

  it "registers the lint prerequisite and skips when no policy exists" do
    expect(Rake::Task[:yard].prerequisites).to include("yard:lint")

    Dir.mktmpdir do |root|
      Dir.chdir(root) do # rubocop:disable ThreadSafety/DirChdir
        expect { Rake::Task["yard:lint"].invoke }.not_to raise_error
      end
    end
  end

  it "runs quiet lint successfully when a policy exists" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".yard-lint.yml"), "---\n")
      Dir.chdir(root) do # rubocop:disable ThreadSafety/DirChdir
        top_level = TOPLEVEL_BINDING.eval("self")
        allow(top_level).to receive(:system).with("bundle", "exec", "yard-lint", "--quiet", "lib").and_return(true)

        Rake::Task["yard:lint"].invoke

        expect(top_level).to have_received(:system).with("bundle", "exec", "yard-lint", "--quiet", "lib")
      end
    end
  end
end
