# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "reek rake tasks" do # rubocop:disable RSpec/DescribeClass
  describe "rake reek:update" do
    include_context "with rake", "reek"

    def status(success, exitstatus)
      instance_double(Process::Status, success?: success, exitstatus: exitstatus)
    end

    let(:task_name) { "reek:update" }
    let(:fake_reek_load_path) { File.expand_path("../../../../tmp/fake_reek_load_path", __dir__) }
    let(:fake_reek_task_file) { File.join(fake_reek_load_path, "reek/rake/task.rb") }

    prepend_before do
      stub_const("Reek", Module.new)
      FileUtils.mkdir_p(File.dirname(fake_reek_task_file))
      File.write(fake_reek_task_file, <<~RUBY)
        # frozen_string_literal: true

        module Reek
          module Rake
            class Task
              attr_accessor :fail_on_error, :verbose, :source_files

              def initialize
                yield(self) if block_given?
                ::Rake::Task.define_task(:reek)
              end
            end
          end
        end
      RUBY
      $LOAD_PATH.unshift(fake_reek_load_path)
    end

    after do
      $LOAD_PATH.delete(fake_reek_load_path)
      $LOADED_FEATURES.reject! { |feature| feature.end_with?("reek/rake/task.rb") }
    end

    it "writes the REEK file by resolving the gem executable directly" do
      reek_executable = "/gems/reek/exe/reek"
      allow(Gem).to receive(:bin_path).with("reek", "reek").and_return(reek_executable)
      allow(Open3).to receive(:capture2e)
        .with(RbConfig.ruby, reek_executable)
        .and_return(["smells\n", status(false, 1)])
      expect(File).to receive(:write).with("REEK", "smells\n")

      invoke
    end

    it "keeps the REEK file empty when reek reports no smells" do
      allow(Gem).to receive(:bin_path).with("reek", "reek").and_return("/gems/reek/exe/reek")
      allow(Open3).to receive(:capture2e).and_return(["\n", status(true, 0)])
      expect(File).to receive(:write).with("REEK", "")

      invoke
    end

    it "fails when the reek executable exits for a reason other than smells" do
      allow(Gem).to receive(:bin_path).with("reek", "reek").and_return("/gems/reek/exe/reek")
      allow(Open3).to receive(:capture2e).and_return(["usage error\n", status(false, 2)])
      expect(File).to receive(:write).with("REEK", "usage error\n")

      expect { invoke }.to raise_error(RuntimeError, /reek:update failed/)
    end
  end

  describe "rake reek when reek is unavailable" do
    include_context "with rake", "reek"

    let(:task_name) { "reek" }
    let(:fake_reek_load_path) { File.expand_path("../../../../tmp/fake_reek_unavailable_load_path", __dir__) }
    let(:fake_reek_task_file) { File.join(fake_reek_load_path, "reek/rake/task.rb") }

    prepend_before do
      FileUtils.mkdir_p(File.dirname(fake_reek_task_file))
      File.write(fake_reek_task_file, <<~RUBY)
        # frozen_string_literal: true

        raise LoadError, "reek unavailable"
      RUBY
      $LOADED_FEATURES.reject! { |feature| feature.end_with?("reek/rake/task.rb") }
      $LOAD_PATH.unshift(fake_reek_load_path)
    end

    after do
      $LOAD_PATH.delete(fake_reek_load_path)
      $LOADED_FEATURES.reject! { |feature| feature.end_with?("reek/rake/task.rb") }
    end

    it "defines a stub task that warns instead of failing" do
      expect { invoke }.to output(/NOTE: reek isn't installed/).to_stderr
    end
  end
end
