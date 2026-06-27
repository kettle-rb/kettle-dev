# frozen_string_literal: true

require "spec_helper"

RSpec.describe "appraisal rake tasks" do # rubocop:disable RSpec/DescribeClass
  include_context "with rake", "appraisal"

  let(:quiet_env) do
    {
      "KETTLE_JEM_QUIET" => "true",
      "KETTLE_JEM_DEBUG" => "false",
      "KETTLE_DEV_DEBUG" => "false",
      "SMORG_RB_DEBUG" => "false",
      "DEBUG" => nil,
      "BUNDLE_QUIET" => "true",
      "BUNDLE_DEBUG" => "false",
      "BUNDLER_DEBUG" => "false",
      "BUNDLE_VERBOSE" => "false",
      "DEBUG_RESOLVER" => nil,
      "DEBUG_RESOLVER_TREE" => nil,
      "BUNDLER_DEBUG_RESOLVER" => nil,
      "BUNDLER_DEBUG_RESOLVER_TREE" => nil,
      "DEBUG_COMPACT_INDEX" => nil,
      "MOLINILLO_DEBUG" => nil,
      "BUNDLE_SILENCE_DEPRECATIONS" => "true",
      "BUNDLE_SILENCE_ROOT_WARNING" => "true",
      "BUNDLE_SUPPRESS_INSTALL_USING_MESSAGES" => "true"
    }
  end
  let(:appraisal_env) { quiet_env.merge("BUNDLE_GEMFILE" => "Appraisal.root.gemfile") }
  let(:bundle_install_call) { [appraisal_env, "bundle", "install", "--quiet"] }

  describe "rake appraisal:generate" do
    let(:task_name) { "appraisal:generate" }
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
        bundle_install_call,
        [appraisal_env, "bundle", "exec", "appraisal", "generate"]
      ])
    end
  end

  describe "rake appraisal:install" do
    let(:task_name) { "appraisal:install" }
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
        bundle_install_call,
        appraisal_install_call
      ])
    end

    context "when appraisal install fails" do
      let(:failed_calls) { [appraisal_install_call] }

      it "falls back to generating appraisal gemfiles" do
        invoke

        expect(system_calls).to eq([
          bundle_install_call,
          appraisal_install_call,
          bundle_install_call,
          [appraisal_env, "bundle", "exec", "appraisal", "generate"]
        ])
      end
    end
  end

  describe "rake appraisal:update" do
    let(:task_name) { "appraisal:update" }
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
        bundle_install_call,
        [appraisal_env, "bundle", "update", "--bundler"],
        bundle_install_call,
        appraisal_update_call
      ])
    end

    context "when appraisal update fails" do
      let(:failed_calls) { [appraisal_update_call] }

      it "falls back to generating appraisal gemfiles" do
        invoke

        expect(system_calls).to eq([
          bundle_install_call,
          [appraisal_env, "bundle", "update", "--bundler"],
          bundle_install_call,
          appraisal_update_call,
          bundle_install_call,
          [appraisal_env, "bundle", "exec", "appraisal", "generate"]
        ])
      end
    end
  end
end
