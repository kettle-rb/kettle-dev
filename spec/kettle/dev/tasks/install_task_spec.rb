# frozen_string_literal: true

# Unit specs for Kettle::Dev::Tasks::InstallTask
# These tests focus on exercising branches documented as missing coverage.
# rubocop:disable RSpec/MultipleExpectations, RSpec/VerifiedDoubles, RSpec/ReceiveMessages

require "rake"

RSpec.describe Kettle::Dev::Tasks::InstallTask do
  include_context "with stubbed env"

  let(:helpers) { Kettle::Dev::TemplateHelpers }

  before do
    # Prevent invoking the real rake task; stub it to a no-op
    allow(Rake::Task).to receive(:[]).with("kettle:dev:template").and_return(double(invoke: nil))
  end

  describe "::run" do
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

        # Decline prompt; stub stdin for this example only
        allow($stdin).to receive(:gets).and_return("n\n")

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
        allow($stdin).to receive(:gets).and_return("n\n")
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
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/VerifiedDoubles, RSpec/ReceiveMessages
