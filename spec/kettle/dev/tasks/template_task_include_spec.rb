# frozen_string_literal: true

RSpec.describe Kettle::Dev::Tasks::TemplateTask do
  describe "optional include for discord-notifier workflow" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    before do
      stub_env("allowed" => "true")
      stub_env("FUNDING_ORG" => "false")
    end

    it "excludes .github/workflows/discord-notifier.yml by default and includes when include matches" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Arrange .github/workflows with optional notifier and a normal workflow
          gh_wf = File.join(gem_root, ".github", "workflows")
          FileUtils.mkdir_p(gh_wf)
          File.write(File.join(gh_wf, "ci.yml"), "name: CI\n")
          File.write(File.join(gh_wf, "discord-notifier.yml"), "name: Discord\n")

          # Minimal gemspec for metadata
          File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/demo"
            end
          GEMSPEC

          allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

          # 1) Default: no include -> notifier should NOT be copied; ci.yml should be copied
          stub_env("include" => nil, "only" => nil)
          expect { described_class.run }.not_to raise_error
          expect(File).to exist(File.join(project_root, ".github", "workflows", "ci.yml"))
          expect(File).not_to exist(File.join(project_root, ".github", "workflows", "discord-notifier.yml"))

          # Cleanup outputs before second run
          FileUtils.rm_f(File.join(project_root, ".github", "workflows", "ci.yml"))

          # 2) With include matching notifier -> it should be copied
          stub_env("include" => ".github/workflows/discord-notifier.yml")
          expect { described_class.run }.not_to raise_error
          expect(File).to exist(File.join(project_root, ".github", "workflows", "discord-notifier.yml"))
        end
      end
    end
  end
end
