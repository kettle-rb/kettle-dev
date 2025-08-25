# frozen_string_literal: true

# Unit specs for Kettle::Dev::Tasks::InstallTask

require "rake"

RSpec.describe Kettle::Dev::Tasks::InstallTask do
  include_context "with stubbed env"

  let(:helpers) { Kettle::Dev::TemplateHelpers }

  before do
    stub_env("force" => "true") # auto-accept prompts in InstallTask
    stub_env("allowed" => "true") # if .envrc changed, proceed
  end

  describe "::run" do
    it "invokes the template task and adds .env.local to .gitignore when missing" do
      Dir.mktmpdir do |project_root|
        # Minimal gemspec to avoid homepage checks failing on I/O
        File.write(File.join(project_root, "demo.gemspec"), <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.required_ruby_version = ">= 3.1"
          end
        G

        # Pretend templating did not modify .gitignore so InstallTask manages it
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          ask: true,
        )

        # Ensure .tool-versions exists and legacy files exist to be cleaned
        File.write(File.join(project_root, ".tool-versions"), "ruby 3.1.0\n")
        File.write(File.join(project_root, ".ruby-version"), "3.1.0\n")
        File.write(File.join(project_root, ".ruby-gemset"), "demo\n")

        # Stub the template rake task the installer calls
        fake_task = instance_double(Rake::Task)
        allow(fake_task).to receive(:invoke)
        allow(Rake::Task).to receive(:[]).with("kettle:dev:template").and_return(fake_task)

        require "kettle/dev/tasks/install_task"

        expect { Kettle::Dev::Tasks::InstallTask.run }.not_to raise_error
        expect(fake_task).to have_received(:invoke)

        gitignore = File.join(project_root, ".gitignore")
        expect(File).to exist(gitignore)
        expect(File.read(gitignore)).to include(".env.local")

        # Legacy version/gemset files should be removed when we auto-accept removal
        expect(File).not_to exist(File.join(project_root, ".ruby-version"))
        expect(File).not_to exist(File.join(project_root, ".ruby-gemset"))
      end
    end
  end
end
