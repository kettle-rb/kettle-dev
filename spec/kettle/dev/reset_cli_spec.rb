# frozen_string_literal: true

require "tmpdir"

RSpec.describe Kettle::Dev::ResetCLI do
  around do |example|
    Dir.mktmpdir("kettle-dev-reset-cli-spec") do |dir|
      @root = dir
      example.run
    end
  end

  it "checks Gemfile.lock without changing it" do
    File.write(File.join(@root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
          rake (13.4.2)

      CHECKSUMS
        rake (13.4.2)
        thor (1.4.0) sha256=abc123
    LOCK

    cli = described_class.new(%w[--check Gemfile.lock], root: @root)

    expect { cli.run! }.to raise_error(Kettle::Dev::Error, /Gemfile.lock is not reset/)
  end

  it "resets Gemfile.lock" do
    cli = described_class.new(%w[Gemfile.lock], root: @root)
    resetter = instance_double(Kettle::Dev::LockfileReset)
    path = File.join(@root, "Gemfile.lock")
    allow(Kettle::Dev::LockfileReset).to receive(:new).and_return(resetter)
    allow(resetter).to receive(:lockfile_paths_for).with("Gemfile.lock").and_return([path])
    allow(resetter).to receive(:release_lockfiles_target?).with("Gemfile.lock").and_return(false)
    allow(resetter).to receive(:normalization_needed?).with(path).and_return(true)
    allow(resetter).to receive(:reset).with("Gemfile.lock", skip_changelog_dependency: false).and_return(path)

    expect(cli.run!).to eq(0)
  end

  it "does not rewrite an already reset Gemfile.lock" do
    cli = described_class.new(%w[Gemfile.lock], root: @root)
    resetter = instance_double(Kettle::Dev::LockfileReset)
    path = File.join(@root, "Gemfile.lock")
    allow(Kettle::Dev::LockfileReset).to receive(:new).and_return(resetter)
    allow(resetter).to receive(:lockfile_paths_for).with("Gemfile.lock").and_return([path])
    allow(resetter).to receive(:release_lockfiles_target?).with("Gemfile.lock").and_return(false)
    allow(resetter).to receive(:normalization_needed?).with(path).and_return(false)

    expect(resetter).not_to receive(:reset)
    expect(cli.run!).to eq(0)
  end

  it "always rewrites release lockfiles" do
    cli = described_class.new(%w[release-lockfiles], root: @root)
    resetter = instance_double(Kettle::Dev::LockfileReset)
    path = File.join(@root, "Gemfile.lock")
    allow(Kettle::Dev::LockfileReset).to receive(:new).and_return(resetter)
    allow(resetter).to receive(:lockfile_paths_for).with("release-lockfiles").and_return([path])
    allow(resetter).to receive(:release_lockfiles_target?).with("release-lockfiles").and_return(true)
    allow(resetter).to receive(:reset).with("release-lockfiles", skip_changelog_dependency: false).and_return([path])

    expect(cli.run!).to eq(0)
  end

  it "omits the optional changelog dependency when requested" do
    cli = described_class.new(%w[--skip-changelog-dependency release-lockfiles], root: @root)
    resetter = instance_double(Kettle::Dev::LockfileReset)
    path = File.join(@root, "Gemfile.lock")
    allow(Kettle::Dev::LockfileReset).to receive(:new).and_return(resetter)
    allow(resetter).to receive(:lockfile_paths_for).with("release-lockfiles").and_return([path])
    allow(resetter).to receive(:release_lockfiles_target?).with("release-lockfiles").and_return(true)
    allow(resetter).to receive(:reset).with("release-lockfiles", skip_changelog_dependency: true).and_return([path])

    expect(cli.run!).to eq(0)
  end
end
