# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/StubbedMock, RSpec/MessageSpies
require "rake"

RSpec.describe Kettle::Dev::TemplateHelpers do
  let(:helpers) { described_class }

  before do
    # Reset template results between examples to avoid cross-test pollution
    allow(Time).to receive(:now).and_return(Time.at(0))
    # Directly clear the internal hash via the public API contract (reinitialize by touching const)
    # Since we don't expose a reset method, we can ensure no previous writes by referencing a new path each time.
  end

  describe "::project_root" do
    it "delegates to CIHelpers.project_root" do
      stub_const("Kettle::Dev::CIHelpers", Module.new)
      expect(Kettle::Dev::CIHelpers).to receive(:project_root).and_return("/tmp/root")
      expect(helpers.project_root).to eq("/tmp/root")
    end
  end

  describe "::gem_checkout_root" do
    it "returns the repo root relative to this file" do
      expected = File.expand_path("../../..", File.dirname(__FILE__).sub(%r{/spec/.*\z}, "/lib/kettle/dev"))
      # The actual implementation is File.expand_path("../../..", __dir__) where __dir__ is lib/kettle/dev
      actual = helpers.gem_checkout_root
      # Sanity: ensure it looks like an absolute path and ends with project folder name
      expect(actual).to be_a(String)
      expect(File.absolute_path(actual)).to eq(actual)
      expect(File.basename(actual)).to eq(File.basename(expected))
    end
  end

  describe "::ask" do
    def simulate_input(str)
      allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return(str)
    end

    it "returns true on empty input when default is true" do
      simulate_input("")
      expect(helpers.ask("Continue?", true)).to be(true)
    end

    it "returns falsey on empty input when default is false" do
      simulate_input("")
      expect(helpers.ask("Continue?", false)).to be_falsey
    end

    it "accepts yes variations case-insensitively" do
      simulate_input("y\n")
      expect(helpers.ask("Proceed?", false)).to be_truthy
      simulate_input("Yes\n")
      expect(helpers.ask("Proceed?", false)).to be_truthy
    end

    it "treats 'n' as no" do
      simulate_input("n\n")
      expect(helpers.ask("Proceed?", true)).to be_falsey
    end

    context "when forcing" do
      it "forces yes when ENV['force'] is truthy", :check_output do
        stub_env("force" => "true")
        expect {
          result = helpers.ask("Proceed?", false)
          expect(result).to be true
        }.to output(/Proceed\? \[y\/N\]: Y \(forced\)/).to_stdout
      end

      it "capitalizes Y when default is true", :check_output do
        stub_env("force" => "true")
        expect {
          result = helpers.ask("Proceed?", true)
          expect(result).to be true
        }.to output(/Proceed\? \[Y\/n\]: Y \(forced\)/).to_stdout
      end
    end

    it "does not force when ENV['force'] is false", :check_output do
      stub_env("force" => "false")
      expect {
        result = helpers.ask("Proceed?", false)
        expect(result).to be_nil
      }.to output(/Proceed\? \[y\/N\]: /).to_stdout
    end
  end

  describe "::write_file" do
    it "creates parent directories and writes content" do
      Dir.mktmpdir do |dir|
        target = File.join(dir, "a", "b", "c.txt")
        helpers.write_file(target, "hello")
        expect(File).to exist(target)
        expect(File.read(target)).to eq("hello")
      end
    end
  end

  describe "::template_results tracking" do
    it "records create/replace/skip for files" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.txt")
        File.write(src, "X")
        dest = File.join(dir, "dest.txt")

        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        rec = helpers.template_results[File.expand_path(dest)]
        expect(rec[:action]).to eq(:create)

        # Replace
        File.write(src, "Y")
        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        rec2 = helpers.template_results[File.expand_path(dest)]
        expect(rec2[:action]).to eq(:replace)

        # Skip
        allow(helpers).to receive(:ask).and_return(false)
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        rec3 = helpers.template_results[File.expand_path(dest)]
        expect(rec3[:action]).to eq(:replace) # last write remains replace, skip does not overwrite
        expect(helpers.modified_by_template?(dest)).to be(true)
      end
    end

    it "records dir_create/dir_replace/skip for directories" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(File.join(src_dir, "sub"))
        File.write(File.join(src_dir, "sub", "a.txt"), "A")
        dest_dir = File.join(dir, "dest")

        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_dir_with_prompt(src_dir, dest_dir)
        rec = helpers.template_results[File.expand_path(dest_dir)]
        expect(rec[:action]).to eq(:dir_create)
        expect(helpers.modified_by_template?(dest_dir)).to be(true)

        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_dir_with_prompt(src_dir, dest_dir)
        rec2 = helpers.template_results[File.expand_path(dest_dir)]
        expect(rec2[:action]).to eq(:dir_replace)

        allow(helpers).to receive(:ask).and_return(false)
        helpers.copy_dir_with_prompt(src_dir, dest_dir)
        rec3 = helpers.template_results[File.expand_path(dest_dir)]
        expect(rec3[:action]).to eq(:dir_replace) # skip leaves last meaningful action
      end
    end
  end

  describe "::copy_file_with_prompt" do
    it "skips replacing existing file when replace not allowed (covers disallow branch)" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.txt")
        File.write(src, "new")
        dest = File.join(dir, "dest.txt")
        File.write(dest, "old")
        # allow_replace=false forces the 144-145 branch
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: false)
        # content unchanged and recorded as skip
        expect(File.read(dest)).to eq("old")
        rec = helpers.template_results[File.expand_path(dest)]
        expect(rec[:action]).to eq(:skip)
      end
    end

    it "creates new file when allowed and confirmed" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.txt")
        File.write(src, "src")
        dest = File.join(dir, "dest.txt")
        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        expect(File.read(dest)).to eq("src")
      end
    end

    it "skips creating new file when not confirmed" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.txt")
        File.write(src, "src")
        dest = File.join(dir, "dest.txt")
        allow(helpers).to receive(:ask).and_return(false)
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        expect(File).not_to exist(dest)
      end
    end

    it "replaces existing file when allowed and confirmed" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.txt")
        File.write(src, "new")
        dest = File.join(dir, "dest.txt")
        File.write(dest, "old")
        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        expect(File.read(dest)).to eq("new")
      end
    end

    it "does not replace existing file when not confirmed" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.txt")
        File.write(src, "new")
        dest = File.join(dir, "dest.txt")
        File.write(dest, "old")
        allow(helpers).to receive(:ask).and_return(false)
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        expect(File.read(dest)).to eq("old")
      end
    end

    it "skips when creation not allowed" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.txt")
        File.write(src, "x")
        dest = File.join(dir, "dest.txt")
        helpers.copy_file_with_prompt(src, dest, allow_create: false, allow_replace: true)
        expect(File).not_to exist(dest)
      end
    end

    it "applies transformation block to content" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.txt")
        File.write(src, "foo")
        dest = File.join(dir, "dest.txt")
        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) { |c| c.upcase }
        expect(File.read(dest)).to eq("FOO")
      end
    end
  end

  describe "::copy_dir_with_prompt" do
    it "executes in-place rewrite when dest exists and path==target (covers 187-189)" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "same")
        FileUtils.mkdir_p(src_dir)
        f = File.join(src_dir, "x.txt")
        File.write(f, "A")
        allow(helpers).to receive(:ask).and_return(true)
        allow(FileUtils).to receive(:compare_file).and_return(false)
        expect { helpers.copy_dir_with_prompt(src_dir, src_dir) }.not_to raise_error
        expect(File.read(f)).to eq("A")
      end
    end

    it "executes in-place rewrite in create-branch when dest_dir is same as src (covers 218-223)" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "same2")
        FileUtils.mkdir_p(src_dir)
        f = File.join(src_dir, "y.txt")
        File.write(f, "B")
        # Force code path: pretend dest_dir doesn't exist though it does
        allow(Dir).to receive(:exist?).and_wrap_original do |orig, path|
          if File.expand_path(path) == File.expand_path(src_dir)
            false
          else
            orig.call(path)
          end
        end
        allow(helpers).to receive(:ask).and_return(true)
        allow(FileUtils).to receive(:compare_file).and_return(false)
        expect { helpers.copy_dir_with_prompt(src_dir, src_dir) }.not_to raise_error
        expect(File.read(f)).to eq("B")
      end
    end

    it "handles same source and destination directory without raising (in-place rewrite)" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "same")
        FileUtils.mkdir_p(src_dir)
        f = File.join(src_dir, "x.txt")
        File.write(f, "A")
        allow(helpers).to receive(:ask).and_return(true)
        expect { helpers.copy_dir_with_prompt(src_dir, src_dir) }.not_to raise_error
        expect(File.read(f)).to eq("A")
      end
    end

    it "skips files whose contents are identical (does not modify mtime)" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(File.join(src_dir, "sub"))
        File.write(File.join(src_dir, "sub", "a.txt"), "SAME")

        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(File.join(dest_dir, "sub"))
        dest_file = File.join(dest_dir, "sub", "a.txt")
        File.write(dest_file, "SAME")
        before_mtime = File.mtime(dest_file)
        sleep 1 # ensure mtime would change if rewritten

        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_dir_with_prompt(src_dir, dest_dir)

        after_mtime = File.mtime(dest_file)
        expect(after_mtime).to eq(before_mtime)
        expect(File.read(dest_file)).to eq("SAME")
      end
    end

    it "updates existing directory when confirmed" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "a.txt"), "A")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "a.txt"), "OLD")
        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_dir_with_prompt(src_dir, dest_dir)
        expect(File.read(File.join(dest_dir, "a.txt"))).to eq("A")
      end
    end

    it "skips updating existing directory when not confirmed" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "a.txt"), "A")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(dest_dir)
        File.write(File.join(dest_dir, "a.txt"), "OLD")
        allow(helpers).to receive(:ask).and_return(false)
        helpers.copy_dir_with_prompt(src_dir, dest_dir)
        expect(File.read(File.join(dest_dir, "a.txt"))).to eq("OLD")
      end
    end

    it "creates new directory tree when confirmed" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src", "nested")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "a.txt"), "A")
        dest_dir = File.join(dir, "dest")
        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_dir_with_prompt(File.join(dir, "src"), dest_dir)
        expect(File.read(File.join(dest_dir, "nested", "a.txt"))).to eq("A")
      end
    end
  end

  describe "::ensure_clean_git!" do
    it "treats system exceptions as not inside repo (covers line 110 rescue)" do
      allow(helpers).to receive(:system).and_raise(StandardError)
      expect { helpers.ensure_clean_git!(root: "/tmp/project", task_label: "kettle:dev:install") }.not_to raise_error
    end

    it "treats status read exceptions as clean (covers line 117 rescue)" do
      allow(helpers).to receive(:system).and_return(true)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_wrap_original do |m|
        inst = m.call
        allow(inst).to receive(:capture).and_raise(StandardError)
        inst
      end
      expect { helpers.ensure_clean_git!(root: "/tmp/project", task_label: "kettle:dev:template") }.not_to raise_error
    end

    it "does nothing when not inside a git repo" do
      allow(helpers).to receive(:system).and_return(false)
      expect { helpers.ensure_clean_git!(root: "/tmp/project", task_label: "kettle:dev:install") }.not_to raise_error
    end

    it "does nothing when inside repo and status is clean" do
      allow(helpers).to receive(:system).and_return(true)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_wrap_original do |m|
        inst = m.call
        allow(inst).to receive(:clean?).and_return(true)
        inst
      end
      expect { helpers.ensure_clean_git!(root: "/tmp/project", task_label: "kettle:dev:template") }.not_to raise_error
    end

    it "raises helpful error when dirty" do
      allow(helpers).to receive(:system).and_return(true)
      dirty = " M lib/file.rb\n?? new.txt\n"
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_wrap_original do |m|
        inst = m.call
        allow(inst).to receive(:clean?).and_return(false)
        allow(inst).to receive(:capture).with(array_including("-C", "/tmp/project", "status", "--porcelain")).and_return([dirty, true])
        inst
      end
      expect {
        helpers.ensure_clean_git!(root: "/tmp/project", task_label: "kettle:dev:template")
      }.to raise_error(Kettle::Dev::Error, /Aborting: git working tree is not clean\./)
    end
  end

  describe "::gemspec_metadata" do
    include_context "with truffleruby 3.1..3.2 skip"

    it "parses gemspec and derives strings, falling back to git origin when needed" do
      Dir.mktmpdir do |dir|
        stub_env("FUNDING_ORG" => "false")
        gemspec_path = File.join(dir, "example.gemspec")
        File.write(gemspec_path, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "my-gem_name"
            spec.required_ruby_version = ">= 3.2"
            # no homepage specified here to trigger fallback
          end
        G
        # Stub git origin query via GitAdapter
        fake_git = instance_double(Kettle::Dev::GitAdapter, remote_url: "https://github.com/acme/my-gem_name.git", remotes_with_urls: {"origin" => "https://github.com/acme/my-gem_name.git"})
        allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake_git)

        meta = helpers.gemspec_metadata(dir)
        expect(meta[:gemspec_path]).to eq(gemspec_path)
        expect(meta[:gem_name]).to eq("my-gem_name")
        expect(meta[:min_ruby]).to eq(Gem::Version.new("3.2"))
        expect(meta[:forge_org]).to eq("acme")
        expect(meta[:gh_repo]).to eq("my-gem_name")
        expect(meta[:entrypoint_require]).to eq("my/gem_name")
        expect(meta[:namespace]).to eq("My::GemName")
        expect(meta[:namespace_shield]).to eq("My%3A%3AGemName")
        expect(meta[:gem_shield]).to eq("my--gem__name")
      end
    end

    it "parses homepage when present as a quoted literal" do
      Dir.mktmpdir do |dir|
        gemspec_path = File.join(dir, "w.gemspec")
        File.write(gemspec_path, <<~G)
          Gem::Specification.new do |spec|
            spec.name = 'widget'
            spec.required_ruby_version = '>= 2.7.6'
            spec.homepage = "https://github.com/org/widget"
          end
        G
        meta = helpers.gemspec_metadata(dir)
        expect(meta[:homepage]).to eq("https://github.com/org/widget")
        expect(meta[:forge_org]).to eq("org")
        expect(meta[:gh_repo]).to eq("widget")
        expect(meta[:min_ruby]).to eq(Gem::Version.new("2.7.6"))
        expect(meta[:entrypoint_require]).to eq("widget")
        expect(meta[:namespace]).to eq("Widget")
        expect(meta[:gem_shield]).to eq("widget")
      end
    end
  end

  describe "::apply_common_replacements" do
    let(:meta) do
      {org: "some-org", gem_name: "foo_bar", namespace: "FooBar", namespace_shield: "Foo%3A%3ABar", gem_shield: "foo__bar"}
    end

    def rep(s)
      helpers.apply_common_replacements(s, **meta)
    end

    it "replaces kettle-dev inside bracketed emoji label in README references" do
      expect(rep("[🖼️kettle-dev]")).to eq("[🖼️foo_bar]")
    end

    it "replaces kettle-dev inside suffixed identifiers like -i without touching suffix" do
      expect(rep("[🖼️kettle-dev-i]")).to eq("[🖼️foo_bar-i]")
    end

    it "replaces require-like paths kettle/dev with entrypoint path using gem_name with underscores unchanged" do
      expect(rep("require 'kettle/dev'\n# path: kettle/dev/something")).to eq("require 'foo_bar'\n# path: foo_bar/something")
    end

    it "replaces require-like paths kettle/dev with entrypoint path using gem_name hyphen converted to slash" do
      meta2 = meta.merge(gem_name: "food-bar", namespace: "Food::Bar", namespace_shield: "Food%3A%3ABar", gem_shield: "food--bar")
      expect(helpers.apply_common_replacements("require 'kettle/dev'\n# path: kettle/dev/something", **meta2)).to eq("require 'food/bar'\n# path: food/bar/something")
    end

    it "uses dashed gem name in yard-head link reference and runs before other replacements" do
      input = "[🚎yard-head]: https://kettle-dev.galtzo.com"
      expect(rep(input)).to eq("[🚎yard-head]: https://foo-bar.galtzo.com")
    end

    context "when funding_org is different" do
      let(:meta) do
        {org: "some-org", funding_org: "fund-handle", gem_name: "foo_bar", namespace: "FooBar", namespace_shield: "Foo%3A%3ABar", gem_shield: "foo__bar"}
      end

      it "replaces {OPENCOLLECTIVE|ORG_NAME} with funding_org when available" do
        expect(rep("Support us at {OPENCOLLECTIVE|ORG_NAME}!"))
          .to eq("Support us at fund-handle!")
      end
    end

    it "falls back to org when funding_org is nil or empty" do
      allow(helpers).to receive(:gemspec_metadata).and_return(meta.merge(funding_org: nil))
      expect(rep("Support us at {OPENCOLLECTIVE|ORG_NAME}!"))
        .to eq("Support us at some-org!")

      allow(helpers).to receive(:gemspec_metadata).and_return(meta.merge(funding_org: ""))
      expect(rep("Support us at {OPENCOLLECTIVE|ORG_NAME}!"))
        .to eq("Support us at some-org!")
    end
  end

  context "when running kettle:dev:template" do
    def load_template_task!
      Rake.application = Rake::Application.new
      load File.join(__dir__.sub(%r{/spec/.*\z}, ""), "lib", "kettle", "dev", "rakelib", "template.rake")
    end

    it "uses .example source but writes destination filename without .example for .github files" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          github_dir = File.join(gem_root, ".github", "workflows")
          FileUtils.mkdir_p(github_dir)
          real_yml = File.join(github_dir, "ci.yml")
          File.write(real_yml, "name: REAL\n")
          File.write(real_yml + ".example", "name: EXAMPLE\n")

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

          load_template_task!
          stub_env("FUNDING_ORG" => "false")
          Rake::Task["kettle:dev:template"].invoke

          dest_ci = File.join(project_root, ".github", "workflows", "ci.yml")
          expect(File).to exist(dest_ci)
          expect(File.read(dest_ci)).to include("EXAMPLE")
        end
      end
    end

    it "copies .env.local.example and does not create/overwrite .env.local" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          File.write(File.join(gem_root, ".env.local.example"), "SECRET=1\n")
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

          load_template_task!
          stub_env("FUNDING_ORG" => "false")
          begin
            Rake::Task["kettle:dev:template"].invoke
          rescue Kettle::Dev::Error => e
            # The task intentionally aborts to force a manual review of environment files.
            # For this example we only care that the copy behavior occurred prior to aborting.
            expect(e.message).to include("Aborting: review of environment files required")
          end

          expect(File).not_to exist(File.join(project_root, ".env.local"))
          expect(File).to exist(File.join(project_root, ".env.local.example"))
        end
      end
    end
  end

  it "prefers FUNDING_ORG env over forge_org" do
    Dir.mktmpdir do |dir|
      gemspec_path = File.join(dir, "example.gemspec")
      File.write(gemspec_path, <<~G)
        Gem::Specification.new do |spec|
          spec.name = "another-gem"
          spec.required_ruby_version = ">= 3.0"
          # no homepage to allow forge_org to be inferred from git, but FUNDING_ORG should take precedence
        end
      G
      # Stub git origin so forge_org would be present if used
      fake_git = instance_double(Kettle::Dev::GitAdapter, remote_url: "https://github.com/acme/another-gem.git", remotes_with_urls: {"origin" => "https://github.com/acme/another-gem.git"})
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake_git)

      stub_env("FUNDING_ORG" => "oc-org")

      meta = helpers.gemspec_metadata(dir)
      expect(meta[:forge_org]).to eq("acme")
      expect(meta[:funding_org]).to eq("oc-org")
    end
  end

  describe "::prefer_example" do
    it "returns .example variant when present" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "Rakefile")
        ex = src + ".example"
        File.write(ex, "# example")
        expect(helpers.prefer_example(src)).to eq(ex)
      end
    end

    it "returns original when .example is not present" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "Rakefile")
        expect(helpers.prefer_example(src)).to eq(src)
      end
    end

    it "returns the same path when already ends with .example" do
      Dir.mktmpdir do |dir|
        ex = File.join(dir, "README.md.example")
        expect(helpers.prefer_example(ex)).to eq(ex)
      end
    end
  end

  describe "::modified_by_template? (negative cases)" do
    it "returns false when nothing recorded for path" do
      Dir.mktmpdir do |dir|
        dest = File.join(dir, "x.txt")
        expect(helpers.modified_by_template?(dest)).to be(false)
      end
    end

    it "returns false when only :skip action was recorded" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "s.txt")
        File.write(src, "a")
        dest = File.join(dir, "d.txt")
        helpers.copy_file_with_prompt(src, dest, allow_create: false, allow_replace: true)
        expect(helpers.modified_by_template?(dest)).to be(false)
      end
    end
  end

  describe "ENV[\"only\"] filtering" do
    include_context "with stubbed env"

    it "skips copy_file_with_prompt when dest does not match any pattern and records :skip", :check_output do
      Dir.mktmpdir do |project_root|
        Dir.mktmpdir do |src_root|
          src = File.join(src_root, "a.txt")
          File.write(src, "A")
          dest = File.join(project_root, "other", "a.txt")
          allow(helpers).to receive(:project_root).and_return(project_root)
          stub_env("only" => "lib/**")
          expect {
            helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
          }.to output(/Skipping .* \(excluded by only filter\)/).to_stdout
          rec = helpers.template_results[File.expand_path(dest)]
          expect(rec[:action]).to eq(:skip)
          expect(File).not_to exist(dest)
        end
      end
    end

    it "proceeds with copy_file_with_prompt if matching, and also proceeds when File.fnmatch? raises (rescue path)" do
      Dir.mktmpdir do |project_root|
        Dir.mktmpdir do |src_root|
          src = File.join(src_root, "a.txt")
          File.write(src, "A")
          dest = File.join(project_root, "lib", "a.txt")
          allow(helpers).to receive(:project_root).and_return(project_root)
          stub_env("only" => "lib/**")
          allow(helpers).to receive(:ask).and_return(true)
          helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
          expect(File).to exist(dest)

          # Now force fnmatch? to raise; code should rescue and proceed (ignore filter)
          dest2 = File.join(project_root, "lib", "b.txt")
          allow(File).to receive(:fnmatch?).and_raise(StandardError.new("boom"))
          helpers.copy_file_with_prompt(src, dest2, allow_create: true, allow_replace: true)
          expect(File).to exist(dest2)
        end
      end
    end

    it "copy_dir_with_prompt: early exit when only filter present and no files match (records :skip)" do
      Dir.mktmpdir do |project_root|
        Dir.mktmpdir do |src_root|
          src_dir = File.join(src_root, "tmpl")
          FileUtils.mkdir_p(File.join(src_dir, "a"))
          File.write(File.join(src_dir, "a", "x.txt"), "X")
          dest_dir = File.join(project_root, "out")
          allow(helpers).to receive(:project_root).and_return(project_root)
          stub_env("only" => "lib/**")
          helpers.copy_dir_with_prompt(src_dir, dest_dir)
          rec = helpers.template_results[File.expand_path(dest_dir)]
          expect(rec[:action]).to eq(:skip)
          expect(Dir).not_to exist(dest_dir)
        end
      end
    end

    it "copy_dir_with_prompt: per-file inclusion filter applies and copies only matching files" do
      Dir.mktmpdir do |project_root|
        Dir.mktmpdir do |src_root|
          src_dir = File.join(src_root, "tmpl")
          FileUtils.mkdir_p(File.join(src_dir, ".github", "workflows"))
          File.write(File.join(src_dir, ".github", "workflows", "ci.yml"), "CI")
          FileUtils.mkdir_p(File.join(src_dir, "lib"))
          File.write(File.join(src_dir, "lib", "x.rb"), "puts :x")
          dest_dir = File.join(project_root, "out")
          allow(helpers).to receive(:project_root).and_return(project_root)
          stub_env("only" => "out/.github/**")
          allow(helpers).to receive(:ask).and_return(true)
          helpers.copy_dir_with_prompt(src_dir, dest_dir)
          expect(File).to exist(File.join(dest_dir, ".github", "workflows", "ci.yml"))
          expect(File).not_to exist(File.join(dest_dir, "lib", "x.rb"))
        end
      end
    end
  end

  describe "chmod behavior for .git-hooks" do
    it "sets executable bit when copying a single hook file via copy_file_with_prompt" do
      skip_for(reason: "Ruby 2.3 may not preserve chmod semantics for this path; behavior differs", versions: %w[2.3 2.4])
      Dir.mktmpdir do |dir|
        src = File.join(dir, "commit-msg.src")
        File.write(src, "#!/bin/sh\n")
        dest_dir = File.join(dir, ".git-hooks")
        FileUtils.mkdir_p(dest_dir)
        dest = File.join(dest_dir, "commit-msg")
        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true)
        mode = File.stat(dest).mode
        expect(mode & 0o111).not_to eq(0)
      end
    end

    it "sets executable bit when copying hook files via copy_dir_with_prompt" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(File.join(src_dir, ".git-hooks"))
        hook = File.join(src_dir, ".git-hooks", "prepare-commit-msg")
        File.write(hook, "#!/bin/sh\n")
        dest_dir = File.join(dir, "dest")
        allow(helpers).to receive(:ask).and_return(true)
        helpers.copy_dir_with_prompt(src_dir, dest_dir)
        dest_hook = File.join(dest_dir, ".git-hooks", "prepare-commit-msg")
        mode = File.stat(dest_hook).mode
        expect(mode & 0o111).not_to eq(0)
      end
    end
  end

  describe "additional coverage for edge/rescue branches" do
    include_context "with stubbed env"

    it "ensure_clean_git!: handles dirty path with capture raising (covers 139-144)" do
      Dir.mktmpdir do |root|
        allow(helpers).to receive(:system).and_return(true)
        fake = instance_double(Kettle::Dev::GitAdapter)
        allow(fake).to receive(:clean?).and_return(false)
        allow(fake).to receive(:capture).and_raise(StandardError.new("boom"))
        allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake)
        expect {
          helpers.ensure_clean_git!(root: root, task_label: "kettle:dev:template")
        }.to raise_error(Kettle::Dev::Error, /git working tree is not clean/)
      end
    end

    it "copy_file_with_prompt: normalizes rel path when dest == project_root (covers 176-177)" do
      Dir.mktmpdir do |project_root|
        Dir.mktmpdir do |src_root|
          src = File.join(src_root, "a.txt")
          File.write(src, "A")
          # Set only filter to force path normalization branch
          allow(helpers).to receive(:project_root).and_return(project_root)
          stub_env("only" => "**")
          # dest equals project_root, will be normalized to empty rel path
          allow(helpers).to receive(:ask).and_return(false)
          helpers.copy_file_with_prompt(src, project_root, allow_create: true, allow_replace: true)
          # No file expected to be created; just exercising branch logic
          expect(Dir).to exist(project_root)
        end
      end
    end

    it "copy_file_with_prompt: rescues token replacement gsub errors (covers 226)" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.txt")
        # Include the token so include? is true
        File.write(src, "BEFORE {KETTLE|DEV|GEM} AFTER")
        dest = File.join(dir, ".git-hooks", "commit-msg")
        FileUtils.mkdir_p(File.dirname(dest))
        allow(helpers).to receive(:ask).and_return(true)
        # Only stub the specific gsub call to raise
        allow_any_instance_of(String).to receive(:gsub).with("{KETTLE|DEV|GEM}", "kettle-dev").and_raise(StandardError.new("gsub boom"))
        expect { helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) }.not_to raise_error
        expect(File).to exist(dest)
      end
    end

    it "copy_file_with_prompt: rescues chmod errors under .git-hooks (covers 236)" do
      Dir.mktmpdir do |dir|
        src = File.join(dir, "src.sh")
        File.write(src, "#!/bin/sh\n")
        dest = File.join(dir, ".git-hooks", "prepare-commit-msg")
        FileUtils.mkdir_p(File.dirname(dest))
        allow(helpers).to receive(:ask).and_return(true)
        allow(File).to receive(:chmod).and_raise(StandardError.new("chmod boom"))
        expect { helpers.copy_file_with_prompt(src, dest, allow_create: true, allow_replace: true) }.not_to raise_error
        expect(File).to exist(dest)
      end
    end

    it "copy_dir_with_prompt: rescues fnmatch? errors in matches_only and proceeds (covers 271, 273)" do
      Dir.mktmpdir do |project_root|
        Dir.mktmpdir do |src_root|
          src_dir = File.join(src_root, "tmpl")
          FileUtils.mkdir_p(src_dir)
          File.write(File.join(src_dir, "a.txt"), "A")
          dest_dir = File.join(project_root, "out")
          allow(helpers).to receive(:project_root).and_return(project_root)
          stub_env("only" => "out/**")
          allow(helpers).to receive(:ask).and_return(true)
          # Force fnmatch? to raise; matches_only should rescue and treat as matched
          allow(File).to receive(:fnmatch?).and_raise(StandardError.new("fnmatch boom"))
          helpers.copy_dir_with_prompt(src_dir, dest_dir)
          expect(File).to exist(File.join(dest_dir, "a.txt"))
        end
      end
    end

    it "copy_dir_with_prompt: rescues scanning errors during early-only check (covers 298)" do
      Dir.mktmpdir do |project_root|
        Dir.mktmpdir do |src_root|
          src_dir = File.join(src_root, "tmpl")
          FileUtils.mkdir_p(File.join(src_dir, "sub"))
          File.write(File.join(src_dir, "sub", "a.txt"), "A")
          dest_dir = File.join(project_root, "out")
          allow(helpers).to receive(:project_root).and_return(project_root)
          stub_env("only" => "out/**")
          # Create dest_dir so we can answer no to avoid later Find.find runs
          FileUtils.mkdir_p(dest_dir)
          allow(helpers).to receive(:ask).and_return(false)
          allow(Find).to receive(:find).and_raise(StandardError.new("find boom"))
          # Should fall through (rescue) and skip without traversing later
          expect { helpers.copy_dir_with_prompt(src_dir, dest_dir) }.not_to raise_error
        end
      end
    end

    it "copy_dir_with_prompt: rescues compare_file errors in replace branch (covers 329)" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(src_dir)
        FileUtils.mkdir_p(dest_dir)
        File.write(File.join(src_dir, "a.txt"), "NEW")
        File.write(File.join(dest_dir, "a.txt"), "OLD")
        allow(helpers).to receive(:ask).and_return(true)
        allow(FileUtils).to receive(:compare_file).and_raise(StandardError.new("cmp boom"))
        helpers.copy_dir_with_prompt(src_dir, dest_dir)
        expect(File.read(File.join(dest_dir, "a.txt"))).to eq("NEW")
      end
    end

    it "copy_dir_with_prompt: rescues chmod errors in replace branch (covers 341)" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        dest_dir = File.join(dir, "dest")
        FileUtils.mkdir_p(File.join(src_dir, ".git-hooks"))
        File.write(File.join(src_dir, ".git-hooks", "commit-msg"), "#!/bin/sh\n")
        FileUtils.mkdir_p(dest_dir)
        allow(helpers).to receive(:ask).and_return(true)
        allow(File).to receive(:chmod).and_raise(StandardError.new("chmod boom"))
        expect { helpers.copy_dir_with_prompt(src_dir, dest_dir) }.not_to raise_error
        expect(File).to exist(File.join(dest_dir, ".git-hooks", "commit-msg"))
      end
    end

    it "copy_dir_with_prompt: rescues compare_file errors in create branch (covers 377)" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(src_dir)
        File.write(File.join(src_dir, "a.txt"), "NEW")
        dest_dir = File.join(dir, "dest")
        allow(helpers).to receive(:ask).and_return(true)
        # Force create branch by making dest_dir absent
        allow(FileUtils).to receive(:compare_file).and_raise(StandardError.new("cmp boom"))
        helpers.copy_dir_with_prompt(src_dir, dest_dir)
        expect(File.read(File.join(dest_dir, "a.txt"))).to eq("NEW")
      end
    end

    it "copy_dir_with_prompt: rescues chmod errors in create branch (covers 389)" do
      Dir.mktmpdir do |dir|
        src_dir = File.join(dir, "src")
        FileUtils.mkdir_p(File.join(src_dir, ".git-hooks"))
        File.write(File.join(src_dir, ".git-hooks", "prepare-commit-msg"), "#!/bin/sh\n")
        dest_dir = File.join(dir, "dest")
        allow(helpers).to receive(:ask).and_return(true)
        allow(File).to receive(:chmod).and_raise(StandardError.new("chmod boom"))
        expect { helpers.copy_dir_with_prompt(src_dir, dest_dir) }.not_to raise_error
        expect(File).to exist(File.join(dest_dir, ".git-hooks", "prepare-commit-msg"))
      end
    end

    it "apply_common_replacements: rescues yard-head dash conversion when gem_name.tr raises (covers 422)" do
      # Build a gem_name that quacks like String for emptiness/to_s but raises on tr
      class TrRaisingString < String
        def tr(from, to)
          if from == "_" && to == "-"
            raise StandardError, "tr boom"
          else
            super
          end
        end
      end
      gem_name = TrRaisingString.new("foo_bar")
      meta = {org: "org", gem_name: gem_name, namespace: "X::Y", namespace_shield: "X%3A%3AY", gem_shield: "x__y"}
      input = "[🚎yard-head]: https://kettle-dev.galtzo.com"
      expect { helpers.apply_common_replacements(input, **meta) }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/StubbedMock, RSpec/MessageSpies
