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

    it "accepts --refresh-cache and --cache-path" do
      cache_path = File.join(workflow_root, "gha-cache.json")
      cli = described_class.new(["--root", workflow_root, "--refresh-cache", "--cache-path", cache_path])

      cli.send(:parse!)

      options = cli.instance_variable_get(:@options)
      expect(options[:refresh_cache]).to be(true)
      expect(options[:cache_path]).to eq(cache_path)
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
      expect(plan[:latest_outdated][:version]).to eq("2.0.0")
    end

    it "parses release tags and matches version-like values" do
      expect(dummy_cli.send(:parse_release_version, "v1.2.3")).to eq(Gem::Version.new("1.2.3"))
      expect(dummy_cli.send(:parse_release_version, "bad-tag")).to be_nil
    end

    it "falls back to source scanning for Psych nodes without location APIs" do
      text = <<~YAML
        jobs:
          test:
            steps:
              - uses: foo/bar@v1.2.0
      YAML

      expect(dummy_cli.send(:fallback_uses_location, text, "foo/bar@v1.2.0", {})).to eq([3, 14])
    end

    it "reports higher-version outdated info even when patch is the write target" do
      plan = dummy_cli.send(:determine_upgrade_plan, old_ref: "v1.2.0", repo_ref: "foo/bar", versions: versions, upgrade_level: "patch", client: client)

      expect(plan[:updates][:version]).to eq("1.2.3")
      expect(plan[:latest_outdated][:version]).to eq("2.0.0")
      expect(plan[:is_outdated]).to be(true)
    end

    it "does not treat a version-equivalent but unresolved ref as a valid release tag" do
      allow(client).to receive(:commit_sha).with("foo/bar", "1.2.3").and_return(nil)

      plan = dummy_cli.send(:determine_upgrade_plan, old_ref: "1.2.3", repo_ref: "foo/bar", versions: versions, upgrade_level: "patch", client: client)

      expect(plan[:updates]).to include(sha: "aaa", version: nil, reason: described_class::NON_SHA_REASON)
      expect(plan[:current_version]).to eq("1.2.3")
      expect(plan[:is_outdated]).to be(true)
    end
  end

  describe described_class::GitHubClient do
    it "loads release tag SHAs through matching refs instead of resolving every release commit" do
      client = described_class.new(token: nil, api_base: Kettle::Dev::GhaShaPinsCLI::API_BASE, user_agent: "kettle-gha-sha-pins")
      releases = [
        {"tag_name" => "v1.2.0", "prerelease" => false},
        {"tag_name" => "v1.3.0", "prerelease" => false}
      ]
      refs = [
        {"ref" => "refs/tags/v1.2.0", "object" => {"type" => "commit", "sha" => "a" * 40}},
        {"ref" => "refs/tags/v1.3.0", "object" => {"type" => "commit", "sha" => "b" * 40}}
      ]
      allow(client).to receive(:request_json).with("/repos/foo/bar/releases?per_page=100").and_return(releases)
      allow(client).to receive(:request_json).with("/repos/foo/bar/git/matching-refs/tags/").and_return(refs)
      expect(client).not_to receive(:commit_sha)

      versions = client.versions_for_repo("foo/bar")

      expect(versions.map { |entry| entry[:sha] }).to contain_exactly("a" * 40, "b" * 40)
    end

    it "uses fresh persistent cache entries without GitHub API calls" do
      cache = Kettle::Dev::GhaShaPinsCLI::PersistentActionCache.new(
        path: File.join(workflow_root, "gha-cache.json"),
        clock: -> { Time.utc(2026, 6, 8, 12, 0, 0) }
      )
      cache.write_versions(
        "foo/bar",
        [
          {tag: "v1.2.3", version_obj: Gem::Version.new("1.2.3"), version: "1.2.3", sha: "a" * 40},
          {tag: "v1.3.0", version_obj: Gem::Version.new("1.3.0"), version: "1.3.0", sha: "b" * 40},
          {tag: "v2.0.0", version_obj: Gem::Version.new("2.0.0"), version: "2.0.0", sha: "c" * 40}
        ]
      )
      client = described_class.new(
        token: nil,
        api_base: Kettle::Dev::GhaShaPinsCLI::API_BASE,
        user_agent: "kettle-gha-sha-pins",
        persistent_cache: cache
      )
      expect(client).not_to receive(:request_json)

      versions = client.versions_for_repo("foo/bar")

      expect(versions.map { |entry| entry[:version] }).to eq(%w[2.0.0 1.3.0 1.2.3])
    end

    it "bypasses fresh cache when refreshing and preserves unrelated cached actions" do
      cache_path = File.join(workflow_root, "gha-cache.json")
      cache = Kettle::Dev::GhaShaPinsCLI::PersistentActionCache.new(path: cache_path, clock: -> { Time.utc(2026, 6, 8, 12, 0, 0) })
      cache.write_versions(
        "other/action",
        [{tag: "v9.0.0", version_obj: Gem::Version.new("9.0.0"), version: "9.0.0", sha: "9" * 40}]
      )
      cache.write_versions(
        "foo/bar",
        [{tag: "v1.2.0", version_obj: Gem::Version.new("1.2.0"), version: "1.2.0", sha: "a" * 40}]
      )
      client = described_class.new(
        token: nil,
        api_base: Kettle::Dev::GhaShaPinsCLI::API_BASE,
        user_agent: "kettle-gha-sha-pins",
        persistent_cache: Kettle::Dev::GhaShaPinsCLI::PersistentActionCache.new(path: cache_path, clock: -> { Time.utc(2026, 6, 8, 12, 5, 0) }),
        refresh_cache: true
      )
      allow(client).to receive(:request_json).with("/repos/foo/bar/releases?per_page=100").and_return([
        {"tag_name" => "v1.2.3", "prerelease" => false},
        {"tag_name" => "v1.3.0", "prerelease" => false},
        {"tag_name" => "v2.0.0", "prerelease" => false}
      ])
      allow(client).to receive(:request_json).with("/repos/foo/bar/git/matching-refs/tags/").and_return([
        {"ref" => "refs/tags/v1.2.3", "object" => {"type" => "commit", "sha" => "b" * 40}},
        {"ref" => "refs/tags/v1.3.0", "object" => {"type" => "commit", "sha" => "c" * 40}},
        {"ref" => "refs/tags/v2.0.0", "object" => {"type" => "commit", "sha" => "d" * 40}}
      ])

      versions = client.versions_for_repo("foo/bar")
      cached = JSON.parse(File.read(cache_path))

      expect(versions.map { |entry| entry[:version] }).to eq(%w[2.0.0 1.3.0 1.2.3])
      expect(cached.fetch("actions")).to include("other/action")
      expect(cached.dig("actions", "foo/bar", "versions")).to include("1.2.0", "1.2.3", "1.3.0", "2.0.0")
      expect(cached.dig("actions", "foo/bar", "targets", "patch", "1.2", "version")).to eq("1.2.3")
      expect(cached.dig("actions", "foo/bar", "targets", "minor", "1", "version")).to eq("1.3.0")
      expect(cached.dig("actions", "foo/bar", "targets", "major", "*", "version")).to eq("2.0.0")
    end

    it "refreshes stale persistent cache entries after the TTL" do
      cache_path = File.join(workflow_root, "gha-cache.json")
      Kettle::Dev::GhaShaPinsCLI::PersistentActionCache.new(
        path: cache_path,
        clock: -> { Time.utc(2026, 6, 7, 11, 59, 0) }
      ).write_versions(
        "foo/bar",
        [{tag: "v1.2.0", version_obj: Gem::Version.new("1.2.0"), version: "1.2.0", sha: "a" * 40}]
      )
      client = described_class.new(
        token: nil,
        api_base: Kettle::Dev::GhaShaPinsCLI::API_BASE,
        user_agent: "kettle-gha-sha-pins",
        persistent_cache: Kettle::Dev::GhaShaPinsCLI::PersistentActionCache.new(path: cache_path, clock: -> { Time.utc(2026, 6, 8, 12, 0, 1) })
      )
      allow(client).to receive(:request_json).with("/repos/foo/bar/releases?per_page=100").and_return([
        {"tag_name" => "v1.2.1", "prerelease" => false}
      ])
      allow(client).to receive(:request_json).with("/repos/foo/bar/git/matching-refs/tags/").and_return([
        {"ref" => "refs/tags/v1.2.1", "object" => {"type" => "commit", "sha" => "b" * 40}}
      ])

      versions = client.versions_for_repo("foo/bar")

      expect(versions.map { |entry| entry[:version] }).to eq(["1.2.1"])
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
          "new_ref" => "ccc",
          "new_version" => "2.0.0",
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

    it "rewrites unresolved version-equivalent refs to release SHAs instead of stripped tag names" do
      File.write(
        workflow_path,
        <<~YAML
          name: ci
          on: [push]
          jobs:
            test:
              runs-on: ubuntu-latest
              steps:
                - uses: foo/bar@1.2.0 # v1.2.0
        YAML
      )
      cli_client = instance_double(described_class::GitHubClient)
      allow(described_class::GitHubClient).to receive(:new).and_return(cli_client)
      allow(cli_client).to receive(:versions_for_repo).with("foo/bar").and_return(client_versions)
      allow(cli_client).to receive(:commit_sha).with("foo/bar", "1.2.0").and_return(nil)

      cli = described_class.new(["--root", workflow_root, "--upgrade", "patch", "--write"])
      cli.run!

      expect(File.read(workflow_path)).to include("uses: foo/bar@aaa # v1.2.0")
      expect(File.read(workflow_path)).not_to include("foo/bar@1.2.0")
    end

    it "updates adjacent version comments when upgrading to a newer release SHA" do
      File.write(
        workflow_path,
        <<~YAML
          name: ci
          on: [push]
          jobs:
            test:
              runs-on: ubuntu-latest
              steps:
                - uses: foo/bar@aaa # v1.2.0
        YAML
      )
      cli_client = instance_double(described_class::GitHubClient)
      allow(described_class::GitHubClient).to receive(:new).and_return(cli_client)
      allow(cli_client).to receive(:versions_for_repo).with("foo/bar").and_return(client_versions)
      allow(cli_client).to receive(:commit_sha).with("foo/bar", "aaa").and_return("aaa")

      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor", "--write"])
      cli.run!

      expect(File.read(workflow_path)).to include("uses: foo/bar@bbb # v1.3.0")
      expect(File.read(workflow_path)).not_to include("# v1.2.0")
    end

    it "updates stale version comments even when the SHA is already current" do
      File.write(
        workflow_path,
        <<~YAML
          name: ci
          on: [push]
          jobs:
            test:
              runs-on: ubuntu-latest
              steps:
                - uses: foo/bar@bbb # v1.2.0
        YAML
      )
      cli_client = instance_double(described_class::GitHubClient)
      allow(described_class::GitHubClient).to receive(:new).and_return(cli_client)
      allow(cli_client).to receive(:versions_for_repo).with("foo/bar").and_return(client_versions)
      allow(cli_client).to receive(:commit_sha).with("foo/bar", "bbb").and_return("bbb")

      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor", "--write"])
      cli.run!

      expect(File.read(workflow_path)).to include("uses: foo/bar@bbb # v1.3.0")
      expect(File.read(workflow_path)).not_to include("# v1.2.0")
    end

    it "calls GitHub release-version lookup for each workflow action when evaluating pins" do
      cli_client = instance_double(described_class::GitHubClient)
      allow(described_class::GitHubClient).to receive(:new).and_return(cli_client)
      expect(cli_client).to receive(:versions_for_repo).with("foo/bar").and_return(client_versions)
      allow(cli_client).to receive(:commit_sha).and_return("aaa")

      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor"])
      cli.run!
    end

    it "reuses one resolution plan for duplicate action repos" do
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
                - uses: foo/bar@v1.2.0
        YAML
      )
      cli_client = instance_double(described_class::GitHubClient)
      allow(described_class::GitHubClient).to receive(:new).and_return(cli_client)
      expect(cli_client).to receive(:versions_for_repo).with("foo/bar").once.and_return(client_versions)
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
      expect(err.string).to include("Resolved foo/bar@v1.2.0 in")
    end

    it "keeps progress disabled by default for JSON output" do
      err = StringIO.new
      cli = described_class.new(["--root", workflow_root, "--upgrade", "minor", "--json"], err: err)

      cli.run!

      expect(err.string).to eq("")
    end
  end
end
