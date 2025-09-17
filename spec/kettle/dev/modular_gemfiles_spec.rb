# frozen_string_literal: true

RSpec.describe Kettle::Dev::ModularGemfiles do
  before do
    require "kettle/dev"
  end

  it "exposes sync! and performs copy calls via helpers" do
    helpers = Kettle::Dev::TemplateHelpers
    Dir.mktmpdir do |proj|
      Dir.mktmpdir do |gemroot|
        # Create a minimal source tree for modular files
        src_dir = File.join(gemroot, described_class::MODULAR_GEMFILE_DIR)
        FileUtils.mkdir_p(src_dir)
        %w[coverage debug documentation injected optional runtime_heads x_std_libs].each do |base|
          File.write(File.join(src_dir, "#{base}.gemfile"), "# #{base}\n")
        end
        File.write(File.join(src_dir, "style.gemfile"), "gem 'rubocop-lts', '{RUBOCOP|LTS|CONSTRAINT}'\n# {RUBOCOP|RUBY|GEM}\n")
        %w[erb mutex_m stringio x_std_libs].each do |dir|
          FileUtils.mkdir_p(File.join(src_dir, dir))
          File.write(File.join(src_dir, dir, "placeholder"), "ok\n")
        end

        # Stub helpers.project_root and gem_checkout_root to these temp dirs
        allow(helpers).to receive_messages(
          project_root: proj,
          gem_checkout_root: gemroot,
          ask: true,
        )

        expect {
          described_class.sync!(helpers: helpers, project_root: proj, gem_checkout_root: gemroot, min_ruby: Gem::Version.new("3.2"))
        }.not_to raise_error

        # Verify a couple of outputs exist
        expect(File).to exist(File.join(proj, described_class::MODULAR_GEMFILE_DIR, "coverage.gemfile"))
        expect(File).to exist(File.join(proj, described_class::MODULAR_GEMFILE_DIR, "style.gemfile"))
        expect(File.read(File.join(proj, described_class::MODULAR_GEMFILE_DIR, "style.gemfile"))).to include("rubocop-lts")
        expect(File).to exist(File.join(proj, described_class::MODULAR_GEMFILE_DIR, "erb", "placeholder"))
      end
    end
  end
end
