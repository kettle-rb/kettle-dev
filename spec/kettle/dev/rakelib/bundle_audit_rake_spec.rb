# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "bundle audit rake tasks" do # rubocop:disable RSpec/DescribeClass
  let(:fake_load_path) { File.expand_path("../../../../tmp/fake_bundle_audit_load_path", __dir__) }
  let(:fake_task_file) { File.join(fake_load_path, "bundler/audit/task.rb") }

  around do |example|
    previous_application = Rake.application
    previous_defaults = Kettle::Dev.defaults
    begin
      Rake.application = Rake::Application.new
      Kettle::Dev.instance_variable_set(:@defaults, [].freeze)
      example.run
    ensure
      Rake.application = previous_application
      Kettle::Dev.instance_variable_set(:@defaults, previous_defaults)
      $LOAD_PATH.delete(fake_load_path)
      $LOADED_FEATURES.reject! { |feature| feature.end_with?("bundler/audit/task.rb") }
    end
  end

  def load_bundle_audit_tasks
    load File.expand_path("../../../../lib/kettle/dev/rakelib/bundle_audit.rake", __dir__)
  end

  it "registers bundler-audit tasks and defaults when bundler-audit is available" do
    FileUtils.mkdir_p(File.dirname(fake_task_file))
    File.write(fake_task_file, <<~RUBY)
      # frozen_string_literal: true

      module Bundler
        module Audit
          class Task
            def initialize
              ::Rake::Task.define_task("bundle:audit")
              ::Rake::Task.define_task("bundle:audit:update")
            end
          end
        end
      end
    RUBY
    $LOAD_PATH.unshift(fake_load_path)

    load_bundle_audit_tasks

    expect(Rake::Task.task_defined?("bundle:audit")).to be true
    expect(Rake::Task.task_defined?("bundle:audit:update")).to be true
    expect(Kettle::Dev.defaults).to include("bundle:audit", "bundle:audit:update")
  end

  it "defines stub tasks when bundler-audit is unavailable" do
    FileUtils.mkdir_p(File.dirname(fake_task_file))
    File.write(fake_task_file, <<~RUBY)
      # frozen_string_literal: true

      raise LoadError, "bundler-audit unavailable"
    RUBY
    $LOAD_PATH.unshift(fake_load_path)
    stub_const("Kettle::Dev::DEBUGGING", true)

    expect { load_bundle_audit_tasks }.to output(/failed to load bundle\/audit\/task/).to_stderr
    expect { Rake::Task["bundle:audit"].invoke }.to output(/bundler-audit isn't installed/).to_stderr
    expect { Rake::Task["bundle:audit:update"].invoke }.to output(/bundler-audit isn't installed/).to_stderr
  end
end
