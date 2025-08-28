# frozen_string_literal: true

require "rake"

RSpec.describe Kettle::Dev::Tasks::TemplateTask do
  let(:helpers) { Kettle::Dev::TemplateHelpers }

  it "prefers hook_templates over KETTLE_DEV_HOOK_TEMPLATES for .git-hooks template choice" do
    Dir.mktmpdir do |project_root|
      # Minimal setup to let the run walk through hooks section
      allow(helpers).to receive_messages(
        project_root: project_root,
        gem_checkout_root: project_root,
        ensure_clean_git!: nil,
        gemspec_metadata: {
          gem_name: "demo",
          min_ruby: "3.1",
          forge_org: "acme",
          gh_org: "acme",
          funding_org: "acme",
          entrypoint_require: "kettle/dev",
          namespace: "Demo",
          namespace_shield: "demo",
          gem_shield: "demo",
        },
      )

      # Create a .git-hooks dir structure in checkout root with the two template files
      hooks_dir = File.join(project_root, ".git-hooks")
      FileUtils.mkdir_p(hooks_dir)
      File.write(File.join(hooks_dir, "commit-subjects-goalie.txt"), "x")
      File.write(File.join(hooks_dir, "footer-template.erb.txt"), "x")

      # Ensure destination local .git-hooks exists to observe skip vs copy
      dest_hooks_dir = File.join(project_root, ".git-hooks")
      FileUtils.mkdir_p(dest_hooks_dir)

      # Spy on copy to see if we skip
      copied = []
      allow(helpers).to receive(:copy_file_with_prompt) do |src, dest, *_args|
        copied << [src, dest]
      end

      # With conflicting ENV, prefer hook_templates=s (skip)
      stub_env(
        "hook_templates" => "s",
        "KETTLE_DEV_HOOK_TEMPLATES" => "g",
        # Avoid env file abort step
        "allowed" => "true",
      )
      expect { described_class.run }.not_to raise_error

      # Should have skipped copying, so no copy_file_with_prompt calls for goalie/footer
      expect(copied).to not_include(a_string_matching(/footer-template\.erb\.txt/)) &
        not_include(a_string_matching(/commit-subjects-goalie\.txt/)) # single expectation to satisfy RuboCop RSpec/MultipleExpectations
    end
  end
end
