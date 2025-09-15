# frozen_string_literal: true

# rubocop:disable ThreadSafety/DirChdir

RSpec.describe Kettle::Dev::SetupCLI do
  include_context "with stubbed env"

  before do
    require "kettle/dev"
  end

  describe "#derive_funding_org_from_git_if_missing!" do
    before do
      ENV.delete("FUNDING_ORG")
      ENV.delete("OPENCOLLECTIVE_HANDLE")
    end
    after do
      ENV.delete("FUNDING_ORG")
      ENV.delete("OPENCOLLECTIVE_HANDLE")
    end
    around do |ex|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) { ex.run }
      end
    end

    def build_cli
      described_class.allocate
    end

    it "returns early when .opencollective.yml has org" do
      File.write(".opencollective.yml", "org: cool-co\n")
      cli = build_cli
      # Provide a git adapter that would otherwise set the env if called
      fake_ga = instance_double(Kettle::Dev::GitAdapter)
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake_ga)
      allow(fake_ga).to receive(:clean?).and_return(true)
      allow(fake_ga).to receive(:remote_url).and_return("git@github.com:acme/thing.git")

      cli.send(:derive_funding_org_from_git_if_missing!)

      expect(ENV["FUNDING_ORG"]).to be_nil
    end

    it "logs debug when reading .opencollective.yml fails", :check_output do
      stub_env("DEBUG" => "true")
      oc = File.join(Dir.pwd, ".opencollective.yml")
      # Create file and then force File.read to raise for this specific path
      File.write(oc, "org: nope\n")
      cli = build_cli
      allow(File).to receive(:read).and_wrap_original do |orig, path|
        if path == oc
          raise IOError, "boom"
        else
          orig.call(path)
        end
      end
      expect { cli.send(:derive_funding_org_from_git_if_missing!) }
        .to output(/Reading \.opencollective\.yml failed: IOError: boom/).to_stderr
    end

    it "uses remotes_with_urls when remote_url is unavailable and sets FUNDING_ORG from origin" do
      fake_ga = Object.new
      def fake_ga.respond_to?(m); m == :remotes_with_urls; end
      allow(fake_ga).to receive(:remotes_with_urls).and_return({"origin" => "https://github.com/example/repo.git"})
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake_ga)

      cli = build_cli
      cli.send(:derive_funding_org_from_git_if_missing!)

      expect(ENV["FUNDING_ORG"]).to eq("example")
    end

    it "logs debug when remotes_with_urls raises and otherwise continues silently", :check_output do
      stub_env("DEBUG" => "true")
      fake_ga = Object.new
      def fake_ga.respond_to?(m); m == :remotes_with_urls; end
      allow(fake_ga).to receive(:remotes_with_urls).and_raise(StandardError, "bad remote")
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_return(fake_ga)

      cli = build_cli
      expect { cli.send(:derive_funding_org_from_git_if_missing!) }
        .to output(/remotes_with_urls failed: StandardError: bad remote/).to_stderr
      expect(ENV["FUNDING_ORG"]).to be_nil
    end

    it "swallows unexpected adapter errors and logs debug (outer rescue)", :check_output do
      stub_env("DEBUG" => "true")
      allow(Kettle::Dev::GitAdapter).to receive(:new).and_raise(RuntimeError, "kaput")
      cli = build_cli
      expect { cli.send(:derive_funding_org_from_git_if_missing!) }
        .to output(/Could not derive funding org from git: RuntimeError: kaput/).to_stderr
    end
  end
end
# rubocop:enable ThreadSafety/DirChdir
