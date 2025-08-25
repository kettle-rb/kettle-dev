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
    it "prefers .example files under .github/workflows and writes without .example" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Arrange template source
          gh_src = File.join(gem_root, ".github", "workflows")
          FileUtils.mkdir_p(gh_src)
          File.write(File.join(gh_src, "ci.yml"), "name: REAL\n")
          File.write(File.join(gh_src, "ci.yml.example"), "name: EXAMPLE\n")

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
          require "kettle/dev/tasks/template_task"
          expect { Kettle::Dev::Tasks::TemplateTask.run }.not_to raise_error

          # Assert
          dest_ci = File.join(project_root, ".github", "workflows", "ci.yml")
          expect(File).to exist(dest_ci)
          expect(File.read(dest_ci)).to include("EXAMPLE")
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

          require "kettle/dev/tasks/template_task"
          expect { Kettle::Dev::Tasks::TemplateTask.run }.not_to raise_error

          expect(File).to exist(File.join(project_root, ".env.local.example"))
          expect(File).not_to exist(File.join(project_root, ".env.local"))
        end
      end
    end
  end
end
