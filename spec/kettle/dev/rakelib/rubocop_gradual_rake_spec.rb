# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "rubocop gradual rake tasks" do # rubocop:disable RSpec/DescribeClass
  let(:fake_load_path) { File.expand_path("../../../../tmp/fake_rubocop_gradual_load_path", __dir__) }
  let(:fake_task_file) { File.join(fake_load_path, "rubocop/gradual/rake_task.rb") }

  around do |example|
    previous_application = Rake.application
    begin
      Rake.application = Rake::Application.new
      example.run
    ensure
      Rake.application = previous_application
      $LOAD_PATH.delete(fake_load_path)
      $LOADED_FEATURES.reject! { |feature| feature.end_with?("rubocop/gradual/rake_task.rb") }
    end
  end

  def load_rubocop_gradual_tasks
    load File.expand_path("../../../../lib/kettle/dev/rakelib/rubocop_gradual.rake", __dir__)
  end

  it "defines a debug RuboCop Gradual task with debug options" do
    debug_options = []
    stub_const("RUBOCOP_GRADUAL_RAKE_SPEC_DEBUG_OPTIONS", debug_options)
    FileUtils.mkdir_p(File.dirname(fake_task_file))
    File.write(fake_task_file, <<~RUBY)
      # frozen_string_literal: true

      module RuboCop
        module Gradual
          class RakeTask
            attr_accessor :options

            def initialize(name)
              ::Rake::Task.define_task(name)
              yield(self) if block_given?
              RUBOCOP_GRADUAL_RAKE_SPEC_DEBUG_OPTIONS.replace(options)
            end
          end
        end
      end
    RUBY
    $LOAD_PATH.unshift(fake_load_path)

    load_rubocop_gradual_tasks

    expect(Rake::Task.task_defined?(:rubocop_gradual_debug)).to be true
    expect(debug_options).to eq(["--debug"])
  end

  it "warns when RuboCop Gradual is unavailable" do
    FileUtils.mkdir_p(File.dirname(fake_task_file))
    File.write(fake_task_file, <<~RUBY)
      # frozen_string_literal: true

      raise LoadError, "rubocop-gradual unavailable"
    RUBY
    $LOAD_PATH.unshift(fake_load_path)
    stub_const("Kettle::Dev::DEBUGGING", true)

    expect { load_rubocop_gradual_tasks }.to output(/failed to load rubocop\/gradual\/rake_task/).to_stderr
  end
end
