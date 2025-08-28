# frozen_string_literal: true

# Unit specs for Kettle::Dev::Tasks::InstallTask
# These tests focus on exercising branches documented as missing coverage.
# rubocop:disable RSpec/MultipleExpectations, RSpec/VerifiedDoubles, RSpec/ReceiveMessages

require "rake"

RSpec.describe Kettle::Dev::Tasks::InstallTask do
  let(:helpers) { Kettle::Dev::TemplateHelpers }

  before do
    # Prevent invoking the real rake task; stub it to a no-op
    allow(Rake::Task).to receive(:[]).with("kettle:dev:template").and_return(double(invoke: nil))
  end

  describe "::run" do
    it "trims MRI Ruby badges below gemspec required_ruby_version and removes unused link refs" do
      Dir.mktmpdir do |project_root|
        # Create a gemspec with required_ruby_version >= 2.3
        File.write(File.join(project_root, "demo.gemspec"), <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.required_ruby_version = ">= 2.3"
            spec.homepage = "https://github.com/acme/demo"
          end
        G
        # Minimal README with MRI rows and refs
        readme = <<~MD
          | Works with MRI Ruby 3   | [![Ruby 3.0 Compat][💎ruby-3.0i]][🚎4-lg-wf] [![Ruby 3.1 Compat][💎ruby-3.1i]][🚎6-s-wf] |
          | Works with MRI Ruby 2   | ![Ruby 2.0 Compat][💎ruby-2.0i] ![Ruby 2.1 Compat][💎ruby-2.1i] [![Ruby 2.3 Compat][💎ruby-2.3i]][🚎1-an-wf] |
          | Works with MRI Ruby 1   | ![Ruby 1.8 Compat][💎ruby-1.8i] ![Ruby 1.9 Compat][💎ruby-1.9i] |

          [💎ruby-1.8i]: https://example/18
          [💎ruby-1.9i]: https://example/19
          [💎ruby-2.0i]: https://example/20
          [💎ruby-2.1i]: https://example/21
          [💎ruby-2.3i]: https://example/23
          [💎ruby-3.0i]: https://example/30
          [💎ruby-3.1i]: https://example/31
          [🚎1-an-wf]: https://example/ancient
          [🚎4-lg-wf]: https://example/legacy
          [🚎6-s-wf]: https://example/supported
        MD
        File.write(File.join(project_root, "README.md"), readme)

        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: true, # skip .envrc prompting path
          template_results: {},
        )
        # Stubbing Rake template task already done in before

        described_class.run

        edited = File.read(File.join(project_root, "README.md"))
        table = edited.lines.select { |l| l.start_with?("| Works with MRI") }.join
        # Badges below 2.3 removed from table rows
        expect(table).not_to include("ruby-1.8i")
        expect(table).not_to include("ruby-1.9i")
        expect(table).not_to include("ruby-2.0i")
        expect(table).not_to include("ruby-2.1i")
        # 2.3+ remain in table rows
        expect(table).to include("ruby-2.3i")
        expect(table).to include("ruby-3.0i")
        expect(table).to include("ruby-3.1i")
        # Link reference lines for removed versions are deleted
        expect(edited).not_to match(/^\[💎ruby-1\.8i\]:/)
        expect(edited).not_to match(/^\[💎ruby-1\.9i\]:/)
        expect(edited).not_to match(/^\[💎ruby-2\.0i\]:/)
        expect(edited).not_to match(/^\[💎ruby-2\.1i\]:/)
        # Link refs used by remaining badges and workflows remain
        expect(edited).to match(/^\[💎ruby-2\.3i\]:/)
        expect(edited).to match(/^\[💎ruby-3\.0i\]:/)
        expect(edited).to match(/^\[💎ruby-3\.1i\]:/)
        expect(edited).to match(/^\[🚎6-s-wf\]:/)
      end
    end

    it "prints direnv notes when .envrc was modified by template" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: true,
          template_results: {},
        )

        expect { described_class.run }.not_to raise_error
      end
    end

    it "detects PATH_add bin already present in .envrc" do
      Dir.mktmpdir do |project_root|
        envrc = File.join(project_root, ".envrc")
        File.write(envrc, "\n  PATH_add   bin  \n")

        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )

        expect { described_class.run }.not_to raise_error
      end
    end

    it "adds PATH_add bin to .envrc on prompt accept and continues when allowed=true", :check_output do
      Dir.mktmpdir do |project_root|
        envrc = File.join(project_root, ".envrc")
        # Create unreadable scenario -> read failure rescued to ""
        Dir.mkdir(envrc)

        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          ask: true,
          template_results: {},
        )

        stub_env("allowed" => "true")

        expect { described_class.run }.not_to raise_error
        # Ensure file was created with PATH_add
        expect(File.file?(envrc)).to be true
        expect(File.read(envrc)).to include("PATH_add bin")
      end
    end

    it "skips modifying .envrc when user declines" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          ask: false,
          template_results: {},
        )

        expect { described_class.run }.not_to raise_error
        expect(File).not_to exist(File.join(project_root, ".envrc"))
      end
    end

    it "adds .env.local to .gitignore (forced) and prints confirmation" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )

        # Force non-interactive add
        stub_env("force" => "true")

        expect { described_class.run }.not_to raise_error
        gi = File.join(project_root, ".gitignore")
        expect(File).to exist(gi)
        txt = File.read(gi)
        expect(txt).to include("# direnv - brew install direnv")
        expect(txt).to include(".env.local\n")
      end
    end

    it "skips adding .env.local to .gitignore when declined" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )

        # Decline prompt; stub input adapter for this example only
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("n\n")

        expect { described_class.run }.not_to raise_error
        gi = File.join(project_root, ".gitignore")
        expect(File).not_to exist(gi)
      end
    end

    it "notes when no gemspec is present" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )
        expect { described_class.run }.not_to raise_error
      end
    end

    it "warns when multiple gemspecs and homepage missing" do
      Dir.mktmpdir do |project_root|
        File.write(File.join(project_root, "a.gemspec"), "Gem::Specification.new do |spec| spec.name='a' end\n")
        File.write(File.join(project_root, "b.gemspec"), "Gem::Specification.new do |spec| spec.name='b' end\n")

        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )

        expect { described_class.run }.not_to raise_error
      end
    end

    it "aborts when homepage invalid and no GitHub origin remote is found" do
      Dir.mktmpdir do |project_root|
        gemspec = File.join(project_root, "demo.gemspec")
        File.write(gemspec, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.homepage = "http://example.com/demo"
          end
        G

        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )

        # Return non-GitHub url from git remote
        allow(IO).to receive(:popen).and_wrap_original do |m, *args, &blk|
          if Array(args.first).take(4) == ["git", "-C", project_root.to_s, "remote"]
            StringIO.new("https://gitlab.example.com/acme/demo.git\n")
          else
            m.call(*args, &blk)
          end
        end

        expect { described_class.run }.to raise_error { |e| expect([SystemExit, Kettle::Dev::Error]).to include(e.class) }
      end
    end

    it "updates homepage using origin when forced, or skips when declined" do
      Dir.mktmpdir do |project_root|
        gemspec = File.join(project_root, "demo.gemspec")
        File.write(gemspec, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.homepage = "'${ORG}'" # interpolated/invalid on purpose
          end
        G

        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )

        # GitHub origin
        allow(IO).to receive(:popen).and_wrap_original do |m, *args, &blk|
          if Array(args.first).take(4) == ["git", "-C", project_root.to_s, "remote"]
            StringIO.new("https://github.com/acme/demo.git\n")
          else
            m.call(*args, &blk)
          end
        end

        # Case 1: forced update
        stub_env("force" => "true")
        described_class.run
        expect(File.read(gemspec)).to match(/spec.homepage\s*=\s*"https:\/\/github.com\/acme\/demo"/)

        # Case 2: decline
        File.write(gemspec, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.homepage = "http://example.com/demo"
          end
        G
        stub_env("force" => nil)
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("n\n")
        described_class.run
        expect(File.read(gemspec)).to include("http://example.com/demo")
      end
    end

    it "aborts after updating .envrc unless allowed=true" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          ask: true,
          template_results: {},
        )

        # Ensure origin check doesn't abort: provide a gemspec with a valid homepage to avoid touching git
        File.write(File.join(project_root, "demo.gemspec"), <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.homepage = "https://github.com/acme/demo"
          end
        G

        # No allowed set, so after updating .envrc the task should abort
        expect { described_class.run }.to raise_error { |e| expect([SystemExit, Kettle::Dev::Error]).to include(e.class) }
      end
    end

    it "prints summary of templating changes and handles errors in summary" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive(:project_root).and_return(project_root)
        allow(helpers).to receive(:modified_by_template?).and_return(false)

        # First run: provide meaningful template results across action types
        allow(helpers).to receive(:template_results).and_return({
          File.join(project_root, "a.txt") => {action: :create, timestamp: Time.now},
          File.join(project_root, "b.txt") => {action: :replace, timestamp: Time.now},
          File.join(project_root, "dir1") => {action: :dir_create, timestamp: Time.now},
          File.join(project_root, "dir2") => {action: :dir_replace, timestamp: Time.now},
        })

        expect { described_class.run }.not_to raise_error

        # Second run: force an error when fetching summary
        allow(helpers).to receive(:template_results).and_raise(StandardError, "nope")
        expect { described_class.run }.not_to raise_error
      end
    end

    it "offers to remove .ruby-version and .ruby-gemset when .tool-versions exists and removes them on accept", :check_output do
      Dir.mktmpdir do |project_root|
        File.write(File.join(project_root, ".tool-versions"), "ruby 3.3.0\n")
        rv = File.join(project_root, ".ruby-version")
        rg = File.join(project_root, ".ruby-gemset")
        File.write(rv, "3.3.0\n")
        File.write(rg, "gemset\n")

        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: true, # skip .envrc path
          ask: true,
          template_results: {},
        )

        described_class.run
        expect(File).not_to exist(rv)
        expect(File).not_to exist(rg)
      end
    end

    it "rescues read error for .envrc and proceeds (line 60)" do
      Dir.mktmpdir do |project_root|
        envrc = File.join(project_root, ".envrc")
        File.write(envrc, "whatever")

        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          ask: false, # skip writing
          template_results: {},
        )

        allow(File).to receive(:read).and_wrap_original do |m, path|
          if path == envrc
            raise StandardError, "nope"
          else
            m.call(path)
          end
        end

        expect { described_class.run }.not_to raise_error
      end
    end

    it "prepends PATH_add bin to non-empty .envrc content (line 73)" do
      Dir.mktmpdir do |project_root|
        envrc = File.join(project_root, ".envrc")
        File.write(envrc, "export FOO=bar\n")
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          ask: true,
          template_results: {},
        )
        stub_env("allowed" => "true")
        described_class.run
        txt = File.read(envrc)
        expect(txt).to start_with("# Run any command in this project's bin/ without the bin/ prefix\nPATH_add bin\n\n")
        expect(txt).to include("export FOO=bar")
      end
    end

    it "rescues read error for .gitignore (line 98) and still proceeds" do
      Dir.mktmpdir do |project_root|
        gi = File.join(project_root, ".gitignore")
        File.write(gi, "")
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )
        allow(File).to receive(:read).and_wrap_original do |m, path|
          if path == gi
            raise StandardError, "boom"
          else
            m.call(path)
          end
        end
        # Decline prompt so we don't write
        allow($stdin).to receive(:gets).and_return("n\n")
        expect { described_class.run }.not_to raise_error
      end
    end

    it "handles exception when reading git origin (line 194) and aborts due to missing GitHub" do
      Dir.mktmpdir do |project_root|
        gemspec = File.join(project_root, "demo.gemspec")
        File.write(gemspec, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.homepage = "http://example.com/demo"
          end
        G
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )
        allow(IO).to receive(:popen).and_raise(StandardError, "no git")
        expect { described_class.run }.to raise_error { |e| expect([SystemExit, Kettle::Dev::Error]).to include(e.class) }
      end
    end

    it "rescues unexpected error during gemspec homepage check and warns (line 235)" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: true, # skip envrc
          template_results: {},
        )
        allow(Dir).to receive(:glob).and_raise(StandardError, "kaboom")
        expect { described_class.run }.not_to raise_error
      end
    end

    it "parses quoted literal GitHub homepage (line 173) without update" do
      Dir.mktmpdir do |project_root|
        gemspec = File.join(project_root, "demo.gemspec")
        File.write(gemspec, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.homepage = "'https://github.com/acme/demo'"
          end
        G
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: false,
          template_results: {},
        )
        expect { described_class.run }.not_to raise_error
        expect(File.read(gemspec)).to include("'https://github.com/acme/demo'")
      end
    end

    it "rescues when computing relative path during summary (line 279)" do
      Dir.mktmpdir do |project_root|
        allow(helpers).to receive(:project_root).and_return(project_root)
        allow(helpers).to receive(:modified_by_template?).and_return(true)
        # Include a nil key to trigger NoMethodError in start_with?
        allow(helpers).to receive(:template_results).and_return({
          nil => {action: :create, timestamp: Time.now},
        })
        expect { described_class.run }.not_to raise_error
      end
    end

    # New tests: grapheme synchronization between README H1 and gemspec
    it "replaces mismatched grapheme and enforces single space in README and gemspec" do
      Dir.mktmpdir do |project_root|
        # README with a different emoji
        File.write(File.join(project_root, "README.md"), "# 🍕  My Library\n\nText\n")
        # Gemspec with different leading emoji and extra spaces
        gemspec = File.join(project_root, "demo.gemspec")
        File.write(gemspec, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.summary = "🍲  A tasty lib"
            spec.description = "🍲  Delicious things" \
              " and more"
            spec.homepage = "https://github.com/acme/demo"
          end
        G
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: true,
          template_results: {},
        )
        described_class.run
        # README H1 normalized: single 🍕 and single space
        readme = File.read(File.join(project_root, "README.md"))
        expect(readme.lines.first).to eq("# 🍕 My Library\n")
        # Gemspec summary/description start with 🍕 and single space
        txt = File.read(gemspec)
        expect(txt).to match(/spec.summary\s*=\s*"🍕 A tasty lib"/)
        expect(txt).to match(/spec.description\s*=\s*"🍕 Delicious things"/)
      end
    end

    it "inserts user-provided grapheme when README H1 has none" do
      Dir.mktmpdir do |project_root|
        File.write(File.join(project_root, "README.md"), "# My Library\n")
        gemspec = File.join(project_root, "demo.gemspec")
        File.write(gemspec, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.summary = "A lib"
            spec.description = "Awesome" \
              " stuff"
            spec.homepage = "https://github.com/acme/demo"
          end
        G
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: true,
          template_results: {},
        )
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("🚀\n")
        described_class.run
        readme = File.read(File.join(project_root, "README.md"))
        expect(readme.lines.first).to eq("# 🚀 My Library\n")
        txt = File.read(gemspec)
        expect(txt).to match(/spec.summary\s*=\s*"🚀 A lib"/)
        expect(txt).to match(/spec.description\s*=\s*"🚀 Awesome"/)
      end
    end

    it "does nothing when user provides empty grapheme input" do
      Dir.mktmpdir do |project_root|
        File.write(File.join(project_root, "README.md"), "# Title\n")
        gemspec = File.join(project_root, "demo.gemspec")
        File.write(gemspec, <<~G)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.summary = "Sum"
            spec.description = "Desc" \
              " tail"
            spec.homepage = "https://github.com/acme/demo"
          end
        G
        allow(helpers).to receive_messages(
          project_root: project_root,
          modified_by_template?: true,
          template_results: {},
        )
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("\n")
        described_class.run
        # unchanged
        expect(File.read(File.join(project_root, "README.md"))).to start_with("# Title\n")
        t = File.read(gemspec)
        expect(t).to include('spec.summary = "Sum"')
        expect(t).to include('spec.description = "Desc"')
      end
    end
  end

  describe "::task_abort" do
    it "aborts with SystemExit in a subprocess without RSpec loaded (line 14)" do
      require "open3"
      cmd = %(ruby -e "require './lib/kettle/dev/tasks/install_task'; Kettle::Dev::Tasks::InstallTask.task_abort('boom')")
      stdout, stderr, status = Open3.capture3(cmd)
      expect(status.success?).to be false
      expect(stdout + stderr).to include("boom")
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/VerifiedDoubles, RSpec/ReceiveMessages
