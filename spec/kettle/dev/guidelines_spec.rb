# frozen_string_literal: true

RSpec.describe Kettle::Dev::Tasks::TemplateTask do
  describe "::run prefers .junie/guidelines.md.example" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    before do
      stub_env("allowed" => "true")
      stub_env("FUNDING_ORG" => "false")
    end

    it "copies .junie/guidelines.md from the .example source when both exist" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Arrange template files
          src_dir = File.join(gem_root, ".junie")
          FileUtils.mkdir_p(src_dir)
          File.write(File.join(src_dir, "guidelines.md"), "REAL-GUIDELINES\n")
          File.write(File.join(src_dir, "guidelines.md.example"), "EXAMPLE-GUIDELINES\n")

          # Minimal gemspec so metadata scan works
          File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/demo"
            end
          GEMSPEC

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          expect { described_class.run }.not_to raise_error

          dest = File.join(project_root, ".junie", "guidelines.md")
          expect(File).to exist(dest)
          content = File.read(dest)
          expect(content).to include("EXAMPLE-GUIDELINES")
          expect(content).not_to include("REAL-GUIDELINES")
        end
      end
    end
  end
end
