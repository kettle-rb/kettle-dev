# frozen_string_literal: true

RSpec.describe Kettle::Dev::ReleaseCLI do
  let(:cli) { described_class.new }

  before do
    allow(cli).to receive_messages(
      detect_gem_name: "example-gem",
      preferred_github_remote: "origin"
    )
    allow(cli).to receive(:remote_tag_exists?).with("origin", "v1.2.3").and_return(true)
    allow(cli).to receive(:extract_changelog_for_version).with("1.2.3").and_return(["## [1.2.3]", nil, nil])
    allow(Kettle::Dev::RubyGemsVersions).to receive(:fetch)
      .with("example-gem", version_hint: "1.2.3", refresh: true)
      .and_return([{"number" => "1.2.3"}])
    stub_env("GITHUB_TOKEN" => "token", "GH_TOKEN" => nil)
  end

  it "accepts a published version with a remote tag and changelog section" do
    result = cli.send(:github_release_backfill_check, "1.2.3")

    expect(result).to include(
      "ok" => true,
      "gem_name" => "example-gem",
      "tag" => "v1.2.3",
      "diagnostics" => []
    )
  end

  it "rejects a version that RubyGems.org does not publish" do
    allow(Kettle::Dev::RubyGemsVersions).to receive(:fetch).and_return([])

    result = cli.send(:github_release_backfill_check, "1.2.3")

    expect(result.fetch("ok")).to be(false)
    expect(result.fetch("diagnostics")).to include("RubyGems.org does not list example-gem 1.2.3")
  end

  it "rejects a missing remote tag rather than allowing GitHub to create one" do
    allow(cli).to receive(:remote_tag_exists?).with("origin", "v1.2.3").and_return(false)

    result = cli.send(:github_release_backfill_check, "1.2.3")

    expect(result.fetch("ok")).to be(false)
    expect(result.fetch("diagnostics")).to include('remote "origin" does not contain tag v1.2.3')
  end

  it "uses GH_TOKEN when GITHUB_TOKEN is absent" do
    stub_env("GITHUB_TOKEN" => nil, "GH_TOKEN" => "token")

    expect(cli.send(:github_release_token_configured?)).to be(true)
  end

  it "uses the configured family gem name without requiring a root gemspec" do
    stub_env("K_CHANGELOG_GEM_NAME" => "structuredmerge-ruby")
    allow(cli).to receive(:detect_gem_name).and_call_original

    expect(cli.send(:detect_gem_name)).to eq("structuredmerge-ruby")
  end

  it "uses the configured family changelog path for release notes" do
    Dir.mktmpdir("kettle-release-changelog") do |dir|
      path = File.join(dir, "CHANGELOG.md")
      File.write(path, "## [1.2.3]\n\n- Family release.\n")
      stub_env("K_CHANGELOG_PATH" => path)
      allow(cli).to receive(:extract_changelog_for_version).and_call_original

      section, compare_ref, tag_ref = cli.send(:extract_changelog_for_version, "1.2.3")

      expect(section).to include("Family release.")
      expect(compare_ref).to be_nil
      expect(tag_ref).to be_nil
    end
  end

  it "updates an existing release from its changelog section" do
    allow(cli).to receive(:remote_url).with("origin").and_return("git@github.com:acme/example-gem.git")
    allow(cli).to receive(:extract_changelog_for_version).with("1.2.3")
      .and_return(["## [1.2.3]\n\n- Release notes.\n", "[1.2.3]: compare\n", "[1.2.3t]: tag\n"])
    allow(cli).to receive(:github_update_release).and_return([true, "updated"])

    result = cli.send(:maybe_update_github_release!, "1.2.3")

    expect(result).to eq([true, "updated"])
    expect(cli).to have_received(:github_update_release).with(hash_including(
      owner: "acme",
      repo: "example-gem",
      token: "token",
      tag: "v1.2.3",
      title: "v1.2.3",
      body: a_string_including("## [1.2.3]\n\n- Release notes.\n\n[1.2.3]: compare\n[1.2.3t]: tag\n")
    ))
  end
end
