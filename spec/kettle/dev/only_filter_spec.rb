# frozen_string_literal: true

RSpec.describe "only filter templating" do # rubocop:disable RSpec/DescribeClass
  let(:helpers) { Kettle::Dev::TemplateHelpers }

  context "when copy_file_with_prompt respects ENV['only']" do
    it "skips files not matching any pattern" do
      Dir.mktmpdir do |project_root|
        # Ensure relative matching uses this project root
        allow(helpers).to receive_messages(project_root: project_root)

        src = File.join(project_root, "src.txt")
        File.write(src, "content")
        dest1 = File.join(project_root, "README.md")
        dest2 = File.join(project_root, "docs", "guide.md")

        # Only include README.md
        stub_env("only" => "README.md")

        # Force non-interactive to avoid prompts if our check failed
        allow(helpers).to receive_messages(ask: true)

        # 1) non-matching path should be skipped
        helpers.copy_file_with_prompt(src, dest2, allow_create: true, allow_replace: true)
        expect(File).not_to exist(dest2)

        # 2) matching path should be written
        helpers.copy_file_with_prompt(src, dest1, allow_create: true, allow_replace: true)
        expect(File).to exist(dest1)
      end
    end

    it "supports multiple comma-separated patterns and subdirectories" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive_messages(project_root: project_root)
        src = File.join(project_root, "src.txt")
        File.write(src, "x")
        a = File.join(project_root, ".github", "workflows", "ci.yml")
        b = File.join(project_root, "lib", "demo.rb")
        c = File.join(project_root, "README.md")
        FileUtils.mkdir_p(File.dirname(a))
        FileUtils.mkdir_p(File.dirname(b))

        stub_env("only" => ".github/**,README.md")
        allow(helpers).to receive_messages(ask: true)

        # Included
        helpers.copy_file_with_prompt(src, a, allow_create: true, allow_replace: true)
        expect(File).to exist(a)
        helpers.copy_file_with_prompt(src, c, allow_create: true, allow_replace: true)
        expect(File).to exist(c)

        # Excluded
        helpers.copy_file_with_prompt(src, b, allow_create: true, allow_replace: true)
        expect(File).not_to exist(b)
      end
    end
  end

  context "when copy_dir_with_prompt respects ENV['only'] for individual files" do
    it "copies only matching files from a directory tree" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive_messages(project_root: project_root)
        # Build a source directory with two files
        src_dir = File.join(project_root, "src")
        FileUtils.mkdir_p(File.join(src_dir, ".github", "workflows"))
        FileUtils.mkdir_p(File.join(src_dir, "lib"))
        File.write(File.join(src_dir, ".github", "workflows", "ci.yml"), "A")
        File.write(File.join(src_dir, "lib", "ignored.rb"), "B")

        stub_env("only" => ".github/**")
        allow(helpers).to receive_messages(ask: true)

        helpers.copy_dir_with_prompt(src_dir, project_root)

        expect(File).to exist(File.join(project_root, ".github", "workflows", "ci.yml"))
        expect(File).not_to exist(File.join(project_root, "lib", "ignored.rb"))
      end
    end
  end
end
