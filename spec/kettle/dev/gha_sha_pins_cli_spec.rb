# frozen_string_literal: true

require "json"
require "stringio"

# rubocop:disable RSpec/VerifiedDoubles, RSpec/MessageSpies, ThreadSafety/ClassInstanceVariable

RSpec.describe Kettle::Dev::GhaShaPinsCLI do
  let(:workflow_root) { Dir.mktmpdir }
  let(:workflow_path) { File.join(workflow_root, ".github", "workflows", "ci.yml") }

  before do
    FileUtils.mkdir_p(File.dirname(workflow_path))
    File.write(
      workflow_path,
      <<~YAML
        name: ci
        on: [push]
        jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - uses: foo/bar@v1.2.0
      YAML
    )
  end

  after do
    FileUtils.rm_rf(workflow_root)
  end

  def stub_github_client(versions:, commit_shas: {})
    allow_any_instance_of(described_class::GitHubClient).to receive(:versions_for_repo).and_return(versions)
    allow_any_instance_of(described_class::GitHubClient).to receive(:commit_sha) do |_client, _repo, ref|
      commit_shas[ref]
    end
  end

  describe "CLI options" do
    it "defaults --upgrade to patch" do
      cli = described_class.new(["--root", workflow_root])
      cli.send(:parse!)
      expect(cli.instance_variable_get(:@options)[:upgrade]).to eq("patch")
    end

    it "accepts major, minor, and patch for --upgrade", :real_exit_adapter do
      cli_major = described_class.new(["--upgrade", "major", "--root", workflow_root])
      cli_minor = described_class.new(["--upgrade", "minor", "--root", workflow_root])
      cli_patch = described_class.new(["--upgrade", "patch", "--root", workflow_root])

      expect { cli_major.send(:parse!) }.not_to raise_error
      expect(cli_major.instance_variable_get(:@options)[:upgrade]).to eq("major")

      expect { cli_minor.send(:parse!) }.not_to raise_error
      expect(cli_minor.instance_variable_get(:@options)[:upgrade]).to eq("minor")

      expect { cli_patch.send(:parse!) }.not_to raise_error
      expect(cli_patch.instance_variable_get(:@options)[:upgrade]).to eq("patch")
    end

    it "aborts on invalid --upgrade values", :real_exit_adapter do
      cli = described_class.new(["--upgrade", "garbage", "--root", workflow_root])

      expect { cli.send(:parse!) }.to raise_error(SystemExit)
    end
  end

  describe "upgrade planning helpers" do
    let(:versions) do
      [
        {
          tag: "v1.2.0",
          version_obj: Gem::Version.new("1.2.0"),
          version: "1.2.0",
          sha: "777"
        },
        {
          tag: "v1.3.0",
          version_obj: Gem::Version.new("1.3.0"),
          version: "1.3.0",
          sha: "999"
        },
        {
          tag: "v1.2.3",
          version_obj: Gem::Version.new("1.2.3"),
          version: "1.2.3",
          sha: "aaa"
        },
        {
          tag: "v2.0.0",
          version_obj: Gem::Version.new("2.0.0"),
          version: "2.0.0",
          sha: "bbb"
        }
      ]
    end

    let(:client) { described_class::GitHubClient.new(token: nil, api_base: described_class::API_BASE, user_agent: "kettle-gha-sha-pins") }
    let(:dummy_cli) { described_class.new(["--root", workflow_root]) }

    before do
      allow_any_instance_of(described_class::GitHubClient).to receive(:commit_sha).and_return("777")
    end

    it "selects minor-compatible upgrade target for minor strategy" do
      plan = dummy_cli.send(:determine_upgrade_plan, old_ref: "v1.2.0", repo_ref: "foo/bar", versions: versions, upgrade_level: "minor", client: client)
      expect(plan[:updates][:sha]).to eq("999")
      expect(plan[:updates][:version]).to eq("1.3.0")
      expect(plan[:reason]).to eq(described_class::UPGRADE_REASON)
      expect(plan[:current_version]).to eq("1.2.0")
      expect(plan[:is_outdated]).to be(true)
    end

    it "selects any higher version for major strategy" do
      plan = dummy_cli.send(:determine_upgrade_plan, old_ref: "v1.2.0", repo_ref: "foo/bar", versions: versions, upgrade_level: "major", client: client)
      expect(plan[:updates][:sha]).to eq("bbb")
      expect(plan[:updates][:version]).to eq("2.0.0")
      expect(plan[:reason]).to eq(described_class::UPGRADE_REASON)
    end

    it "selects latest patch for patch strategy" do
      plan = dummy_cli.send(:determine_upgrade_plan, old_ref: "v1.2.0", repo_ref: "foo/bar", versions: versions, upgrade_level: "patch", client: client)
      expect(plan[:updates][:sha]).to eq("aaa")
      expect(plan[:updates][:version]).to eq("1.2.3")
      expect(plan[:reason]).to eq(described_class::UPGRADE_REASON)
    end

    it "parses release tags and matches version-like values" do
      expect(dummy_cli.send(:parse_release_version, "v1.2.3")).to eq(Gem::Version.new("1.2.3"))
      expect(dummy_cli.send(:parse_release_version, "bad-tag")).to be_nil
    end
  end

  describe "run! output" do
    let(:client_versions) do
      [
        {
          tag: "v1.3.0",
          version_obj: Gem::Version.new("1.3.0"),
          version: "1.3.0",
          sha: "bbb"
        },
        {
          tag: "v2.0.0",
          version_obj: Gem::Version.new("2.0.0"),
          version: "2.0.0",
          sha: "ccc"
        },
        {
          tag: "v1.2.0",
          version_obj: Gem::Version.new("1.2.0"),
          version: "1.2.0",
          sha: "aaa"
        }
      ]
    end

    before do
      stub_github_client(
        versions: client_versions,
        commit_shas: {
          "v1.2.0" => "aaa",
          "v1.3.0" => "bbb",
          "v2.0.0" => "ccc"
        }
      )
    end

    it "emits JSON report with outdated_pins and version-equivalent values" do
      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor", "--json"])

      output = StringIO.new
      original_stdout = $stdout
      $stdout = output
      begin
        cli.run!
      ensure
        $stdout = original_stdout
      end

      payload = JSON.parse(output.string)
      expect(payload.fetch("outdated_pins")).to contain_exactly(
        a_hash_including(
          "path" => workflow_path,
          "line" => 7,
          "action" => "foo/bar",
          "old_ref" => "v1.2.0",
          "old_version" => "1.2.0",
          "new_ref" => "bbb",
          "new_version" => "1.3.0",
          "upgrade_level" => "minor",
          "reason" => described_class::UPGRADE_REASON
        )
      )
      expect(payload.fetch("planned_changes").first["old_version"]).to eq("1.2.0")
      expect(payload.fetch("planned_changes").first["new_version"]).to eq("1.3.0")
    end

    it "emits human text report with version-equivalent outdated pins summary" do
      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor"])

      expect do
        cli.run!
      end.to output(
        %r{Outdated actions \(1\):\nAction Current Latest Location Reason\nfoo/bar 1\.2\.0 1\.3\.0 #{Regexp.escape(workflow_path)}:\d+ #{Regexp.escape(described_class::UPGRADE_REASON)}}
      ).to_stdout
    end

    it "fails in check mode and recommends the write command when updates are needed" do
      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor", "--check"])

      expect do
        expect(cli.run!).to eq(3)
      end.to output(/Outdated actions \(1\):.*Recommended fix: kettle-gha-sha-pins --write --upgrade minor/m).to_stdout
    end

    it "calls GitHub release-version lookup for each workflow action when evaluating pins" do
      cli_client = instance_double(described_class::GitHubClient)
      allow(described_class::GitHubClient).to receive(:new).and_return(cli_client)
      expect(cli_client).to receive(:versions_for_repo).with("foo/bar").and_return(client_versions)
      allow(cli_client).to receive(:commit_sha).and_return("aaa")

      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor"])
      cli.run!
    end

    it "emits progress feedback to stderr for human output" do
      err = StringIO.new
      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor", "--no-progress"], err: err)
      expect(cli.run!).to eq(0)
      expect(err.string).to eq("")

      err = StringIO.new
      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor"], err: err)
      cli.run!

      expect(err.string).to include("Discovering workflow files")
      expect(err.string).to include("Discovered 1 workflow file")
      expect(err.string).to include("Resolving 1 GitHub action reference")
    end

    it "keeps progress disabled by default for JSON output" do
      err = StringIO.new
      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor", "--json"], err: err)

      cli.run!

      expect(err.string).to eq("")
    end
  end
end
