# frozen_string_literal: true

# rubocop:disable RSpec/NestedGroups, RSpec/MultipleExpectations

require "rake"

RSpec.describe "rake kettle:dev:template" do # rubocop:disable RSpec/DescribeClass
  include_context "with rake", "template"

  describe "task loading" do
    it "defines the task" do
      expect { rake_task }.not_to raise_error
      expect(Rake::Task.task_defined?("kettle:dev:template")).to be(true)
    end
  end

  context "when invoked in a temporary project" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    def write_gemspec(dir, name: "demo", min_ruby: ">= 3.1")
      File.write(File.join(dir, "#{name}.gemspec"), <<~G)
        Gem::Specification.new do |spec|
          spec.name = "#{name}"
          spec.required_ruby_version = "#{min_ruby}"
          spec.homepage = "https://github.com/acme/#{name}"
        end
      G
    end

    it "copies .github workflow files preferring .example and writes without .example" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          github_dir = File.join(gem_root, ".github", "workflows")
          FileUtils.mkdir_p(github_dir)
          # Provide both real and .example, the task should use .example as source
          File.write(File.join(github_dir, "ci.yml"), "name: REAL\n")
          File.write(File.join(github_dir, "ci.yml.example"), "name: EXAMPLE\n")

          write_gemspec(project_root)

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          stub_env("FUNDING_ORG" => "false")

          expect { invoke }.not_to raise_error

          dest_ci = File.join(project_root, ".github", "workflows", "ci.yml")
          expect(File).to exist(dest_ci)
          expect(File.read(dest_ci)).to include("EXAMPLE")
        end
      end
    end

    it "copies .env.local.example but does not create/overwrite .env.local" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          File.write(File.join(gem_root, ".env.local.example"), "SECRET=1\n")
          write_gemspec(project_root)

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          stub_env("allowed" => "true")
          stub_env("FUNDING_ORG" => "false")

          expect { invoke }.not_to raise_error

          expect(File).to exist(File.join(project_root, ".env.local.example"))
          expect(File).not_to exist(File.join(project_root, ".env.local"))
        end
      end
    end
  end
end
# rubocop:enable RSpec/NestedGroups, RSpec/MultipleExpectations
