# frozen_string_literal: true

# Unit specs for Kettle::Dev::Tasks::TemplateTask
# Mirrors a subset of behavior covered by the rake integration spec, but
# calls the class API directly for focused unit testing.

require "rake"
require "open3"

RSpec.describe Kettle::Dev::Tasks::TemplateTask do
  let(:helpers) { Kettle::Dev::TemplateHelpers }

  before do
    stub_env("allowed" => "true") # allow env file changes without abort
  end

  describe "::task_abort" do
    it "raises Kettle::Dev::Error when running under RSpec (abort is suppressed during specs)" do
      expect {
        described_class.task_abort("STOP ME")
      }.to raise_error(Kettle::Dev::Error, /STOP ME/)
    end
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

    it "keeps style.gemfile constraint unchanged when min_ruby is missing (else branch)" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          style_dir = File.join(gem_root, "gemfiles", "modular")
          FileUtils.mkdir_p(style_dir)
          File.write(File.join(style_dir, "style.gemfile.example"), <<~G)
            source "https://rubygems.org"
            gem "rubocop-lts", "~> 10.0"
          G
          # gemspec without any min ruby declaration
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
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
          expect(txt).to include("gem \"rubocop-lts\", \"~> 10.0\"")
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

    it "merges README sections and preserves first H1 emojis", :check_output do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Arrange
          template_readme = <<~MD
            # 🚀 Template Title
            
            ## Synopsis
            Template synopsis.
            
            ## Configuration
            Template configuration.
            
            ## Basic Usage
            Template usage.
            
            ## NOTE: Something
            Template note.
          MD
          File.write(File.join(gem_root, "README.md"), template_readme)

          existing_readme = <<~MD
            # 🎉 Existing Title
            
            ## Synopsis
            Existing synopsis.
            
            ## Configuration
            Existing configuration.
            
            ## Basic Usage
            Existing usage.
            
            ## NOTE: Something
            Existing note.
          MD
          File.write(File.join(project_root, "README.md"), existing_readme)

          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/demo"
            end
          G

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          # Exercise
          described_class.run

          # Assert merge and emoji preservation
          merged = File.read(File.join(project_root, "README.md"))
          expect(merged.lines.first).to match(/^#\s+🎉\s+Template Title/)
          expect(merged).to include("Existing synopsis.")
          expect(merged).to include("Existing configuration.")
          expect(merged).to include("Existing usage.")
          expect(merged).to include("Existing note.")
        end
      end
    end

    it "prefers .gitlab-ci.yml.example over .gitlab-ci.yml and writes destination without .example" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Arrange template files at root
          File.write(File.join(gem_root, ".gitlab-ci.yml"), "from: REAL\n")
          File.write(File.join(gem_root, ".gitlab-ci.yml.example"), "from: EXAMPLE\n")

          # Minimal gemspec so metadata scan works
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/demo"
            end
          G

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          # Exercise
          described_class.run

          # Assert destination is the non-example name and content from example
          dest = File.join(project_root, ".gitlab-ci.yml")
          expect(File).to exist(dest)
          expect(File.read(dest)).to include("EXAMPLE")
        end
      end
    end
  end
end

# frozen_string_literal: true

# Additional unit check for .env.local non-example source behavior
require "rake"
require "open3"

RSpec.describe Kettle::Dev::Tasks::TemplateTask do
  let(:helpers) { Kettle::Dev::TemplateHelpers }

  before do
    stub_env("allowed" => "true")
  end

  describe "::run" do
    it "copies non-example .env.local from gem as .env.local.example and does not touch .env.local" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Gem provides a non-example .env.local
          File.write(File.join(gem_root, ".env.local"), "SECRET=from_non_example\n")
          # Minimal gemspec for metadata
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

          # Assert .env.local.example created with correct content
          dest_example = File.join(project_root, ".env.local.example")
          expect(File).to exist(dest_example)
          expect(File.read(dest_example)).to include("SECRET=from_non_example")
          # Assert .env.local not created/overwritten
          expect(File).not_to exist(File.join(project_root, ".env.local"))
        end
      end
    end
  end
end
