# frozen_string_literal: true

RSpec.describe Kettle::Dev::ModularGemfiles do
  it "exposes sync! and performs copy calls via helpers" do
    helpers = Kettle::Dev::TemplateHelpers
    Dir.mktmpdir do |proj|
      Dir.mktmpdir do |gemroot|
        # Create a minimal source tree for modular files
        src_dir = File.join(gemroot, described_class::MODULAR_GEMFILE_DIR)
        FileUtils.mkdir_p(src_dir)
        %w[coverage debug documentation injected optional runtime_heads templating x_std_libs].each do |base|
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

  it "preserves if statements and comments when merging style.gemfile" do
    helpers = Kettle::Dev::TemplateHelpers
    Dir.mktmpdir do |proj|
      Dir.mktmpdir do |gemroot|
        # Create source and destination directories
        src_dir = File.join(gemroot, described_class::MODULAR_GEMFILE_DIR)
        dest_dir = File.join(proj, described_class::MODULAR_GEMFILE_DIR)
        FileUtils.mkdir_p(src_dir)
        FileUtils.mkdir_p(dest_dir)

        # Create template source with if statement and tokens
        src_content = <<~RUBY
          # frozen_string_literal: true

          gem "reek", "~> 6.5"
          gem "rubocop-packaging", "~> 0.6", ">= 0.6.0"
          gem "standard", ">= 1.50"
          gem "rubocop-on-rbs", "~> 1.8"                    # ruby >= 3.1.0

          # Std Lib extractions
          gem "benchmark", "~> 0.4", ">= 0.4.1" # Removed from Std Lib in Ruby 3.5

          if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
            home = ENV["HOME"] || Dir.home
            gem "rubocop-lts", path: "\#{home}/src/rubocop-lts/rubocop-lts"
            gem "rubocop-lts-rspec", path: "\#{home}/src/rubocop-lts/rubocop-lts-rspec"
            gem "{RUBOCOP|RUBY|GEM}", path: "\#{home}/src/rubocop-lts/{RUBOCOP|RUBY|GEM}"
            gem "standard-rubocop-lts", path: "\#{home}/src/rubocop-lts/standard-rubocop-lts"
          else
            gem "rubocop-lts", "{RUBOCOP|LTS|CONSTRAINT}"
            gem "{RUBOCOP|RUBY|GEM}"
            gem "rubocop-rspec", "~> 3.6"
          end
        RUBY
        File.write(File.join(src_dir, "style.gemfile"), src_content)

        # Create pre-existing destination with different gems
        dest_content = <<~RUBY
          # frozen_string_literal: true

          gem "reek", "~> 6.4"
          gem "rubocop", "~> 1.73", ">= 1.73.2"
          gem "standard", "~> 1.47"
        RUBY
        File.write(File.join(dest_dir, "style.gemfile"), dest_content)

        # Create empty subdirectories
        %w[erb mutex_m stringio x_std_libs].each do |dir|
          FileUtils.mkdir_p(File.join(src_dir, dir))
        end

        # Stub helpers methods
        allow(helpers).to receive_messages(
          project_root: proj,
          gem_checkout_root: gemroot,
          ask: true,
        )

        # Run sync
        described_class.sync!(
          helpers: helpers,
          project_root: proj,
          gem_checkout_root: gemroot,
          min_ruby: Gem::Version.new("2.3"),
        )

        # Read the result
        result = File.read(File.join(dest_dir, "style.gemfile"))

        # Verify the if statement is preserved
        expect(result).to include('if ENV.fetch("RUBOCOP_LTS_LOCAL"')
        expect(result).to include("else")
        expect(result).to include("end")

        # Verify comments are preserved
        expect(result).to include("# ruby >= 3.1.0")
        expect(result).to include("# Std Lib extractions")
        expect(result).to include("# Removed from Std Lib in Ruby 3.5")

        # Verify tokens were replaced for Ruby 2.3
        expect(result).to include('gem "rubocop-lts", "~> 10.0"')
        expect(result).to include('gem "rubocop-ruby2_3"')
        expect(result).not_to include("{RUBOCOP|LTS|CONSTRAINT}")
        expect(result).not_to include("{RUBOCOP|RUBY|GEM}")

        # Verify new gems from template were added
        expect(result).to include("rubocop-packaging")
        expect(result).to include("rubocop-on-rbs")
        expect(result).to include("benchmark")

        # Verify existing gems from destination were preserved
        expect(result).to include("reek")
        expect(result).to include("standard")
      end
    end
  end
end
