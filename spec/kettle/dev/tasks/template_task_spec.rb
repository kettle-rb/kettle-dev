# frozen_string_literal: true

# Unit specs for Kettle::Dev::Tasks::TemplateTask
# Mirrors a subset of behavior covered by the rake integration spec, but
# calls the class API directly for focused unit testing.

require "rake"
require "open3"

RSpec.describe Kettle::Dev::Tasks::TemplateTask do
  let(:helpers) { Kettle::Dev::TemplateHelpers }

  before do
    stub_env("allowed" => "true") # allow env file changes without abort
  end

  describe "::task_abort" do
    it "raises Kettle::Dev::Error when running under RSpec (abort is suppressed during specs)" do
      expect {
        described_class.task_abort("STOP ME")
      }.to raise_error(Kettle::Dev::Error, /STOP ME/)
    end

    it "delegates to ExitAdapter.abort when RSpec is not defined (subprocess)" do
      ruby = RbConfig.ruby
      libdir = File.expand_path("../../../../../../lib", __FILE__)
      script = <<~'R'
        require "kettle/dev/tasks/template_task"
        module Kettle; module Dev; module ExitAdapter
          def self.abort(msg); puts("CALLED: #{msg}"); end
        end; end; end
        Kettle::Dev::Tasks::TemplateTask.task_abort("BYE")
      R
      out, = Open3.capture3(ruby, "-I", libdir, "-e", script)
      # Some Rubies may mark nonzero due to tooling; assert on output primarily
      expect(out).to include("CALLED: BYE")
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
          File.write(File.join(gem_root, ".github", "FUNDING.yml.example"), <<~Y)
            open_collective: placeholder
            tidelift: rubygems/placeholder
          Y

          # Provide gemspec in project to satisfy metadata scanner
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/demo"
            end
          G

          # Stub helpers used by the task
          allow(helpers).to receive_messages(
            project_root: project_root,
            gem_checkout_root: gem_root,
            ensure_clean_git!: nil,
            ask: true,
          )

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
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
            end
          G

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

    it "updates style.gemfile rubocop-lts constraint based on min_ruby" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # style.gemfile template with placeholder constraint
          style_dir = File.join(gem_root, "gemfiles", "modular")
          FileUtils.mkdir_p(style_dir)
          File.write(File.join(style_dir, "style.gemfile.example"), <<~G)
            source "https://rubygems.org"
            gem "rubocop-lts", "~> 10.0"
          G
          # gemspec declares min_ruby 3.2 -> map to "~> 24.0"
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.minimum_ruby_version = ">= 3.2"
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

          dest = File.join(project_root, "gemfiles", "modular", "style.gemfile")
          expect(File).to exist(dest)
          txt = File.read(dest)
          expect(txt).to include("gem \"rubocop-lts\", \"~> 24.0\"")
        end
      end
    end

    it "keeps style.gemfile constraint unchanged when min_ruby is missing (else branch)" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          style_dir = File.join(gem_root, "gemfiles", "modular")
          FileUtils.mkdir_p(style_dir)
          File.write(File.join(style_dir, "style.gemfile.example"), <<~G)
            source "https://rubygems.org"
            gem "rubocop-lts", "~> 10.0"
          G
          # gemspec without any min ruby declaration
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
            end
          G

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
          expect(txt).to include("gem \"rubocop-lts\", \"~> 10.0\"")
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

          dest = File.join(project_root, "gemfiles", "modular", "optional.gemfile")
          expect(File).to exist(dest)
          content = File.read(dest)
          expect(content).to include("EXAMPLE")
          expect(content).not_to include("REAL")
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
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "demo"
              spec.required_ruby_version = ">= 3.1"
            end
          G

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
          File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "kettle-dev"
              # Namespace token example
              Kettle::Dev
            end
          G

          # Destination project gemspec to derive gem_name and org/homepage
          File.write(File.join(project_root, "my-gem.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "my-gem"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/my-gem"
            end
          G

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
          expect(txt).to include("spec.name = \"my-gem\"")
          expect(txt).to include("My::Gem")
        end
      end
    end

    it "when gem_name is missing, falls back to first existing *.gemspec in project" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Provide template gemspec example
          File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "kettle-dev"
              Kettle::Dev
            end
          G

          # Destination already has a different gemspec; note: no name set elsewhere to derive gem_name
          File.write(File.join(project_root, "existing.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "existing"
              spec.homepage = "https://github.com/acme/existing"
            end
          G

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
          expect(txt).not_to include("kettle-dev")
        end
      end
    end

    it "when gem_name is missing and no gemspec exists, uses example basename without .example" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          # Provide template example only
          File.write(File.join(gem_root, "kettle-dev.gemspec.example"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "kettle-dev"
              Kettle::Dev
            end
          G

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

          # Exercise
          described_class.run

          # Assert destination is the non-example name and content from example
          dest = File.join(project_root, ".gitlab-ci.yml")
          expect(File).to exist(dest)
          expect(File.read(dest)).to include("EXAMPLE")
        end
      end
    end

    it "prints a warning when copying .env.local.example raises", :check_output do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          File.write(File.join(gem_root, ".env.local.example"), "A=1\n")
          File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'}\n")
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
          File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'}\n")
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

    context "env file change review", :check_output do
      it "proceeds when allowed=true" do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            File.write(File.join(gem_root, ".envrc"), "export A=1\n")
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'}\n")
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
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'}\n")
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
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'}\n")
            allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)
            allow(helpers).to receive(:modified_by_template?).and_raise(StandardError, "oops")
            stub_env("allowed" => "true")
            expect { described_class.run }.not_to raise_error
          end
        end
      end
    end

    it "applies replacements for special root files like CHANGELOG.md and .opencollective.yml" do
      Dir.mktmpdir do |gem_root|
        Dir.mktmpdir do |project_root|
          File.write(File.join(gem_root, "CHANGELOG.md.example"), "kettle-rb kettle-dev Kettle::Dev Kettle%3A%3ADev kettle--dev\n")
          File.write(File.join(gem_root, ".opencollective.yml"), "org: kettle-rb project: kettle-dev\n")
          File.write(File.join(project_root, "demo.gemspec"), <<~G)
            Gem::Specification.new do |spec|
              spec.name = "my-gem"
              spec.required_ruby_version = ">= 3.1"
              spec.homepage = "https://github.com/acme/my-gem"
            end
          G
          allow(helpers).to receive_messages(project_root: project_root, gem_checkout_root: gem_root, ensure_clean_git!: nil, ask: true)

          described_class.run

          changelog = File.read(File.join(project_root, "CHANGELOG.md"))
          expect(changelog).to include("acme")
          expect(changelog).to include("my-gem")
          expect(changelog).to include("My::Gem")
          expect(changelog).to include("My%3A%3AGem")
          expect(changelog).to include("my--gem")
        end
      end
    end

    context "with .git-hooks present" do
      it "copies templates locally by default", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            hooks_src = File.join(gem_root, ".git-hooks")
            FileUtils.mkdir_p(hooks_src)
            File.write(File.join(hooks_src, "commit-subjects-goalie.txt"), "x")
            File.write(File.join(hooks_src, "footer-template.erb.txt"), "y")
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'}\n")
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
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'}\n")
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
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'}\n")
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
            expect(File).to exist(File.join(dest_dir, "commit-msg"))

            # Overwrite yes
            allow(helpers).to receive(:ask).and_return(true)
            described_class.run
            # Overwrite no
            allow(helpers).to receive(:ask).and_return(false)
            described_class.run
          end
        end
      end

      it "warns when installing hook scripts raises", :check_output do
        Dir.mktmpdir do |gem_root|
          Dir.mktmpdir do |project_root|
            hooks_src = File.join(gem_root, ".git-hooks")
            FileUtils.mkdir_p(hooks_src)
            File.write(File.join(hooks_src, "commit-msg"), "echo ruby hook\n")
            File.write(File.join(project_root, "demo.gemspec"), "Gem::Specification.new{|s| s.name='demo'}\n")
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
  end
end
