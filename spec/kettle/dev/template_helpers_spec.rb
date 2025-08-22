# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/StubbedMock, RSpec/MessageSpies
require "kettle/dev/template_helpers"

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
      allow($stdin).to receive(:gets).and_return(str)
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
    it "does nothing when not inside a git repo" do
      allow(helpers).to receive(:system).and_return(false)
      expect { helpers.ensure_clean_git!(root: "/tmp/project", task_label: "kettle:dev:install") }.not_to raise_error
    end

    it "does nothing when inside repo and status is clean" do
      allow(helpers).to receive(:system).and_return(true)
      allow(IO).to receive(:popen).and_return("")
      expect { helpers.ensure_clean_git!(root: "/tmp/project", task_label: "kettle:dev:template") }.not_to raise_error
    end

    it "aborts with helpful message when dirty" do
      allow(helpers).to receive(:system).and_return(true)
      dirty = " M lib/file.rb\n?? new.txt\n"
      allow(IO).to receive(:popen).and_return(dirty)
      allow(Kernel).to receive(:abort).and_return(nil)
      helpers.ensure_clean_git!(root: "/tmp/project", task_label: "kettle:dev:template")
      expect(Kernel).to have_received(:abort).with("Aborting: git working tree is not clean.")
    end
  end

  describe "::gemspec_metadata" do
    it "parses gemspec and derives strings, falling back to git origin when needed" do
      Dir.mktmpdir do |dir|
        gemspec_path = File.join(dir, "example.gemspec")
        File.write(gemspec_path, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "my-gem_name"
            spec.minimum_ruby_version = ">= 3.2"
            # no homepage specified here to trigger fallback
          end
        G
        # Stub git origin query
        origin = "https://github.com/acme/my-gem_name.git\n"
        allow(IO).to receive(:popen).with(array_including("git", "-C", dir, "remote", "get-url", "origin"), any_args).and_return(origin)

        meta = helpers.gemspec_metadata(dir)
        expect(meta[:gemspec_path]).to eq(gemspec_path)
        expect(meta[:gem_name]).to eq("my-gem_name")
        expect(meta[:min_ruby]).to eq("3.2")
        expect(meta[:gh_org]).to eq("acme")
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
        expect(meta[:gh_org]).to eq("org")
        expect(meta[:gh_repo]).to eq("widget")
        expect(meta[:min_ruby]).to eq("2.7.6")
        expect(meta[:entrypoint_require]).to eq("widget")
        expect(meta[:namespace]).to eq("Widget")
        expect(meta[:gem_shield]).to eq("widget")
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/ExampleLength, RSpec/StubbedMock, RSpec/MessageSpies
