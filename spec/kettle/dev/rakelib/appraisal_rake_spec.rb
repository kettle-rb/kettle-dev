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

  describe "rake appraisal:install" do
    let(:task_name) { "appraisal:install" }
    let(:appraisal_env) { {"BUNDLE_GEMFILE" => "Appraisal.root.gemfile"} }
    let(:appraisal_install_call) { [appraisal_env, "bundle", "exec", "appraisal", "generate-install"] }
    let(:failed_calls) { [] }
    let(:system_calls) { [] }

    before do
      allow(Bundler).to receive(:with_unbundled_env).and_yield
      allow_any_instance_of(Object).to receive(:warn) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Object).to receive(:system) do |_receiver, *args| # rubocop:disable RSpec/AnyInstance
        system_calls << args
        !failed_calls.include?(args)
      end
    end

    it "generates and installs appraisal gemfiles" do
      invoke

      expect(system_calls).to eq([
        [appraisal_env, "bundle", "install"],
        appraisal_install_call
      ])
    end

    context "when appraisal install fails" do
      let(:failed_calls) { [appraisal_install_call] }

      it "falls back to generating appraisal gemfiles" do
        invoke

        expect(system_calls).to eq([
          [appraisal_env, "bundle", "install"],
          appraisal_install_call,
          [appraisal_env, "bundle", "install"],
          [appraisal_env, "bundle", "exec", "appraisal", "generate"]
        ])
      end
    end
  end

  describe "rake appraisal:update" do
    let(:task_name) { "appraisal:update" }
    let(:appraisal_env) { {"BUNDLE_GEMFILE" => "Appraisal.root.gemfile"} }
    let(:appraisal_update_call) { [appraisal_env, "bundle", "exec", "appraisal", "generate-update"] }
    let(:failed_calls) { [] }
    let(:system_calls) { [] }

    before do
      allow(Bundler).to receive(:with_unbundled_env).and_yield
      allow_any_instance_of(Object).to receive(:warn) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Object).to receive(:system) do |_receiver, *args| # rubocop:disable RSpec/AnyInstance
        system_calls << args
        !failed_calls.include?(args)
      end
    end

    it "installs the Appraisal root bundle before updating Bundler" do
      invoke

      expect(system_calls).to eq([
        [appraisal_env, "bundle", "install"],
        [appraisal_env, "bundle", "update", "--bundler"],
        [appraisal_env, "bundle", "install"],
        appraisal_update_call
      ])
    end

    context "when appraisal update fails" do
      let(:failed_calls) { [appraisal_update_call] }

      it "falls back to generating appraisal gemfiles" do
        invoke

        expect(system_calls).to eq([
          [appraisal_env, "bundle", "install"],
          [appraisal_env, "bundle", "update", "--bundler"],
          [appraisal_env, "bundle", "install"],
          appraisal_update_call,
          [appraisal_env, "bundle", "install"],
          [appraisal_env, "bundle", "exec", "appraisal", "generate"]
        ])
      end
    end
  end
end
