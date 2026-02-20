# frozen_string_literal: true

RSpec.describe "ModularGemfiles Integration" do
  before do
    require "kettle/dev"
  end

  it "correctly merges the real style.gemfile.example with a destination file" do
    helpers = Kettle::Dev::TemplateHelpers
    Dir.mktmpdir do |proj|
      Dir.mktmpdir do |gemroot|
        # Create source directory and copy the actual example file
        src_dir = File.join(gemroot, Kettle::Dev::ModularGemfiles::MODULAR_GEMFILE_DIR)
        FileUtils.mkdir_p(src_dir)

        # Copy the actual style.gemfile.example from the gem
        actual_example = File.join(__dir__, "../../gemfiles/modular/style.gemfile.example")
        FileUtils.cp(actual_example, File.join(src_dir, "style.gemfile.example"))

        # Create empty subdirectories required by sync!
        %w[erb mutex_m stringio x_std_libs].each do |dir|
          FileUtils.mkdir_p(File.join(src_dir, dir))
        end

        # Create a destination directory with a pre-existing style.gemfile
        # This simulates the scenario described in the issue
        dest_dir = File.join(proj, Kettle::Dev::ModularGemfiles::MODULAR_GEMFILE_DIR)
        FileUtils.mkdir_p(dest_dir)

        dest_content = <<~RUBY
          gem "reek", "~> 6.4"
          gem "rubocop", "~> 1.73", ">= 1.73.2"
          gem "standard", "~> 1.47"
        RUBY
        File.write(File.join(dest_dir, "style.gemfile"), dest_content)

        # Stub helpers methods
        allow(helpers).to receive_messages(
          project_root: proj,
          gem_checkout_root: gemroot,
          ask: true,
        )

        # Run sync with Ruby 2.7 to get specific version constraints
        Kettle::Dev::ModularGemfiles.sync!(
          helpers: helpers,
          project_root: proj,
          gem_checkout_root: gemroot,
          min_ruby: Gem::Version.new("2.7"),
        )

        # Read the result
        result = File.read(File.join(dest_dir, "style.gemfile"))

        # Verify the if/else structure is preserved
        expect(result).to include('if ENV.fetch("RUBOCOP_LTS_LOCAL"')
        expect(result).to include("else")
        expect(result).to match(/end\s*$/)

        # Verify comments are preserved
        expect(result).to include("# ruby >= 3.1.0")

        # Verify proper indentation inside the if block
        expect(result).to match(/^\s+gem "rubocop-lts", path:/)
        expect(result).to match(/^\s+gem "rubocop-lts-rspec", path:/)
        expect(result).to match(/^\s+gem "standard-rubocop-lts", path:/)

        # Verify tokens were replaced for Ruby 2.7
        expect(result).to include('"rubocop-lts", "~> 18.0"')
        expect(result).to include('"rubocop-ruby2_7"')
        expect(result).not_to include("{RUBOCOP|LTS|CONSTRAINT}")
        expect(result).not_to include("{RUBOCOP|RUBY|GEM}")

        # Verify new gems from template were added
        expect(result).to include("rubocop-packaging")
        expect(result).to include("rubocop-on-rbs")

        # Verify existing gems from destination were preserved
        expect(result).to include("reek")
        expect(result).to include("standard")

        # Most importantly: verify there are NO malformed lines without proper Ruby structure
        # The bug would have created lines like:
        #   gem "rubocop-packaging", "~> 0.6", ">= 0.6.0"
        #   gem "rubocop-on-rbs", "~> 1.8"                    # ruby >= 3.1.0
        #   gem "benchmark", "~> 0.4", ">= 0.4.1" # Removed from Std Lib in Ruby 3.5
        #     gem "rubocop-lts", path: "#{home}/src/rubocop-lts/rubocop-lts"
        # (note the incorrect indentation and lack of if statement)

        # Verify the structure is valid Ruby by parsing it
        expect { Prism.parse(result) }.not_to raise_error
        parse_result = Prism.parse(result)
        expect(parse_result.success?).to be true
      end
    end
  end
end
