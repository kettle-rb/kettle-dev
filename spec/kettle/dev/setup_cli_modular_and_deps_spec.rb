# frozen_string_literal: true

# rubocop:disable ThreadSafety/DirChdir

RSpec.describe Kettle::Dev::SetupCLI do
  include_context "with stubbed env"

  before do
    require "kettle/dev"
  end

  describe "#ensure_modular_gemfiles!" do
    it "calls ModularGemfiles.sync! and rescues metadata errors (min_ruby=nil)" do
      cli = described_class.allocate
      helpers = class_double(Kettle::Dev::TemplateHelpers)
      allow(helpers).to receive(:project_root).and_return("/tmp/project")
      allow(helpers).to receive(:gem_checkout_root).and_return("/tmp/checkout")
      allow(helpers).to receive(:gemspec_metadata).and_raise(StandardError)
      stub_const("Kettle::Dev::TemplateHelpers", helpers)

      called = false
      expect(Kettle::Dev::ModularGemfiles).to receive(:sync!) do |args|
        called = true
        expect(args[:helpers]).to eq(helpers)
        expect(args[:project_root]).to eq("/tmp/project")
        expect(args[:gem_checkout_root]).to eq("/tmp/checkout")
        expect(args[:min_ruby]).to be_nil
      end

      cli.send(:ensure_modular_gemfiles!)
      expect(called).to be true
    end
  end

  describe "#ensure_dev_deps! additional branches" do
    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    def setup_cli_for_deps(example_path)
      cli = described_class.allocate
      cli.instance_variable_set(:@argv, [])
      cli.instance_variable_set(:@passthrough, [])
      cli.send(:parse!)
      allow(cli).to receive(:installed_path).and_wrap_original do |orig, rel|
        if rel == "kettle-dev.gemspec.example"
          example_path
        else
          orig.call(rel)
        end
      end
      cli
    end

    it "appends wanted lines when target gemspec lacks closing end (no rindex match)" do
      # Create an empty gemspec to force the append code path
      File.write("target.gemspec", "")
      example_path = File.expand_path("../../../kettle-dev.gemspec.example", __dir__)
      cli = setup_cli_for_deps(example_path)
      cli.instance_variable_set(:@gemspec_path, File.join(Dir.pwd, "target.gemspec"))

      # Act
      cli.send(:ensure_dev_deps!)

      content = File.read("target.gemspec")
      # Expect at least one development dependency line to be present (from example)
      expect(content).to match(/add_development_dependency\(\s*"rake"/)
    end

    it "prints up-to-date message when no changes are needed", :check_output do
      # Make the target match the example exactly (after placeholder substitution)
      example_path = File.expand_path("../../../kettle-dev.gemspec.example", __dir__)
      text = File.read(example_path).gsub("{KETTLE|DEV|GEM}", "kettle-dev")
      File.write("target.gemspec", text)

      cli = setup_cli_for_deps(example_path)
      cli.instance_variable_set(:@gemspec_path, File.join(Dir.pwd, "target.gemspec"))

      expect { cli.send(:ensure_dev_deps!) }.to output(/Development dependencies already up to date\./).to_stdout
      expect(File.read("target.gemspec")).to eq(text)
    end
  end

  describe "#commit_bootstrap_changes! fallbacks" do
    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    it "uses Open3 fallback when GitAdapter raises (rescue branch)", :check_output do
      %x(git init -q)
      # Simulate clean working tree via Open3 output empty
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_raise(StandardError)
      allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["", instance_double(Process::Status)])
      cli = described_class.allocate
      expect { cli.send(:commit_bootstrap_changes!) }.to output(/No changes to commit/).to_stdout
    end

    it "uses Open3 path when GitAdapter constant is removed (else branch)", :check_output do
      %x(git init -q)
      original = Kettle::Dev.const_get(:GitAdapter)
      Kettle::Dev.send(:remove_const, :GitAdapter)
      begin
        allow(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["", instance_double(Process::Status)])
        cli = described_class.allocate
        expect { cli.send(:commit_bootstrap_changes!) }.to output(/No changes to commit/).to_stdout
      ensure
        Kettle::Dev.const_set(:GitAdapter, original)
      end
    end
  end
end
# rubocop:enable ThreadSafety/DirChdir
