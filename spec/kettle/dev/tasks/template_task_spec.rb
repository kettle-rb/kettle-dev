# frozen_string_literal: true

# Unit specs for Kettle::Dev::Tasks::TemplateTask
# Mirrors a subset of behavior covered by the rake integration spec, but
# calls the class API directly for focused unit testing.

require "rake"

RSpec.describe Kettle::Dev::Tasks::TemplateTask do
  include_context "with stubbed env"

  let(:helpers) { Kettle::Dev::TemplateHelpers }

  before do
    stub_env("allowed" => "true") # allow env file changes without abort
  end

  describe "::run" do
    it "prefers .example files under .github/workflows and writes without .example and customizes FUNDING.yml" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Arrange template source
          gh_src = File.join(gem_root, ".github", "workflows")
          FileUtils.mkdir_p(gh_src)
          File.write(File.join(gh_src, "ci.yml"), "name: REAL\n")
          File.write(File.join(gh_src, "ci.yml.example"), "name: EXAMPLE\n")
          # FUNDING.yml example with placeholders
          File.write(File.join(gem_root, ".github", "FUNDING.yml.example"), <<~Y)
            open_collective: placeholder
            tidelift: rubygems/placeholder
          Y

          # Provide gemspec in project to satisfy metadata scanner
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/demo"
            end
          G

          # Stub helpers used by the task
          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          # Exercise
          expect { described_class.run }.not_to raise_error

          # Assert
          dest_ci = File.join(project_root, ".github", "workflows", "ci.yml")
          expect(File).to exist(dest_ci)
          expect(File.read(dest_ci)).to include("EXAMPLE")

          # FUNDING content customized
          funding_dest = File.join(project_root, ".github", "FUNDING.yml")
          expect(File).to exist(funding_dest)
          funding = File.read(funding_dest)
          expect(funding).to include("open_collective: acme")
          expect(funding).to include("tidelift: rubygems/demo")
        end
      end
    end

    it "copies .env.local.example but does not create .env.local" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          File.write(File.join(gem_root, ".env.local.example"), "SECRET=1\n")
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
            end
          G

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          expect { described_class.run }.not_to raise_error

          expect(File).to exist(File.join(project_root, ".env.local.example"))
          expect(File).not_to exist(File.join(project_root, ".env.local"))
        end
      end
    end

    it "updates style.gemfile rubocop-lts constraint based on min_ruby" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # style.gemfile template with placeholder constraint
          style_dir = File.join(gem_root, "gemfiles", "modular")
          FileUtils.mkdir_p(style_dir)
          File.write(File.join(style_dir, "style.gemfile.example"), <<~G)
            source "https://rubygems.org"
            gem "rubocop-lts", "~> 10.0"
          G
          # gemspec declares min_ruby 3.2 -> map to "~> 24.0"
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.minimum_ruby_version = ">= 3.2"
              spec.homepage = "https://github.com/acme/demo"
            end
          G

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          described_class.run

          dest = File.join(project_root, "gemfiles", "modular", "style.gemfile")
          expect(File).to exist(dest)
          txt = File.read(dest)
          expect(txt).to include("gem \"rubocop-lts\", \"~> 24.0\"")
        end
      end
    end

    it "replaces require in spec/spec_helper.rb when confirmed, or skips when declined" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Arrange project spec_helper with kettle/dev
          spec_dir = File.join(project_root, "spec")
          FileUtils.mkdir_p(spec_dir)
          File.write(File.join(spec_dir, "spec_helper.rb"), "require 'kettle/dev'\n")
          # gemspec
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
            end
          G

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
          )

          # Case 1: confirm replacement
          allow(helpers).to receive(:ask).and_return(true)
          described_class.run
          content = File.read(File.join(spec_dir, "spec_helper.rb"))
          expect(content).to include('require "demo"')

          # Case 2: decline
          File.write(File.join(spec_dir, "spec_helper.rb"), "require 'kettle/dev'\n")
          allow(helpers).to receive(:ask).and_return(false)
          described_class.run
          content2 = File.read(File.join(spec_dir, "spec_helper.rb"))
          expect(content2).to include("require 'kettle/dev'")
        end
      end
    end

    it "aborts when env files changed and allowed is not set truthy" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Provide .envrc example so it is copied
          File.write(File.join(gem_root, ".envrc.example"), "export FOO=bar\n")
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
            end
          G

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          # Unset allowed so the code path aborts
          stub_env("allowed" => nil)
          expect { described_class.run }.to raise_error { |e| expect([SystemExit, Kettle::Dev::Error]).to include(e.class) }
        end
      end
    end

    it "installs .git-hooks templates and scripts locally by default" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          hooks_src = File.join(gem_root, ".git-hooks")
          FileUtils.mkdir_p(hooks_src)
          File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "🔖 Prepare release v\n")
          File.write(File.join(hooks_src, "footer-template.erb.txt"), "Footer <%= 1 %>\n")
          File.write(File.join(hooks_src, "commit-msg"), "#!/usr/bin/env ruby\n")
          File.write(File.join(hooks_src, "prepare-commit-msg"), "#!/bin/sh\n")

          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
            end
          G

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          described_class.run

          local_hooks = File.join(project_root, ".git-hooks")
          expect(File).to exist(File.join(local_hooks, "commit-subjects-goalie.txt"))
          expect(File).to exist(File.join(local_hooks, "footer-template.erb.txt"))
          expect(File).to exist(File.join(local_hooks, "commit-msg"))
          expect(File).to exist(File.join(local_hooks, "prepare-commit-msg"))
        end
      end
    end

    it "warns and continues if .env.local example copy raises" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
            end
          G

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )
          # Force prefer_example to raise when asked for .env.local
          allow(helpers).to receive(:prefer_example).and_wrap_original do |m, *args|
            if args.first&.end_with?(".env.local")
              raise "boom"
            else
              m.call(*args)
            end
          end

          expect { Kettle::Dev::Tasks::TemplateTask.run }.not_to raise_error
        end
      end
    end
  end
end
