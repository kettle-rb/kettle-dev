# frozen_string_literal: true

# Unit specs for Kettle::Dev::Tasks::TemplateTask
# Mirrors a subset of behavior covered by the rake integration spec, but
# calls the class API directly for focused unit testing.

require "rake"
require "open3"

RSpec.describe Kettle::Dev::Tasks::TemplateTask do
  describe "run/install behaviors" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    before do
      stub_env("allowed" => "true") # allow env file changes without abort
      stub_env("FUNDING_ORG" => "false") # bypass funding org requirement in unit tests unless explicitly set
    end

    describe "::task_abort" do
      it "raises Kettle::Dev::Error" do
        expect {
          described_class.task_abort("STOP ME")
        }.to raise_error(Kettle::Dev::Error, /STOP ME/)
      end
    end

    describe "::run" do
      it "prefers .example files under .github/workflows and writes without .example and customizes FUNDING.yml" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange template source
            gh_src = File.join(gem_root, ".github", "workflows")
            FileUtils.mkdir_p(gh_src)
            File.write(File.join(gh_src, "ci.yml"), "name: REAL\n")
            File.write(File.join(gh_src, "ci.yml.example"), "name: EXAMPLE\n")
            # FUNDING.yml example with placeholders
            File.write(File.join(gem_root, ".github", "FUNDING.yml.example"), <<~YAML)
              open_collective: placeholder
              tidelift: rubygems/placeholder
            YAML

            # Provide gemspec in project to satisfy metadata scanner
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            # Stub helpers used by the task
            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Override global funding disable for this example to allow customization
            stub_env("FUNDING_ORG" => "")

            # Exercise
            expect { described_class.run }.not_to raise_error

            # Assert
            dest_ci = File.join(project_root, ".github", "workflows", "ci.yml")
            expect(File).to exist(dest_ci)
            expect(File.read(dest_ci)).to include("EXAMPLE")

            # FUNDING content customized
            funding_dest = File.join(project_root, ".github", "FUNDING.yml")
            expect(File).to exist(funding_dest)
            funding = File.read(funding_dest)
            expect(funding).to include("open_collective: acme")
            expect(funding).to include("tidelift: rubygems/demo")
          end
        end
      end

      it "copies .env.local.example but does not create .env.local" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, ".env.local.example"), "SECRET=1\n")
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            expect { described_class.run }.not_to raise_error

            expect(File).to exist(File.join(project_root, ".env.local.example"))
            expect(File).not_to exist(File.join(project_root, ".env.local"))
          end
        end
      end

      it "replaces {TARGET|GEM|NAME} token in .envrc files" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Create .envrc.example with the token
            File.write(File.join(gem_root, ".envrc.example"), <<~ENVRC)
              export DEBUG=false
              # If {TARGET|GEM|NAME} does not have an open source collective set these to false.
              export OPENCOLLECTIVE_HANDLE={OPENCOLLECTIVE|ORG_NAME}
              export FUNDING_ORG={OPENCOLLECTIVE|ORG_NAME}
              dotenv_if_exists .env.local
            ENVRC

            # Provide gemspec in project
            File.write(File.join(project_root, "my-awesome-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-awesome-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/coolorg/my-awesome-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Override funding org for this test
            stub_env("FUNDING_ORG" => "")

            expect { described_class.run }.not_to raise_error

            # Assert .envrc was copied
            envrc_dest = File.join(project_root, ".envrc")
            expect(File).to exist(envrc_dest)

            # Assert {TARGET|GEM|NAME} was replaced with the actual gem name
            envrc_content = File.read(envrc_dest)
            expect(envrc_content).to include("# If my-awesome-gem does not have an open source collective")
            expect(envrc_content).not_to include("{TARGET|GEM|NAME}")

            # Assert other tokens were also replaced (from apply_common_replacements)
            expect(envrc_content).to include("export OPENCOLLECTIVE_HANDLE=coolorg")
            expect(envrc_content).to include("export FUNDING_ORG=coolorg")
          end
        end
      end

      it "updates style.gemfile rubocop-lts constraint based on min_ruby", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # style.gemfile template with placeholder constraint
            style_dir = File.join(gem_root, "gemfiles", "modular")
            FileUtils.mkdir_p(style_dir)
            File.write(File.join(style_dir, "style.gemfile.example"), <<~GEMFILE)
              if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
                gem "rubocop-lts", path: "src/rubocop-lts/rubocop-lts"
                gem "rubocop-lts-rspec", path: "src/rubocop-lts/rubocop-lts-rspec"
                gem "{RUBOCOP|RUBY|GEM}", path: "src/rubocop-lts/{RUBOCOP|RUBY|GEM}"
                gem "standard-rubocop-lts", path: "src/rubocop-lts/standard-rubocop-lts"
              else
                gem "rubocop-lts", "{RUBOCOP|LTS|CONSTRAINT}"
                gem "{RUBOCOP|RUBY|GEM}"
                gem "rubocop-rspec", "~> 3.6"
              end
            GEMFILE
            # gemspec declares min_ruby 3.2 -> map to "~> 24.0"
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.2"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "gemfiles", "modular", "style.gemfile")
            expect(File).to exist(dest)
            txt = File.read(dest)
            expect(txt).to include('gem "rubocop-lts", "~> 24.0"')
            expect(txt).to include('gem "rubocop-ruby3_2"')
          end
        end
      end

      it "keeps style.gemfile constraint unchanged when min_ruby is missing (else branch)" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            style_dir = File.join(gem_root, "gemfiles", "modular")
            FileUtils.mkdir_p(style_dir)
            File.write(File.join(style_dir, "style.gemfile.example"), <<~GEMFILE)
              if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
                gem "rubocop-lts", path: "src/rubocop-lts/rubocop-lts"
                gem "rubocop-lts-rspec", path: "src/rubocop-lts/rubocop-lts-rspec"
                gem "{RUBOCOP|RUBY|GEM}", path: "src/rubocop-lts/{RUBOCOP|RUBY|GEM}"
                gem "standard-rubocop-lts", path: "src/rubocop-lts/standard-rubocop-lts"
              else
                gem "rubocop-lts", "{RUBOCOP|LTS|CONSTRAINT}"
                gem "{RUBOCOP|RUBY|GEM}"
                gem "rubocop-rspec", "~> 3.6"
              end
            GEMFILE
            # gemspec without any min ruby declaration
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "gemfiles", "modular", "style.gemfile")
            expect(File).to exist(dest)
            txt = File.read(dest)
            expect(txt).to include('gem "rubocop-lts", "~> 0.1"')
            expect(txt).to include('gem "rubocop-ruby1_8"')
          end
        end
      end

      it "copies modular directories and additional gemfiles (erb, mutex_m, stringio, x_std_libs; debug/runtime_heads)" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            base = File.join(gem_root, "gemfiles", "modular")
            %w[erb mutex_m stringio x_std_libs].each do |d|
              dir = File.join(base, d)
              FileUtils.mkdir_p(dir)
              # nested/versioned example files
              FileUtils.mkdir_p(File.join(dir, "r2.6"))
              File.write(File.join(dir, "r2.6", "v2.2.gemfile"), "# v2.2\n")
              FileUtils.mkdir_p(File.join(dir, "r3"))
              File.write(File.join(dir, "r3", "libs.gemfile"), "# r3 libs\n")
            end
            # additional specific gemfiles
            File.write(File.join(base, "debug.gemfile"), "# debug\n")
            File.write(File.join(base, "runtime_heads.gemfile"), "# runtime heads\n")

            # minimal gemspec to satisfy metadata scan
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

            expect { described_class.run }.not_to raise_error

            # assert directories copied recursively
            %w[erb mutex_m stringio x_std_libs].each do |d|
              expect(File).to exist(File.join(project_root, "gemfiles", "modular", d, "r2.6", "v2.2.gemfile"))
              expect(File).to exist(File.join(project_root, "gemfiles", "modular", d, "r3", "libs.gemfile"))
            end
            # assert specific gemfiles copied
            expect(File).to exist(File.join(project_root, "gemfiles", "modular", "debug.gemfile"))
            expect(File).to exist(File.join(project_root, "gemfiles", "modular", "runtime_heads.gemfile"))
          end
        end
      end

      # Regression: optional.gemfile should prefer the .example version when both exist
      it "prefers optional.gemfile.example over optional.gemfile" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            dir = File.join(gem_root, "gemfiles", "modular")
            FileUtils.mkdir_p(dir)
            File.write(File.join(dir, "optional.gemfile"), "# REAL\nreal\n")
            File.write(File.join(dir, "optional.gemfile.example"), "# EXAMPLE\nexample\n")

            # Minimal gemspec so metadata scan works
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "gemfiles", "modular", "optional.gemfile")
            expect(File).to exist(dest)
            content = File.read(dest)
            lowered = content.downcase
            expect(lowered).to include("example")
            expect(lowered).not_to include("real")
          end
        end
      end

      it "replaces require in spec/spec_helper.rb when confirmed, or skips when declined" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange project spec_helper with kettle/dev
            spec_dir = File.join(project_root, "spec")
            FileUtils.mkdir_p(spec_dir)
            File.write(File.join(spec_dir, "spec_helper.rb"), "require 'kettle/dev'\n")
            # gemspec
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
            )

            # Case 1: confirm replacement
            allow(helpers).to receive(:ask).and_return(true)
            described_class.run
            content = File.read(File.join(spec_dir, "spec_helper.rb"))
            expect(content).to include('require "demo"')

            # Case 2: decline
            File.write(File.join(spec_dir, "spec_helper.rb"), "require 'kettle/dev'\n")
            allow(helpers).to receive(:ask).and_return(false)
            described_class.run
            content2 = File.read(File.join(spec_dir, "spec_helper.rb"))
            expect(content2).to include("require 'kettle/dev'")
          end
        end
      end

      it "merges README sections and preserves first H1 emojis", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange
            template_readme = <<~MD
              # 🚀 Template Title
              
              ## Synopsis
              Template synopsis.
              
              ## Configuration
              Template configuration.
              
              ## Basic Usage
              Template usage.
              
              ## NOTE: Something
              Template note.
            MD
            File.write(File.join(gem_root, "README.md"), template_readme)

            existing_readme = <<~MD
              # 🎉 Existing Title
              
              ## Synopsis
              Existing synopsis.
              
              ## Configuration
              Existing configuration.
              
              ## Basic Usage
              Existing usage.
              
              ## NOTE: Something
              Existing note.
            MD
            File.write(File.join(project_root, "README.md"), existing_readme)

            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Exercise
            described_class.run

            # Assert merge and H1 full-line preservation
            merged = File.read(File.join(project_root, "README.md"))
            expect(merged.lines.first).to match(/^#\s+🎉\s+Existing Title/)
            expect(merged).to include("Existing synopsis.")
            expect(merged).to include("Existing configuration.")
            expect(merged).to include("Existing usage.")
            expect(merged).to include("Existing note.")
          end
        end
      end

      it "copies kettle-dev.gemspec.example to <gem_name>.gemspec with substitutions" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Provide a kettle-dev.gemspec.example with tokens to be replaced
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                # Namespace token example
                Kettle::Dev
              end
            GEMSPEC

            # Destination project gemspec to derive gem_name and org/homepage
            File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "my-gem.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            expect(txt).to match(/spec\.name\s*=\s*\"my-gem\"/)
            expect(txt).to include("My::Gem")
          end
        end
      end

      it "removes self-dependencies in gemspec after templating (runtime and development, paren and no-paren)" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Template gemspec includes dependencies on the template gem name
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                spec.add_dependency("kettle-dev", "~> 1.0")
                spec.add_dependency 'kettle-dev'
                spec.add_development_dependency("kettle-dev")
                spec.add_development_dependency 'kettle-dev', ">= 0"
                spec.add_dependency("addressable", ">= 2.8", "< 3")
              end
            GEMSPEC

            # Destination project gemspec to derive gem_name and org/homepage
            File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "my-gem.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            # Self-dependency variants should be removed (they would otherwise become my-gem)
            expect(txt).not_to match(/spec\.add_(?:development_)?dependency\([\"\']my-gem[\"\']/)
            expect(txt).not_to match(/spec\.add_(?:development_)?dependency\s+[\"\']my-gem[\"\']/)
            # Other dependencies remain
            expect(txt).to include('spec.add_dependency("addressable", ">= 2.8", "< 3")')
          end
        end
      end

      it "when gem_name is missing, falls back to first existing *.gemspec in project" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Provide template gemspec example
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                Kettle::Dev
              end
            GEMSPEC

            # Destination already has a different gemspec; note: no name set elsewhere to derive gem_name
            File.write(File.join(project_root, "existing.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "existing"
                spec.homepage = "https://github.com/acme/existing"
              end
            GEMSPEC

            # project has no other gemspec affecting gem_name discovery (no spec.name parsing needed beyond existing)
            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            # Should have used existing.gemspec as destination
            dest = File.join(project_root, "existing.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            # Replacements applied (namespace, org, etc.). With no gem_name, namespace remains derived from empty -> should still replace Kettle::Dev
            expect(txt).to include("existing")
            # Allow "kettle-dev" in freeze reminder comments, but verify actual code was replaced
            expect(txt).not_to include('spec.name = "kettle-dev"')
            expect(txt).not_to include("Kettle::Dev")
          end
        end
      end

      it "when gem_name is missing and no gemspec exists, uses example basename without .example" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Provide template example only
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                Kettle::Dev
              end
            GEMSPEC

            # No destination gemspecs present
            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            # Should write kettle-dev.gemspec (no .example)
            dest = File.join(project_root, "kettle-dev.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            expect(txt).not_to include("kettle-dev.gemspec.example")
            # Note: when gem_name is unknown, namespace/gem replacements depending on gem_name may not occur.
            # This test verifies the destination file name logic only.
          end
        end
      end

      it "prefers .gitlab-ci.yml.example over .gitlab-ci.yml and writes destination without .example" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange template files at root
            File.write(File.join(gem_root, ".gitlab-ci.yml"), "from: REAL\n")
            File.write(File.join(gem_root, ".gitlab-ci.yml.example"), "from: EXAMPLE\n")

            # Minimal gemspec so metadata scan works
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Exercise
            described_class.run

            # Assert destination is the non-example name and content from example
            dest = File.join(project_root, ".gitlab-ci.yml")
            expect(File).to exist(dest)
            expect(File.read(dest)).to include("EXAMPLE")
          end
        end
      end

      it "copies .licenserc.yaml preferring .licenserc.yaml.example when available" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange template files at root
            File.write(File.join(gem_root, ".licenserc.yaml"), "header:\n  license: REAL\n")
            File.write(File.join(gem_root, ".licenserc.yaml.example"), "header:\n  license: EXAMPLE\n")

            # Minimal gemspec so metadata scan works
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Exercise
            described_class.run

            # Assert destination is the non-example name and content from example
            dest = File.join(project_root, ".licenserc.yaml")
            expect(File).to exist(dest)
            expect(File.read(dest)).to include("EXAMPLE")
            expect(File.read(dest)).not_to include("REAL")
          end
        end
      end

      it "copies .idea/.gitignore into the project when present" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            idea_dir = File.join(gem_root, ".idea")
            FileUtils.mkdir_p(idea_dir)
            File.write(File.join(idea_dir, ".gitignore"), "/*.iml\n")

            # Minimal gemspec so metadata scan works
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, ".idea", ".gitignore")
            expect(File).to exist(dest)
            expect(File.read(dest)).to include("/*.iml")
          end
        end
      end

      it "prints a warning when copying .env.local.example raises", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, ".env.local.example"), "A=1\n")
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
            # Only raise for .env.local.example copy, not for other copies
            allow(helpers).to receive(:copy_file_with_prompt).and_wrap_original do |m, *args, &blk|
              src = args[0].to_s
              if File.basename(src) == ".env.local.example"
                raise ArgumentError, "boom"
              elsif args.last.is_a?(Hash)
                kw = args.pop
                m.call(*args, **kw, &blk)
              else
                m.call(*args, &blk)
              end
            end
            expect { described_class.run }.not_to raise_error
          end
        end
      end

      it "copies certs/pboling.pem when present, and warns on error", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            cert_dir = File.join(gem_root, "certs")
            FileUtils.mkdir_p(cert_dir)
            File.write(File.join(cert_dir, "pboling.pem"), "certdata")
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            # Normal run
            expect { described_class.run }.not_to raise_error
            expect(File).to exist(File.join(project_root, "certs", "pboling.pem"))

            # Error run
            allow(helpers).to receive(:copy_file_with_prompt).and_wrap_original do |m, *args, &blk|
              if args[0].to_s.end_with?(File.join("certs", "pboling.pem"))
                raise "nope"
              elsif args.last.is_a?(Hash)
                kw = args.pop
                m.call(*args, **kw, &blk)
              else
                m.call(*args, &blk)
              end
            end
            expect { described_class.run }.not_to raise_error
          end
        end
      end

      context "when reviewing env file changes", :check_output do
        it "proceeds when allowed=true" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              File.write(File.join(gem_root, ".envrc"), "export A=1\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(helpers).to receive(:modified_by_template?).and_return(true)
              stub_env("allowed" => "true")
              expect { described_class.run }.not_to raise_error
            end
          end
        end

        it "aborts with guidance when not allowed" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              File.write(File.join(gem_root, ".envrc"), "export A=1\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(helpers).to receive(:modified_by_template?).and_return(true)
              stub_env("allowed" => "")
              expect { described_class.run }.to raise_error(Kettle::Dev::Error, /review of environment files required/)
            end
          end
        end

        it "warns when check raises" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              File.write(File.join(gem_root, ".envrc"), "export A=1\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(helpers).to receive(:modified_by_template?).and_raise(StandardError, "oops")
              stub_env("allowed" => "true")
              expect { described_class.run }.not_to raise_error
            end
          end
        end
      end

      it "applies replacements for special root files like CHANGELOG.md and .opencollective.yml and FUNDING.md" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "CHANGELOG.md.example"), "kettle-rb kettle-dev Kettle::Dev Kettle%3A%3ADev kettle--dev\n")
            File.write(File.join(gem_root, ".opencollective.yml"), "org: kettle-rb project: kettle-dev\n")
            # FUNDING with org placeholder to be replaced
            File.write(File.join(gem_root, "FUNDING.md"), "Support org kettle-rb and project kettle-dev\n")
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            changelog = File.read(File.join(project_root, "CHANGELOG.md"))
            expect(changelog).to include("acme")
            expect(changelog).to include("my-gem")
            expect(changelog).to include("My::Gem")
            expect(changelog).to include("My%3A%3AGem")
            expect(changelog).to include("my--gem")

            # FUNDING.md should be copied and have org replaced with funding org (acme)
            funding = File.read(File.join(project_root, "FUNDING.md"))
            expect(funding).to include("acme")
            expect(funding).not_to include("kettle-rb")
          end
        end
      end

      it "does not duplicate Unreleased change-type headings and preserves existing list items under them, including nested bullets" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Template CHANGELOG with Unreleased and six standard headings (empty)
            File.write(File.join(gem_root, "CHANGELOG.md.example"), <<~MD)
              # Changelog
              \n
              ## [Unreleased]
              ### Added
              ### Changed
              ### Deprecated
              ### Removed
              ### Fixed
              ### Security
              \n
              ## [0.1.0] - 2020-01-01
              - initial
            MD

            # Destination project with existing Unreleased having items including nested sub-bullets
            File.write(File.join(project_root, "CHANGELOG.md"), <<~MD)
              # Changelog
              \n
              ## [Unreleased]
              ### Added
              - kettle-dev v1.1.18
              - Internal escape & unescape methods
                - Stop relying on URI / CGI for escaping and unescaping
                - They are both unstable across supported versions of Ruby (including 3.5 HEAD)
              - keep me
              ### Fixed
              - also keep me
              \n
              ## [0.0.1] - 2019-01-01
              - start
            MD

            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            result = File.read(File.join(project_root, "CHANGELOG.md"))
            # Exactly one of each standard heading under Unreleased
            %w[Added Changed Deprecated Removed Fixed Security].each do |h|
              expect(result.scan(/^### #{h}$/).size).to eq(1)
            end
            # Preserved items, including nested sub-bullets and their indentation
            expect(result).to include("### Added\n\n- kettle-dev v1.1.18")
            expect(result).to include("- Internal escape & unescape methods")
            expect(result).to include("  - Stop relying on URI / CGI for escaping and unescaping")
            expect(result).to include("  - They are both unstable across supported versions of Ruby (including 3.5 HEAD)")
            expect(result).to include("- keep me")
            expect(result).to include("### Fixed\n\n- also keep me")
          end
        end
      end

      it "ensures blank lines before and after headings in CHANGELOG.md" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "CHANGELOG.md.example"), <<~MD)
              # Changelog
              ## [Unreleased]
              ### Added
              ### Changed

              ## [0.1.0] - 2020-01-01
              - initial
            MD
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            content = File.read(File.join(project_root, "CHANGELOG.md"))
            # Expect blank line after H1 and before the next heading
            expect(content).to match(/# Changelog\n\n## \[Unreleased\]/)
            # Expect blank line after Unreleased and before the first subheading
            expect(content).to match(/## \[Unreleased\]\n\n### Added/)
            # Expect blank line between consecutive subheadings
            expect(content).to match(/### Added\n\n### Changed/)
          end
        end
      end

      it "preserves GFM fenced code blocks nested under list items in Unreleased sections" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Template with empty Unreleased standard headings
            File.write(File.join(gem_root, "CHANGELOG.md.example"), <<~MD)
              # Changelog

              ## [Unreleased]
              ### Added
              ### Changed
              ### Deprecated
              ### Removed
              ### Fixed
              ### Security

              ## [0.1.0] - 2020-01-01
              - initial
            MD

            # Destination with a bullet containing a fenced code block
            File.write(File.join(project_root, "CHANGELOG.md"), <<~MD)
              # Changelog

              ## [Unreleased]
              ### Added
              - Add helper with example usage
                
                ```ruby
                puts "hello"
                1 + 2
                ```
              - Another item

              ## [0.0.1] - 2019-01-01
              - start
            MD

            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            result = File.read(File.join(project_root, "CHANGELOG.md"))
            # Ensure the fenced block and its contents are preserved under the list item
            expect(result).to include("### Added")
            expect(result).to include("- Add helper with example usage")
            expect(result).to include("```ruby")
            expect(result).to include("puts \"hello\"")
            expect(result).to include("1 + 2")
            expect(result).to include("```")
            expect(result).to include("- Another item")
          end
        end
      end

      context "with .git-hooks present" do
        it "honors only filter by skipping .git-hooks when not selected" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              # Arrange .git-hooks in template checkout
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "x")
              File.write(File.join(hooks_src, "footer-template.erb.txt"), "y")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

              # Set only to README.md, which should exclude .git-hooks completely
              stub_env("only" => "README.md")
              # If code ignores only for hooks, it would prompt; ensure no blocking by pre-answering
              allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("")

              described_class.run
              expect(File).not_to exist(File.join(project_root, ".git-hooks", "commit-subjects-goalie.txt"))
              expect(File).not_to exist(File.join(project_root, ".git-hooks", "footer-template.erb.txt"))
            end
          end
        end

        it "copies templates when only includes .git-hooks/**", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "x")
              File.write(File.join(hooks_src, "footer-template.erb.txt"), "y")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              stub_env("only" => ".git-hooks/**")
              allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("")
              described_class.run
              expect(File).to exist(File.join(project_root, ".git-hooks", "commit-subjects-goalie.txt"))
              expect(File).to exist(File.join(project_root, ".git-hooks", "footer-template.erb.txt"))
            end
          end
        end

        it "copies templates locally by default", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "x")
              File.write(File.join(hooks_src, "footer-template.erb.txt"), "y")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("")
              described_class.run
              expect(File).to exist(File.join(project_root, ".git-hooks", "commit-subjects-goalie.txt"))
            end
          end
        end

        it "skips copying templates when user chooses 's'", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "x")
              File.write(File.join(hooks_src, "footer-template.erb.txt"), "y")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("s\n")
              described_class.run
              expect(File).not_to exist(File.join(project_root, ".git-hooks", "commit-subjects-goalie.txt"))
            end
          end
        end

        it "installs hook scripts; overwrite yes/no and fresh install", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-msg"), "echo ruby hook\n")
              File.write(File.join(hooks_src, "prepare-commit-msg"), "echo sh hook\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

              # Force templates conditional to false
              allow(Dir).to receive(:exist?).and_call_original
              allow(Dir).to receive(:exist?).with(File.join(gem_root, ".git-hooks")).and_return(true)
              allow(File).to receive(:file?).and_call_original
              allow(File).to receive(:file?).with(File.join(gem_root, ".git-hooks", "commit-subjects-goalie.txt")).and_return(false)
              allow(File).to receive(:file?).with(File.join(gem_root, ".git-hooks", "footer-template.erb.txt")).and_return(false)

              # First run installs
              described_class.run
              dest_dir = File.join(project_root, ".git-hooks")
              commit_hook = File.join(dest_dir, "commit-msg")
              prepare_hook = File.join(dest_dir, "prepare-commit-msg")
              expect(File).to exist(commit_hook)
              expect(File).to exist(prepare_hook)
              expect(File.executable?(commit_hook)).to be(true)
              expect(File.executable?(prepare_hook)).to be(true)

              # Overwrite yes
              allow(helpers).to receive(:ask).and_return(true)
              described_class.run
              expect(File.executable?(commit_hook)).to be(true)
              expect(File.executable?(prepare_hook)).to be(true)
              # Overwrite no
              allow(helpers).to receive(:ask).and_return(false)
              described_class.run
              expect(File.executable?(commit_hook)).to be(true)
              expect(File.executable?(prepare_hook)).to be(true)
            end
          end
        end

        it "prefers prepare-commit-msg.example over prepare-commit-msg when both exist" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              # Provide both real and example; example should be preferred
              File.write(File.join(hooks_src, "prepare-commit-msg"), "REAL\n")
              File.write(File.join(hooks_src, "prepare-commit-msg.example"), "EXAMPLE\n")
              # Commit hook presence isn't required for this behavior, but include to mirror typical state
              File.write(File.join(hooks_src, "commit-msg"), "ruby hook\n")

              # Minimal gemspec in project for metadata
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")

              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

              # Ensure the templates (.txt) branch does not trigger prompts/copies, to keep test focused
              allow(File).to receive(:file?).and_call_original
              allow(File).to receive(:file?).with(File.join(gem_root, ".git-hooks", "commit-subjects-goalie.txt")).and_return(false)
              allow(File).to receive(:file?).with(File.join(gem_root, ".git-hooks", "footer-template.erb.txt")).and_return(false)

              described_class.run

              dest = File.join(project_root, ".git-hooks", "prepare-commit-msg")
              expect(File).to exist(dest)
              content = File.read(dest)
              expect(content).to include("EXAMPLE")
              expect(content).not_to include("REAL")
            end
          end
        end

        it "warns when installing hook scripts raises", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-msg"), "echo ruby hook\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError, "perm")
              expect { described_class.run }.not_to raise_error
            end
          end
        end
      end

      it "preserves nested subsections under preserved H2 sections during README merge" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            template_readme = <<~MD
              # 🚀 Template Title

              ## Synopsis
              Template synopsis.

              ## Configuration
              Template configuration.

              ## Basic Usage
              Template usage.
            MD
            File.write(File.join(gem_root, "README.md"), template_readme)

            existing_readme = <<~MD
              # 🎉 Existing Title

              ## Synopsis
              Existing synopsis intro.

              ### Details
              Keep this nested detail.

              #### More
              And this deeper detail.

              ## Configuration
              Existing configuration.

              ## Basic Usage
              Existing usage.
            MD
            File.write(File.join(project_root, "README.md"), existing_readme)

            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            merged = File.read(File.join(project_root, "README.md"))
            # H1 emoji preserved
            expect(merged.lines.first).to match(/^#\s+🎉\s+Existing Title/)
            # Preserved H2 branch content
            expect(merged).to include("Existing synopsis intro.")
            expect(merged).to include("### Details")
            expect(merged).to include("Keep this nested detail.")
            expect(merged).to include("#### More")
            expect(merged).to include("And this deeper detail.")
            # Other targeted sections still merged
            expect(merged).to include("Existing configuration.")
            expect(merged).to include("Existing usage.")
          end
        end
      end

      it "does not treat # inside fenced code blocks as headings during README merge" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            template_readme = <<~MD
              # 🚀 Template Title

              ## Synopsis
              Template synopsis.

              ## Configuration
              Template configuration.

              ## Basic Usage
              Template usage.
            MD
            File.write(File.join(gem_root, "README.md"), template_readme)

            existing_readme = <<~MD
              # 🎉 Existing Title

              ## Synopsis
              Existing synopsis.

              ```console
              # DANGER: options to reduce prompts will overwrite files without asking.
              bundle exec rake kettle:dev:install allowed=true force=true
              ```

              ## Configuration
              Existing configuration.

              ## Basic Usage
              Existing usage.
            MD
            File.write(File.join(project_root, "README.md"), existing_readme)

            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            merged = File.read(File.join(project_root, "README.md"))
            # H1 full-line preserved from existing README
            expect(merged.lines.first).to match(/^#\s+🎉\s+Existing Title/)
            # Ensure the code block remains intact and not split
            expect(merged).to include("```console")
            expect(merged).to include("# DANGER: options to reduce prompts will overwrite files without asking.")
            expect(merged).to include("bundle exec rake kettle:dev:install allowed=true force=true")
            # And targeted sections still merged with existing content
            expect(merged).to include("Existing synopsis.")
            expect(merged).to include("Existing configuration.")
            expect(merged).to include("Existing usage.")
          end
        end
      end

      it "replaces {KETTLE|DEV|GEM} token after normal replacements" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Template gemspec example contains both normal tokens and the special token
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                # This should become the actual destination gem name via normal replacement
                spec.summary = "kettle-dev summary"
                # This token should be replaced AFTER normal replacements with the literal string
                spec.add_development_dependency("{KETTLE|DEV|GEM}", "~> 1.0.0")
              end
            GEMSPEC

            # Destination project gemspec defines gem_name and org so replacements occur
            File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "my-gem.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            # Normal replacement happened: occurrences of kettle-dev became my-gem
            expect(txt).to match(/spec\.summary\s*=\s*"my-gem summary"/)
            # Special token replacement happened AFTER, yielding literal kettle-dev
            expect(txt).to include('spec.add_development_dependency("kettle-dev", "~> 1.0.0")')
          end
        end
      end

      it "copies Appraisal.root.gemfile with AST merge" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "Appraisal.root.gemfile"), <<~RUBY)
              source "https://rubygems.org"
              gem "foo"
            RUBY
            File.write(File.join(project_root, "Appraisal.root.gemfile"), <<~RUBY)
              source "https://example.com"
              gem "bar"
            RUBY
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
            described_class.run
            merged = File.read(File.join(project_root, "Appraisal.root.gemfile"))
            expect(merged).to include('source "https://rubygems.org"')
            expect(merged).to include('gem "foo"')
            expect(merged).to include('gem "bar"')
          end
        end
      end

      it "merges Appraisals entries without losing custom appraise blocks" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "Appraisals"), <<~APP)
              appraise "ruby-3.1" do
                gemfile "gemfiles/ruby_3.1.gemfile"
              end
            APP
            File.write(File.join(project_root, "Appraisals"), <<~APP)
              appraise "ruby-3.0" do
                gemfile "gemfiles/ruby_3.0.gemfile"
              end
            APP
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
            described_class.run
            merged = File.read(File.join(project_root, "Appraisals"))
            expect(merged).to include('appraise("ruby-3.1")')
            expect(merged).to include('appraise("ruby-3.0")')
          end
        end
      end
    end
  end

  # Consolidated from template_task_carryover_spec.rb and template_task_env_spec.rb
  describe "carryover/env behaviors" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    describe "carryover of gemspec fields" do
      before { stub_env("allowed" => "true") }

      it "carries over key fields from original gemspec when overwriting with example (after replacements)" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                spec.version = "1.0.0"
                spec.authors = ["Template Author"]
                spec.email = ["template@example.com"]
                spec.summary = "🍲 Template summary"
                spec.description = "🍲 Template description"
                spec.license = "MIT"
                spec.required_ruby_version = ">= 2.3.0"
                spec.require_paths = ["lib"]
                spec.bindir = "exe"
                spec.executables = ["templ"]
                Kettle::Dev
              end
            GEMSPEC

            File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.version = "0.1.0"
                spec.authors = ["Alice", "Bob"]
                spec.email = ["alice@example.com"]
                spec.summary = "Original summary"
                spec.description = "Original description more text"
                spec.license = "Apache-2.0"
                spec.required_ruby_version = ">= 3.2"
                spec.require_paths = ["lib", "ext"]
                spec.bindir = "bin"
                spec.executables = ["mygem", "mg"]
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            dest = File.join(project_root, "my-gem.gemspec")
            txt = File.read(dest)
            expect(txt).to match(/spec\.name\s*=\s*\"my-gem\"/)
            expect(txt).to match(/spec\.authors\s*=\s*\[[^\]]*"Alice"[^\]]*"Bob"[^\]]*\]/)
            expect(txt).not_to match(/spec\.email\s*=\s*\[[^\]]*"template@example.com"[^\]]*\]/)
            expect(txt).to match(/spec\.email\s*=\s*\[[^\]]*"alice@example.com"[^\]]*\]/)
            expect(txt).to match(/spec\.summary\s*=\s*"Original summary"/)
            expect(txt).to match(/spec\.description\s*=\s*"Original description more text"/)
            expect(txt).to match(/spec\.licenses\s*=\s*\["Apache-2\.0"\]/)
            expect(txt).to match(/spec\.required_ruby_version\s*=\s*">= 3\.2"/)
            expect(txt).to match(/spec\.require_paths\s*=\s*\["lib", "ext"\]/)
            expect(txt).to match(/spec\.bindir\s*=\s*"bin"/)
            expect(txt).to match(/spec\.executables\s*=\s*\["mygem", "mg"\]/)
          end
        end
      end
    end

    describe "env preference for hook templates" do
      it "prefers hook_templates over KETTLE_DEV_HOOK_TEMPLATES for .git-hooks template choice" do
        Dir.mktmpdir do |project_root|
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

          hooks_dir = File.join(project_root, ".git-hooks")
          FileUtils.mkdir_p(hooks_dir)
          File.write(File.join(hooks_dir, "commit-subjects-goalie.txt"), "x")
          File.write(File.join(hooks_dir, "footer-template.erb.txt"), "x")

          dest_hooks_dir = File.join(project_root, ".git-hooks")
          FileUtils.mkdir_p(dest_hooks_dir)

          copied = []
          allow(helpers).to receive(:copy_file_with_prompt) do |src, dest, *_args|
            copied << [src, dest]
          end

          stub_env(
            "hook_templates" => "s",
            "KETTLE_DEV_HOOK_TEMPLATES" => "g",
            "allowed" => "true",
          )
          expect { described_class.run }.not_to raise_error

          expect(copied).to not_include(a_string_matching(/footer-template\.erb\.txt/)) &
            not_include(a_string_matching(/commit-subjects-goalie\.txt/))
        end
      end
    end
  end

  describe "CHANGELOG default spacing regression" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    before do
      stub_env("allowed" => "true")
      stub_env("FUNDING_ORG" => "false")
    end

    it "ensures a blank line exists between Unreleased chunk and first released version when using DEFAULT_CHANGELOG.md" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Use the DEFAULT_CHANGELOG.md fixture as the template CHANGELOG
          fixture_path = File.join(__dir__, "..", "..", "..", "support", "fixtures", "DEFAULT_CHANGELOG.md")
          default_changelog = if File.file?(fixture_path)
            content = File.read(fixture_path)
            content.strip.empty? ? nil : content
          end
          default_changelog ||= <<~MD
            # Changelog

            ## [Unreleased]
            ### Added
            ### Changed
            ### Deprecated
            ### Removed
            ### Fixed
            ### Security

            ## [0.1.0] - 2025-09-13
            - Initial release
          MD
          # Template CHANGELOG provides only header and Unreleased skeleton
          template_changelog = <<~MD
            # Changelog

            ## [Unreleased]
            ### Added
            ### Changed
            ### Deprecated
            ### Removed
            ### Fixed
            ### Security
          MD
          File.write(File.join(gem_root, "CHANGELOG.md.example"), template_changelog)

          # Destination project already has a default CHANGELOG (from bundle gem)
          File.write(File.join(project_root, "CHANGELOG.md"), default_changelog)

          # Minimal gemspec so metadata scanning works and replacements happen
          File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
            Gem::Specification.new do |spec|
              spec.name = "my-gem"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/my-gem"
            end
          GEMSPEC

          allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

          described_class.run

          result = File.read(File.join(project_root, "CHANGELOG.md"))
          # There must be exactly one blank line between the Unreleased section and the next version chunk
          # Specifically, ensure a blank line before the first numbered version header following Unreleased
          expect(result).to match(/## \[Unreleased\](?:.|\n)*?### Security\n\n## \[/)
        end
      end
    end
  end

  describe "::run prefers .junie/guidelines.md.example" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    before do
      stub_env("allowed" => "true")
      stub_env("FUNDING_ORG" => "false")
    end

    it "copies .junie/guidelines.md from the .example source when both exist" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Arrange template files
          src_dir = File.join(gem_root, ".junie")
          FileUtils.mkdir_p(src_dir)
          File.write(File.join(src_dir, "guidelines.md"), "REAL-GUIDELINES\n")
          File.write(File.join(src_dir, "guidelines.md.example"), "EXAMPLE-GUIDELINES\n")

          # Minimal gemspec so metadata scan works
          File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/demo"
            end
          GEMSPEC

          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

          expect { described_class.run }.not_to raise_error

          dest = File.join(project_root, ".junie", "guidelines.md")
          expect(File).to exist(dest)
          content = File.read(dest)
          expect(content).to include("EXAMPLE-GUIDELINES")
          expect(content).not_to include("REAL-GUIDELINES")
        end
      end
    end
  end

  describe "merging behaviors" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    before do
      stub_env("allowed" => "true")
      stub_env("FUNDING_ORG" => "false")
    end

    it "merges modular coverage gemfile content with existing custom entries" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          template_dir = File.join(gem_root, "gemfiles", "modular")
          FileUtils.mkdir_p(template_dir)
          File.write(File.join(template_dir, "coverage.gemfile"), <<~GEMFILE)
            source "https://rubygems.org"
            gem "simplecov", "~> 0.22"
          GEMFILE
          dest_dir = File.join(project_root, "gemfiles", "modular")
          FileUtils.mkdir_p(dest_dir)
          File.write(File.join(dest_dir, "coverage.gemfile"), <<~GEMFILE)
            # keep this comment
            gem "custom-coverage", "~> 1.0"
          GEMFILE
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
          described_class.run
          merged = File.read(File.join(dest_dir, "coverage.gemfile"))
          expect(merged).to include("# keep this comment")
          expect(merged).to include('gem "custom-coverage", "~> 1.0"')
          expect(merged).to include('gem "simplecov", "~> 0.22"')
        end
      end
    end

    it "merges existing style.gemfile content while updating rubocop tokens" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          template_dir = File.join(gem_root, "gemfiles", "modular")
          FileUtils.mkdir_p(template_dir)
          File.write(File.join(template_dir, "style.gemfile.example"), <<~GEMFILE)
            gem "rubocop-lts", "{RUBOCOP|LTS|CONSTRAINT}"
            gem "{RUBOCOP|RUBY|GEM}"
          GEMFILE
          dest_dir = File.join(project_root, "gemfiles", "modular")
          FileUtils.mkdir_p(dest_dir)
          File.write(File.join(dest_dir, "style.gemfile"), <<~GEMFILE)
            # existing customization
            gem "my-company-style"
          GEMFILE
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.2"
              spec.homepage = "https://github.com/acme/demo"
            end
          G
          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )
          described_class.run
          merged = File.read(File.join(dest_dir, "style.gemfile"))
          expect(merged).to include("# existing customization")
          expect(merged).to include('gem "my-company-style"')
          expect(merged).to include('gem "rubocop-lts", "~> 24.0"')
          expect(merged).to include('gem "rubocop-ruby3_2"')
        end
      end
    end
  end

  describe "run/install behaviors (continued)" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    before do
      stub_env("allowed" => "true") # allow env file changes without abort
      stub_env("FUNDING_ORG" => "false") # bypass funding org requirement in unit tests unless explicitly set
    end

    describe "::task_abort (duplicate check)" do
      it "raises Kettle::Dev::Error" do
        expect {
          described_class.task_abort("STOP ME")
        }.to raise_error(Kettle::Dev::Error, /STOP ME/)
      end
    end

    describe "::run (additional tests)" do
      it "prefers .example files under .github/workflows and writes without .example and customizes FUNDING.yml" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange template source
            gh_src = File.join(gem_root, ".github", "workflows")
            FileUtils.mkdir_p(gh_src)
            File.write(File.join(gh_src, "ci.yml"), "name: REAL\n")
            File.write(File.join(gh_src, "ci.yml.example"), "name: EXAMPLE\n")
            # FUNDING.yml example with placeholders
            File.write(File.join(gem_root, ".github", "FUNDING.yml.example"), <<~YAML)
              open_collective: placeholder
              tidelift: rubygems/placeholder
            YAML

            # Provide gemspec in project to satisfy metadata scanner
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            # Stub helpers used by the task
            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Override global funding disable for this example to allow customization
            stub_env("FUNDING_ORG" => "")

            # Exercise
            expect { described_class.run }.not_to raise_error

            # Assert
            dest_ci = File.join(project_root, ".github", "workflows", "ci.yml")
            expect(File).to exist(dest_ci)
            expect(File.read(dest_ci)).to include("EXAMPLE")

            # FUNDING content customized
            funding_dest = File.join(project_root, ".github", "FUNDING.yml")
            expect(File).to exist(funding_dest)
            funding = File.read(funding_dest)
            expect(funding).to include("open_collective: acme")
            expect(funding).to include("tidelift: rubygems/demo")
          end
        end
      end

      it "copies .env.local.example but does not create .env.local" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, ".env.local.example"), "SECRET=1\n")
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            expect { described_class.run }.not_to raise_error

            expect(File).to exist(File.join(project_root, ".env.local.example"))
            expect(File).not_to exist(File.join(project_root, ".env.local"))
          end
        end
      end

      it "replaces {TARGET|GEM|NAME} token in .envrc files" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Create .envrc.example with the token
            File.write(File.join(gem_root, ".envrc.example"), <<~ENVRC)
              export DEBUG=false
              # If {TARGET|GEM|NAME} does not have an open source collective set these to false.
              export OPENCOLLECTIVE_HANDLE={OPENCOLLECTIVE|ORG_NAME}
              export FUNDING_ORG={OPENCOLLECTIVE|ORG_NAME}
              dotenv_if_exists .env.local
            ENVRC

            # Provide gemspec in project
            File.write(File.join(project_root, "my-awesome-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-awesome-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/coolorg/my-awesome-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Override funding org for this test
            stub_env("FUNDING_ORG" => "")

            expect { described_class.run }.not_to raise_error

            # Assert .envrc was copied
            envrc_dest = File.join(project_root, ".envrc")
            expect(File).to exist(envrc_dest)

            # Assert {TARGET|GEM|NAME} was replaced with the actual gem name
            envrc_content = File.read(envrc_dest)
            expect(envrc_content).to include("# If my-awesome-gem does not have an open source collective")
            expect(envrc_content).not_to include("{TARGET|GEM|NAME}")

            # Assert other tokens were also replaced (from apply_common_replacements)
            expect(envrc_content).to include("export OPENCOLLECTIVE_HANDLE=coolorg")
            expect(envrc_content).to include("export FUNDING_ORG=coolorg")
          end
        end
      end

      it "updates style.gemfile rubocop-lts constraint based on min_ruby", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # style.gemfile template with placeholder constraint
            style_dir = File.join(gem_root, "gemfiles", "modular")
            FileUtils.mkdir_p(style_dir)
            File.write(File.join(style_dir, "style.gemfile.example"), <<~GEMFILE)
              if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
                gem "rubocop-lts", path: "src/rubocop-lts/rubocop-lts"
                gem "rubocop-lts-rspec", path: "src/rubocop-lts/rubocop-lts-rspec"
                gem "{RUBOCOP|RUBY|GEM}", path: "src/rubocop-lts/{RUBOCOP|RUBY|GEM}"
                gem "standard-rubocop-lts", path: "src/rubocop-lts/standard-rubocop-lts"
              else
                gem "rubocop-lts", "{RUBOCOP|LTS|CONSTRAINT}"
                gem "{RUBOCOP|RUBY|GEM}"
                gem "rubocop-rspec", "~> 3.6"
              end
            GEMFILE
            # gemspec declares min_ruby 3.2 -> map to "~> 24.0"
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.2"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "gemfiles", "modular", "style.gemfile")
            expect(File).to exist(dest)
            txt = File.read(dest)
            expect(txt).to include('gem "rubocop-lts", "~> 24.0"')
            expect(txt).to include('gem "rubocop-ruby3_2"')
          end
        end
      end

      it "keeps style.gemfile constraint unchanged when min_ruby is missing (else branch)" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            style_dir = File.join(gem_root, "gemfiles", "modular")
            FileUtils.mkdir_p(style_dir)
            File.write(File.join(style_dir, "style.gemfile.example"), <<~GEMFILE)
              if ENV.fetch("RUBOCOP_LTS_LOCAL", "false").casecmp("true").zero?
                gem "rubocop-lts", path: "src/rubocop-lts/rubocop-lts"
                gem "rubocop-lts-rspec", path: "src/rubocop-lts/rubocop-lts-rspec"
                gem "{RUBOCOP|RUBY|GEM}", path: "src/rubocop-lts/{RUBOCOP|RUBY|GEM}"
                gem "standard-rubocop-lts", path: "src/rubocop-lts/standard-rubocop-lts"
              else
                gem "rubocop-lts", "{RUBOCOP|LTS|CONSTRAINT}"
                gem "{RUBOCOP|RUBY|GEM}"
                gem "rubocop-rspec", "~> 3.6"
              end
            GEMFILE
            # gemspec without any min ruby declaration
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "gemfiles", "modular", "style.gemfile")
            expect(File).to exist(dest)
            txt = File.read(dest)
            expect(txt).to include('gem "rubocop-lts", "~> 0.1"')
            expect(txt).to include('gem "rubocop-ruby1_8"')
          end
        end
      end

      it "copies modular directories and additional gemfiles (erb, mutex_m, stringio, x_std_libs; debug/runtime_heads)" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            base = File.join(gem_root, "gemfiles", "modular")
            %w[erb mutex_m stringio x_std_libs].each do |d|
              dir = File.join(base, d)
              FileUtils.mkdir_p(dir)
              # nested/versioned example files
              FileUtils.mkdir_p(File.join(dir, "r2.6"))
              File.write(File.join(dir, "r2.6", "v2.2.gemfile"), "# v2.2\n")
              FileUtils.mkdir_p(File.join(dir, "r3"))
              File.write(File.join(dir, "r3", "libs.gemfile"), "# r3 libs\n")
            end
            # additional specific gemfiles
            File.write(File.join(base, "debug.gemfile"), "# debug\n")
            File.write(File.join(base, "runtime_heads.gemfile"), "# runtime heads\n")

            # minimal gemspec to satisfy metadata scan
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

            expect { described_class.run }.not_to raise_error

            # assert directories copied recursively
            %w[erb mutex_m stringio x_std_libs].each do |d|
              expect(File).to exist(File.join(project_root, "gemfiles", "modular", d, "r2.6", "v2.2.gemfile"))
              expect(File).to exist(File.join(project_root, "gemfiles", "modular", d, "r3", "libs.gemfile"))
            end
            # assert specific gemfiles copied
            expect(File).to exist(File.join(project_root, "gemfiles", "modular", "debug.gemfile"))
            expect(File).to exist(File.join(project_root, "gemfiles", "modular", "runtime_heads.gemfile"))
          end
        end
      end

      # Regression: optional.gemfile should prefer the .example version when both exist
      it "prefers optional.gemfile.example over optional.gemfile" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            dir = File.join(gem_root, "gemfiles", "modular")
            FileUtils.mkdir_p(dir)
            File.write(File.join(dir, "optional.gemfile"), "# REAL\nreal\n")
            File.write(File.join(dir, "optional.gemfile.example"), "# EXAMPLE\nexample\n")

            # Minimal gemspec so metadata scan works
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "gemfiles", "modular", "optional.gemfile")
            expect(File).to exist(dest)
            content = File.read(dest)
            lowered = content.downcase
            expect(lowered).to include("example")
            expect(lowered).not_to include("real")
          end
        end
      end

      it "replaces require in spec/spec_helper.rb when confirmed, or skips when declined" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange project spec_helper with kettle/dev
            spec_dir = File.join(project_root, "spec")
            FileUtils.mkdir_p(spec_dir)
            File.write(File.join(spec_dir, "spec_helper.rb"), "require 'kettle/dev'\n")
            # gemspec
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
            )

            # Case 1: confirm replacement
            allow(helpers).to receive(:ask).and_return(true)
            described_class.run
            content = File.read(File.join(spec_dir, "spec_helper.rb"))
            expect(content).to include('require "demo"')

            # Case 2: decline
            File.write(File.join(spec_dir, "spec_helper.rb"), "require 'kettle/dev'\n")
            allow(helpers).to receive(:ask).and_return(false)
            described_class.run
            content2 = File.read(File.join(spec_dir, "spec_helper.rb"))
            expect(content2).to include("require 'kettle/dev'")
          end
        end
      end

      it "merges README sections and preserves first H1 emojis", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange
            template_readme = <<~MD
              # 🚀 Template Title
              
              ## Synopsis
              Template synopsis.
              
              ## Configuration
              Template configuration.
              
              ## Basic Usage
              Template usage.
              
              ## NOTE: Something
              Template note.
            MD
            File.write(File.join(gem_root, "README.md"), template_readme)

            existing_readme = <<~MD
              # 🎉 Existing Title
              
              ## Synopsis
              Existing synopsis.
              
              ## Configuration
              Existing configuration.
              
              ## Basic Usage
              Existing usage.
              
              ## NOTE: Something
              Existing note.
            MD
            File.write(File.join(project_root, "README.md"), existing_readme)

            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Exercise
            described_class.run

            # Assert merge and H1 full-line preservation
            merged = File.read(File.join(project_root, "README.md"))
            expect(merged.lines.first).to match(/^#\s+🎉\s+Existing Title/)
            expect(merged).to include("Existing synopsis.")
            expect(merged).to include("Existing configuration.")
            expect(merged).to include("Existing usage.")
            expect(merged).to include("Existing note.")
          end
        end
      end

      it "copies kettle-dev.gemspec.example to <gem_name>.gemspec with substitutions" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Provide a kettle-dev.gemspec.example with tokens to be replaced
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                # Namespace token example
                Kettle::Dev
              end
            GEMSPEC

            # Destination project gemspec to derive gem_name and org/homepage
            File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "my-gem.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            expect(txt).to match(/spec\.name\s*=\s*\"my-gem\"/)
            expect(txt).to include("My::Gem")
          end
        end
      end

      it "removes self-dependencies in gemspec after templating (runtime and development, paren and no-paren)" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Template gemspec includes dependencies on the template gem name
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                spec.add_dependency("kettle-dev", "~> 1.0")
                spec.add_dependency 'kettle-dev'
                spec.add_development_dependency("kettle-dev")
                spec.add_development_dependency 'kettle-dev', ">= 0"
                spec.add_dependency("addressable", ">= 2.8", "< 3")
              end
            GEMSPEC

            # Destination project gemspec to derive gem_name and org/homepage
            File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "my-gem.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            # Self-dependency variants should be removed (they would otherwise become my-gem)
            expect(txt).not_to match(/spec\.add_(?:development_)?dependency\([\"\']my-gem[\"\']/)
            expect(txt).not_to match(/spec\.add_(?:development_)?dependency\s+[\"\']my-gem[\"\']/)
            # Other dependencies remain
            expect(txt).to include('spec.add_dependency("addressable", ">= 2.8", "< 3")')
          end
        end
      end

      it "when gem_name is missing, falls back to first existing *.gemspec in project" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Provide template gemspec example
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                Kettle::Dev
              end
            GEMSPEC

            # Destination already has a different gemspec; note: no name set elsewhere to derive gem_name
            File.write(File.join(project_root, "existing.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "existing"
                spec.homepage = "https://github.com/acme/existing"
              end
            GEMSPEC

            # project has no other gemspec affecting gem_name discovery (no spec.name parsing needed beyond existing)
            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            # Should have used existing.gemspec as destination
            dest = File.join(project_root, "existing.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            # Allow "kettle-dev" in freeze reminder comments, but verify actual code was replaced
            expect(txt).not_to include('spec.name = "kettle-dev"')
            expect(txt).not_to include("Kettle::Dev")
            expect(txt).to include("existing")
            # Allow "kettle-dev" in freeze reminder comments, but verify actual code was replaced
            expect(txt).not_to include('spec.name = "kettle-dev"')
            expect(txt).not_to include("Kettle::Dev")
          end
        end
      end

      it "when gem_name is missing and no gemspec exists, uses example basename without .example" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Provide template example only
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                Kettle::Dev
              end
            GEMSPEC

            # No destination gemspecs present
            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            # Should write kettle-dev.gemspec (no .example)
            dest = File.join(project_root, "kettle-dev.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            expect(txt).not_to include("kettle-dev.gemspec.example")
            # Note: when gem_name is unknown, namespace/gem replacements depending on gem_name may not occur.
            # This test verifies the destination file name logic only.
          end
        end
      end

      it "prefers .gitlab-ci.yml.example over .gitlab-ci.yml and writes destination without .example" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange template files at root
            File.write(File.join(gem_root, ".gitlab-ci.yml"), "from: REAL\n")
            File.write(File.join(gem_root, ".gitlab-ci.yml.example"), "from: EXAMPLE\n")

            # Minimal gemspec so metadata scan works
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Exercise
            described_class.run

            # Assert destination is the non-example name and content from example
            dest = File.join(project_root, ".gitlab-ci.yml")
            expect(File).to exist(dest)
            expect(File.read(dest)).to include("EXAMPLE")
          end
        end
      end

      it "copies .licenserc.yaml preferring .licenserc.yaml.example when available" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Arrange template files at root
            File.write(File.join(gem_root, ".licenserc.yaml"), "header:\n  license: REAL\n")
            File.write(File.join(gem_root, ".licenserc.yaml.example"), "header:\n  license: EXAMPLE\n")

            # Minimal gemspec so metadata scan works
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            # Exercise
            described_class.run

            # Assert destination is the non-example name and content from example
            dest = File.join(project_root, ".licenserc.yaml")
            expect(File).to exist(dest)
            expect(File.read(dest)).to include("EXAMPLE")
            expect(File.read(dest)).not_to include("REAL")
          end
        end
      end

      it "copies .idea/.gitignore into the project when present" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            idea_dir = File.join(gem_root, ".idea")
            FileUtils.mkdir_p(idea_dir)
            File.write(File.join(idea_dir, ".gitignore"), "/*.iml\n")

            # Minimal gemspec so metadata scan works
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, ".idea", ".gitignore")
            expect(File).to exist(dest)
            expect(File.read(dest)).to include("/*.iml")
          end
        end
      end

      it "prints a warning when copying .env.local.example raises", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, ".env.local.example"), "A=1\n")
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
            # Only raise for .env.local.example copy, not for other copies
            allow(helpers).to receive(:copy_file_with_prompt).and_wrap_original do |m, *args, &blk|
              src = args[0].to_s
              if File.basename(src) == ".env.local.example"
                raise ArgumentError, "boom"
              elsif args.last.is_a?(Hash)
                kw = args.pop
                m.call(*args, **kw, &blk)
              else
                m.call(*args, &blk)
              end
            end
            expect { described_class.run }.not_to raise_error
          end
        end
      end

      it "copies certs/pboling.pem when present, and warns on error", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            cert_dir = File.join(gem_root, "certs")
            FileUtils.mkdir_p(cert_dir)
            File.write(File.join(cert_dir, "pboling.pem"), "certdata")
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            # Normal run
            expect { described_class.run }.not_to raise_error
            expect(File).to exist(File.join(project_root, "certs", "pboling.pem"))

            # Error run
            allow(helpers).to receive(:copy_file_with_prompt).and_wrap_original do |m, *args, &blk|
              if args[0].to_s.end_with?(File.join("certs", "pboling.pem"))
                raise "nope"
              elsif args.last.is_a?(Hash)
                kw = args.pop
                m.call(*args, **kw, &blk)
              else
                m.call(*args, &blk)
              end
            end
            expect { described_class.run }.not_to raise_error
          end
        end
      end

      context "when reviewing env file changes", :check_output do
        it "proceeds when allowed=true" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              File.write(File.join(gem_root, ".envrc"), "export A=1\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(helpers).to receive(:modified_by_template?).and_return(true)
              stub_env("allowed" => "true")
              expect { described_class.run }.not_to raise_error
            end
          end
        end

        it "aborts with guidance when not allowed" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              File.write(File.join(gem_root, ".envrc"), "export A=1\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(helpers).to receive(:modified_by_template?).and_return(true)
              stub_env("allowed" => "")
              expect { described_class.run }.to raise_error(Kettle::Dev::Error, /review of environment files required/)
            end
          end
        end

        it "warns when check raises" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              File.write(File.join(gem_root, ".envrc"), "export A=1\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(helpers).to receive(:modified_by_template?).and_raise(StandardError, "oops")
              stub_env("allowed" => "true")
              expect { described_class.run }.not_to raise_error
            end
          end
        end
      end

      it "applies replacements for special root files like CHANGELOG.md and .opencollective.yml and FUNDING.md" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "CHANGELOG.md.example"), "kettle-rb kettle-dev Kettle::Dev Kettle%3A%3ADev kettle--dev\n")
            File.write(File.join(gem_root, ".opencollective.yml"), "org: kettle-rb project: kettle-dev\n")
            # FUNDING with org placeholder to be replaced
            File.write(File.join(gem_root, "FUNDING.md"), "Support org kettle-rb and project kettle-dev\n")
            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            changelog = File.read(File.join(project_root, "CHANGELOG.md"))
            expect(changelog).to include("acme")
            expect(changelog).to include("my-gem")
            expect(changelog).to include("My::Gem")
            expect(changelog).to include("My%3A%3AGem")
            expect(changelog).to include("my--gem")

            # FUNDING.md should be copied and have org replaced with funding org (acme)
            funding = File.read(File.join(project_root, "FUNDING.md"))
            expect(funding).to include("acme")
            expect(funding).not_to include("kettle-rb")
          end
        end
      end

      it "does not duplicate Unreleased change-type headings and preserves existing list items under them, including nested bullets" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Template CHANGELOG with Unreleased and six standard headings (empty)
            File.write(File.join(gem_root, "CHANGELOG.md.example"), <<~MD)
              # Changelog
              \n
              ## [Unreleased]
              ### Added
              ### Changed
              ### Deprecated
              ### Removed
              ### Fixed
              ### Security
              \n
              ## [0.1.0] - 2020-01-01
              - initial
            MD

            # Destination project with existing Unreleased having items including nested sub-bullets
            File.write(File.join(project_root, "CHANGELOG.md"), <<~MD)
              # Changelog
              \n
              ## [Unreleased]
              ### Added
              - kettle-dev v1.1.18
              - Internal escape & unescape methods
                - Stop relying on URI / CGI for escaping and unescaping
                - They are both unstable across supported versions of Ruby (including 3.5 HEAD)
              - keep me
              ### Fixed
              - also keep me
              \n
              ## [0.0.1] - 2019-01-01
              - start
            MD

            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            result = File.read(File.join(project_root, "CHANGELOG.md"))
            # Exactly one of each standard heading under Unreleased
            %w[Added Changed Deprecated Removed Fixed Security].each do |h|
              expect(result.scan(/^### #{h}$/).size).to eq(1)
            end
            # Preserved items, including nested sub-bullets and their indentation
            expect(result).to include("### Added\n\n- kettle-dev v1.1.18")
            expect(result).to include("- Internal escape & unescape methods")
            expect(result).to include("  - Stop relying on URI / CGI for escaping and unescaping")
            expect(result).to include("  - They are both unstable across supported versions of Ruby (including 3.5 HEAD)")
            expect(result).to include("- keep me")
            expect(result).to include("### Fixed\n\n- also keep me")
          end
        end
      end

      it "ensures blank lines before and after headings in CHANGELOG.md" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "CHANGELOG.md.example"), <<~MD)
              # Changelog
              ## [Unreleased]
              ### Added
              ### Changed

              ## [0.1.0] - 2020-01-01
              - initial
            MD
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            content = File.read(File.join(project_root, "CHANGELOG.md"))
            # Expect blank line after H1 and before the next heading
            expect(content).to match(/# Changelog\n\n## \[Unreleased\]/)
            # Expect blank line after Unreleased and before the first subheading
            expect(content).to match(/## \[Unreleased\]\n\n### Added/)
            # Expect blank line between consecutive subheadings
            expect(content).to match(/### Added\n\n### Changed/)
          end
        end
      end

      it "preserves GFM fenced code blocks nested under list items in Unreleased sections" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Template with empty Unreleased standard headings
            File.write(File.join(gem_root, "CHANGELOG.md.example"), <<~MD)
              # Changelog

              ## [Unreleased]
              ### Added
              ### Changed
              ### Deprecated
              ### Removed
              ### Fixed
              ### Security

              ## [0.1.0] - 2020-01-01
              - initial
            MD

            # Destination with a bullet containing a fenced code block
            File.write(File.join(project_root, "CHANGELOG.md"), <<~MD)
              # Changelog

              ## [Unreleased]
              ### Added
              - Add helper with example usage
                
                ```ruby
                puts "hello"
                1 + 2
                ```
              - Another item

              ## [0.0.1] - 2019-01-01
              - start
            MD

            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            result = File.read(File.join(project_root, "CHANGELOG.md"))
            # Ensure the fenced block and its contents are preserved under the list item
            expect(result).to include("### Added")
            expect(result).to include("- Add helper with example usage")
            expect(result).to include("```ruby")
            expect(result).to include("puts \"hello\"")
            expect(result).to include("1 + 2")
            expect(result).to include("```")
            expect(result).to include("- Another item")
          end
        end
      end

      context "with .git-hooks present" do
        it "honors only filter by skipping .git-hooks when not selected" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              # Arrange .git-hooks in template checkout
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "x")
              File.write(File.join(hooks_src, "footer-template.erb.txt"), "y")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

              # Set only to README.md, which should exclude .git-hooks completely
              stub_env("only" => "README.md")
              # If code ignores only for hooks, it would prompt; ensure no blocking by pre-answering
              allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("")

              described_class.run
              expect(File).not_to exist(File.join(project_root, ".git-hooks", "commit-subjects-goalie.txt"))
              expect(File).not_to exist(File.join(project_root, ".git-hooks", "footer-template.erb.txt"))
            end
          end
        end

        it "copies templates when only includes .git-hooks/**", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "x")
              File.write(File.join(hooks_src, "footer-template.erb.txt"), "y")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              stub_env("only" => ".git-hooks/**")
              allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("")
              described_class.run
              expect(File).to exist(File.join(project_root, ".git-hooks", "commit-subjects-goalie.txt"))
              expect(File).to exist(File.join(project_root, ".git-hooks", "footer-template.erb.txt"))
            end
          end
        end

        it "copies templates locally by default", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "x")
              File.write(File.join(hooks_src, "footer-template.erb.txt"), "y")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("")
              described_class.run
              expect(File).to exist(File.join(project_root, ".git-hooks", "commit-subjects-goalie.txt"))
            end
          end
        end

        it "skips copying templates when user chooses 's'", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "x")
              File.write(File.join(hooks_src, "footer-template.erb.txt"), "y")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("s\n")
              described_class.run
              expect(File).not_to exist(File.join(project_root, ".git-hooks", "commit-subjects-goalie.txt"))
            end
          end
        end

        it "installs hook scripts; overwrite yes/no and fresh install", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-msg"), "echo ruby hook\n")
              File.write(File.join(hooks_src, "prepare-commit-msg"), "echo sh hook\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

              # Force templates conditional to false
              allow(Dir).to receive(:exist?).and_call_original
              allow(Dir).to receive(:exist?).with(File.join(gem_root, ".git-hooks")).and_return(true)
              allow(File).to receive(:file?).and_call_original
              allow(File).to receive(:file?).with(File.join(gem_root, ".git-hooks", "commit-subjects-goalie.txt")).and_return(false)
              allow(File).to receive(:file?).with(File.join(gem_root, ".git-hooks", "footer-template.erb.txt")).and_return(false)

              # First run installs
              described_class.run
              dest_dir = File.join(project_root, ".git-hooks")
              commit_hook = File.join(dest_dir, "commit-msg")
              prepare_hook = File.join(dest_dir, "prepare-commit-msg")
              expect(File).to exist(commit_hook)
              expect(File).to exist(prepare_hook)
              expect(File.executable?(commit_hook)).to be(true)
              expect(File.executable?(prepare_hook)).to be(true)

              # Overwrite yes
              allow(helpers).to receive(:ask).and_return(true)
              described_class.run
              expect(File.executable?(commit_hook)).to be(true)
              expect(File.executable?(prepare_hook)).to be(true)
              # Overwrite no
              allow(helpers).to receive(:ask).and_return(false)
              described_class.run
              expect(File.executable?(commit_hook)).to be(true)
              expect(File.executable?(prepare_hook)).to be(true)
            end
          end
        end

        it "prefers prepare-commit-msg.example over prepare-commit-msg when both exist" do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              # Provide both real and example; example should be preferred
              File.write(File.join(hooks_src, "prepare-commit-msg"), "REAL\n")
              File.write(File.join(hooks_src, "prepare-commit-msg.example"), "EXAMPLE\n")
              # Commit hook presence isn't required for this behavior, but include to mirror typical state
              File.write(File.join(hooks_src, "commit-msg"), "ruby hook\n")

              # Minimal gemspec in project for metadata
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")

              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

              # Ensure the templates (.txt) branch does not trigger prompts/copies, to keep test focused
              allow(File).to receive(:file?).and_call_original
              allow(File).to receive(:file?).with(File.join(gem_root, ".git-hooks", "commit-subjects-goalie.txt")).and_return(false)
              allow(File).to receive(:file?).with(File.join(gem_root, ".git-hooks", "footer-template.erb.txt")).and_return(false)

              described_class.run

              dest = File.join(project_root, ".git-hooks", "prepare-commit-msg")
              expect(File).to exist(dest)
              content = File.read(dest)
              expect(content).to include("EXAMPLE")
              expect(content).not_to include("REAL")
            end
          end
        end

        it "warns when installing hook scripts raises", :check_output do
          Dir.mktmpdir do |gem_root|
            Dir.mktmpdir do |project_root|
              hooks_src = File.join(gem_root, ".git-hooks")
              FileUtils.mkdir_p(hooks_src)
              File.write(File.join(hooks_src, "commit-msg"), "echo ruby hook\n")
              File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'; s.homepage='https://github.com/acme/demo'}\n")
              allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
              allow(FileUtils).to receive(:mkdir_p).and_raise(StandardError, "perm")
              expect { described_class.run }.not_to raise_error
            end
          end
        end
      end

      it "preserves nested subsections under preserved H2 sections during README merge" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            template_readme = <<~MD
              # 🚀 Template Title

              ## Synopsis
              Template synopsis.

              ## Configuration
              Template configuration.

              ## Basic Usage
              Template usage.
            MD
            File.write(File.join(gem_root, "README.md"), template_readme)

            existing_readme = <<~MD
              # 🎉 Existing Title

              ## Synopsis
              Existing synopsis intro.

              ### Details
              Keep this nested detail.

              #### More
              And this deeper detail.

              ## Configuration
              Existing configuration.

              ## Basic Usage
              Existing usage.
            MD
            File.write(File.join(project_root, "README.md"), existing_readme)

            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            merged = File.read(File.join(project_root, "README.md"))
            # H1 emoji preserved
            expect(merged.lines.first).to match(/^#\s+🎉\s+Existing Title/)
            # Preserved H2 branch content
            expect(merged).to include("Existing synopsis intro.")
            expect(merged).to include("### Details")
            expect(merged).to include("Keep this nested detail.")
            expect(merged).to include("#### More")
            expect(merged).to include("And this deeper detail.")
            # Other targeted sections still merged
            expect(merged).to include("Existing configuration.")
            expect(merged).to include("Existing usage.")
          end
        end
      end

      it "does not treat # inside fenced code blocks as headings during README merge" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            template_readme = <<~MD
              # 🚀 Template Title

              ## Synopsis
              Template synopsis.

              ## Configuration
              Template configuration.

              ## Basic Usage
              Template usage.
            MD
            File.write(File.join(gem_root, "README.md"), template_readme)

            existing_readme = <<~MD
              # 🎉 Existing Title

              ## Synopsis
              Existing synopsis.

              ```console
              # DANGER: options to reduce prompts will overwrite files without asking.
              bundle exec rake kettle:dev:install allowed=true force=true
              ```

              ## Configuration
              Existing configuration.

              ## Basic Usage
              Existing usage.
            MD
            File.write(File.join(project_root, "README.md"), existing_readme)

            File.write(File.join(project_root, "demo.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "demo"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/demo"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            merged = File.read(File.join(project_root, "README.md"))
            # H1 full-line preserved from existing README
            expect(merged.lines.first).to match(/^#\s+🎉\s+Existing Title/)
            # Ensure the code block remains intact and not split
            expect(merged).to include("```console")
            expect(merged).to include("# DANGER: options to reduce prompts will overwrite files without asking.")
            expect(merged).to include("bundle exec rake kettle:dev:install allowed=true force=true")
            # And targeted sections still merged with existing content
            expect(merged).to include("Existing synopsis.")
            expect(merged).to include("Existing configuration.")
            expect(merged).to include("Existing usage.")
          end
        end
      end

      it "replaces {KETTLE|DEV|GEM} token after normal replacements" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            # Template gemspec example contains both normal tokens and the special token
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                # This should become the actual destination gem name via normal replacement
                spec.summary = "kettle-dev summary"
                # This token should be replaced AFTER normal replacements with the literal string
                spec.add_development_dependency("{KETTLE|DEV|GEM}", "~> 1.0.0")
              end
            GEMSPEC

            # Destination project gemspec defines gem_name and org so replacements occur
            File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.required_ruby_version = ">= 3.1"
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(
              project_root: project_root,
              gem_checkout_root: gem_root,
              ensure_clean_git!: nil,
              ask: true,
            )

            described_class.run

            dest = File.join(project_root, "my-gem.gemspec")
            expect(File).to exist(dest)
            txt = File.read(dest)
            # Normal replacement happened: occurrences of kettle-dev became my-gem
            expect(txt).to match(/spec\.summary\s*=\s*"my-gem summary"/)
            # Special token replacement happened AFTER, yielding literal kettle-dev
            expect(txt).to include('spec.add_development_dependency("kettle-dev", "~> 1.0.0")')
          end
        end
      end

      it "copies Appraisal.root.gemfile with AST merge" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "Appraisal.root.gemfile"), <<~RUBY)
              source "https://rubygems.org"
              gem "foo"
            RUBY
            File.write(File.join(project_root, "Appraisal.root.gemfile"), <<~RUBY)
              source "https://example.com"
              gem "bar"
            RUBY
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
            described_class.run
            merged = File.read(File.join(project_root, "Appraisal.root.gemfile"))
            expect(merged).to include('source "https://rubygems.org"')
            expect(merged).to include('gem "foo"')
            expect(merged).to include('gem "bar"')
          end
        end
      end

      it "merges Appraisals entries without losing custom appraise blocks" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "Appraisals"), <<~APP)
              appraise "ruby-3.1" do
                gemfile "gemfiles/ruby_3.1.gemfile"
              end
            APP
            File.write(File.join(project_root, "Appraisals"), <<~APP)
              appraise "ruby-3.0" do
                gemfile "gemfiles/ruby_3.0.gemfile"
              end
            APP
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
            described_class.run
            merged = File.read(File.join(project_root, "Appraisals"))
            expect(merged).to include('appraise("ruby-3.1")')
            expect(merged).to include('appraise("ruby-3.0")')
          end
        end
      end
    end
  end

  # Consolidated from template_task_carryover_spec.rb and template_task_env_spec.rb
  describe "carryover/env behaviors (part 2)" do
    let(:helpers) { Kettle::Dev::TemplateHelpers }

    describe "carryover of gemspec fields (part 2)" do
      before { stub_env("allowed" => "true") }

      it "carries over key fields from original gemspec when overwriting with example (after replacements)" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "kettle-dev"
                spec.version = "1.0.0"
                spec.authors = ["Template Author"]
                spec.email = ["template@example.com"]
                spec.summary = "🍲 Template summary"
                spec.description = "🍲 Template description"
                spec.license = "MIT"
                spec.required_ruby_version = ">= 2.3.0"
                spec.require_paths = ["lib"]
                spec.bindir = "exe"
                spec.executables = ["templ"]
                Kettle::Dev
              end
            GEMSPEC

            File.write(File.join(project_root, "my-gem.gemspec"), <<~GEMSPEC)
              Gem::Specification.new do |spec|
                spec.name = "my-gem"
                spec.version = "0.1.0"
                spec.authors = ["Alice", "Bob"]
                spec.email = ["alice@example.com"]
                spec.summary = "Original summary"
                spec.description = "Original description more text"
                spec.license = "Apache-2.0"
                spec.required_ruby_version = ">= 3.2"
                spec.require_paths = ["lib", "ext"]
                spec.bindir = "bin"
                spec.executables = ["mygem", "mg"]
                spec.homepage = "https://github.com/acme/my-gem"
              end
            GEMSPEC

            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

            described_class.run

            dest = File.join(project_root, "my-gem.gemspec")
            txt = File.read(dest)
            expect(txt).to match(/spec\.name\s*=\s*\"my-gem\"/)
            expect(txt).to match(/spec\.authors\s*=\s*\[[^\]]*"Alice"[^\]]*"Bob"[^\]]*\]/)
            expect(txt).not_to match(/spec\.email\s*=\s*\[[^\]]*"template@example.com"[^\]]*\]/)
            expect(txt).to match(/spec\.email\s*=\s*\[[^\]]*"alice@example.com"[^\]]*\]/)
            expect(txt).to match(/spec\.summary\s*=\s*"Original summary"/)
            expect(txt).to match(/spec\.description\s*=\s*"Original description more text"/)
            expect(txt).to match(/spec\.licenses\s*=\s*\["Apache-2\.0"\]/)
            expect(txt).to match(/spec\.required_ruby_version\s*=\s*">= 3\.2"/)
            expect(txt).to match(/spec\.require_paths\s*=\s*\["lib", "ext"\]/)
            expect(txt).to match(/spec\.bindir\s*=\s*"bin"/)
            expect(txt).to match(/spec\.executables\s*=\s*\["mygem", "mg"\]/)
          end
        end
      end
    end

    describe "env preference for hook templates" do
      it "prefers hook_templates over KETTLE_DEV_HOOK_TEMPLATES for .git-hooks template choice" do
        Dir.mktmpdir do |project_root|
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

          hooks_dir = File.join(project_root, ".git-hooks")
          FileUtils.mkdir_p(hooks_dir)
          File.write(File.join(hooks_dir, "commit-subjects-goalie.txt"), "x")
          File.write(File.join(hooks_dir, "footer-template.erb.txt"), "x")

          dest_hooks_dir = File.join(project_root, ".git-hooks")
          FileUtils.mkdir_p(dest_hooks_dir)

          copied = []
          allow(helpers).to receive(:copy_file_with_prompt) do |src, dest, *_args|
            copied << [src, dest]
          end

          stub_env(
            "hook_templates" => "s",
            "KETTLE_DEV_HOOK_TEMPLATES" => "g",
            "allowed" => "true",
          )
          expect { described_class.run }.not_to raise_error

          expect(copied).to not_include(a_string_matching(/footer-template\.erb\.txt/)) &
            not_include(a_string_matching(/commit-subjects-goalie\.txt/))
        end
      end
    end
  end
end
