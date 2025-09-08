# frozen_string_literal: true

RSpec.describe Kettle::Dev::SetupCLI do
  include_context "with stubbed env"

  before do
    require "kettle/dev"
  end

  def write(file, content)
    File.write(file, content)
  end

  def read(file)
    File.read(file)
  end

  it "updates existing add_development_dependency lines that omit parentheses, without creating duplicates" do
    Dir.mktmpdir do |dir|
      # rubocop:disable ThreadSafety/DirChdir
      Dir.chdir(dir) do
        # rubocop:enable ThreadSafety/DirChdir
        # minimal git repo to satisfy prechecks!
        %x(git init -q)
        # clean working tree
        %x(git add -A && git commit --allow-empty -m initial -q)

        # Create a Gemfile to satisfy prechecks
        write("Gemfile", "source 'https://rubygems.org'\n")

        # Create a target gemspec with non-parenthesized dev deps (from the user's example)
        gemspec = <<~RUBY
          Gem::Specification.new do |spec|
            spec.name = 'example'
            spec.version = '0.0.1'

            spec.add_development_dependency 'addressable', '>= 2'
            spec.add_development_dependency 'rake', '>= 12'
            spec.add_development_dependency 'rexml', '>= 3'
            spec.add_development_dependency 'rspec', '>= 3'
            spec.add_development_dependency 'rspec-block_is_expected'
            spec.add_development_dependency 'rspec-pending_for'
            spec.add_development_dependency 'rspec-stubbed_env'
            spec.add_development_dependency 'rubocop-lts', ['>= 2.0.3', '~>2.0']
            spec.add_development_dependency 'silent_stream'
          end
        RUBY
        write("example.gemspec", gemspec)

        # Stub installed_path to point to the example shipped with repo
        example_path = File.expand_path("../../../kettle-dev.gemspec.example", __dir__)

        cli = described_class.allocate
        cli.instance_variable_set(:@argv, [])
        cli.instance_variable_set(:@passthrough, [])
        cli.send(:parse!) # init options

        # stub prechecks! to set gemspec/Gemfile without enforcing cleanliness again
        cli.instance_variable_set(:@gemspec_path, File.join(dir, "example.gemspec"))

        allow(cli).to receive(:installed_path).and_wrap_original do |orig, rel|
          # Only intercept the example gemspec lookup
          if rel == "kettle-dev.gemspec.example"
            example_path
          else
            orig.call(rel)
          end
        end

        # We also need to bypass git clean check inside prechecks!
        allow(cli).to receive(:prechecks!).and_return(nil)

        # Run just the dependency sync
        cli.send(:ensure_dev_deps!)

        result = read("example.gemspec")

        # Ensure we did not introduce duplicates for gems like rake and rspec-pending_for
        rake_lines = result.lines.grep(/add_development_dependency\s*\(?\s*["']rake["']/)
        pending_for_lines = result.lines.grep(/add_development_dependency\s*\(?\s*["']rspec-pending_for["']/)
        expect(rake_lines.size).to eq(1)
        expect(pending_for_lines.size).to eq(1)

        # Ensure the lines were updated to match the constraints from the example file (i.e., include ~> 13.0 etc.)
        expect(result).to match(/add_development_dependency\(\s*"rake"\s*,\s*"~> 13.0"\s*\)/)
        expect(result).to match(/add_development_dependency\(\s*"rspec-pending_for"\s*,\s*"~> 0.0"\s*,\s*">= 0.0.17"\s*\)/)
      end
    end
  end
end
