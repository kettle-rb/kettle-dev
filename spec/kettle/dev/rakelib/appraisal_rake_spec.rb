# frozen_string_literal: true

require "spec_helper"

RSpec.describe "appraisal rake tasks" do # rubocop:disable RSpec/DescribeClass
  include_context "with rake", "appraisal"

  describe "rake appraisal:generate" do
    let(:task_name) { "appraisal:generate" }
    let(:appraisal_env) { {"BUNDLE_GEMFILE" => "Appraisal.root.gemfile"} }
    let(:system_calls) { [] }

    before do
      allow(Bundler).to receive(:with_unbundled_env).and_yield
      allow(Gem::Platform).to receive(:local).and_return(Gem::Platform.new("x86_64-linux"))
      allow(Dir).to receive(:glob).with(File.join("gemfiles", "*.gemfile")).and_return([
        "gemfiles/unlocked_deps.gemfile",
        "gemfiles/current.gemfile"
      ])
      allow(File).to receive(:file?).and_call_original
      allow(File).to receive(:file?).with("gemfiles/unlocked_deps.gemfile.lock").and_return(true)
      allow(File).to receive(:file?).with("gemfiles/current.gemfile.lock").and_return(false)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("gemfiles/unlocked_deps.gemfile").and_return("eval_gemfile \"modular/documentation.gemfile\"")
      allow(File).to receive(:read).with("gemfiles/unlocked_deps.gemfile.lock").and_return("yaml-converter (0.2.0)")
      allow_any_instance_of(Object).to receive(:system) do |_receiver, *args| # rubocop:disable RSpec/AnyInstance
        system_calls << args
        true
      end
    end

    it "generates appraisal gemfiles in the Appraisal root bundle context" do
      invoke

      expect(system_calls).to eq([
        [appraisal_env, "bundle", "install"],
        [appraisal_env, "bundle", "exec", "appraisal", "generate"]
      ])
    end
  end

  describe "rake appraisal:update" do
    let(:task_name) { "appraisal:update" }
    let(:appraisal_env) { {"BUNDLE_GEMFILE" => "Appraisal.root.gemfile"} }
    let(:system_calls) { [] }

    before do
      allow(Bundler).to receive(:with_unbundled_env).and_yield
      allow_any_instance_of(Object).to receive(:system) do |_receiver, *args| # rubocop:disable RSpec/AnyInstance
        system_calls << args
        true
      end
    end

    it "installs the Appraisal root bundle before updating Bundler" do
      invoke

      expect(system_calls.first(3)).to eq([
        [appraisal_env, "bundle", "install"],
        [appraisal_env, "bundle", "update", "--bundler"],
        [appraisal_env, "bundle", "install"]
      ])
      expect(system_calls).to include(
        [{"BUNDLE_GEMFILE" => "gemfiles/unlocked_deps.gemfile"}, "bundle", "lock", "--add-platform", "x86_64-linux"],
        [{"BUNDLE_GEMFILE" => "gemfiles/unlocked_deps.gemfile"}, "bundle", "update", "yaml-converter"]
      )
      expect(system_calls.last(2)).to eq([
        [appraisal_env, "bundle", "exec", "appraisal", "update"],
        ["bundle", "exec", "rake", "rubocop_gradual:autocorrect"]
      ])
    end
  end
end
