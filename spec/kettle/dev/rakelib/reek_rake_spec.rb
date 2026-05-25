# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "rake reek:update" do
  include_context "with rake", "reek"

  def status(success, exitstatus)
    instance_double(Process::Status, success?: success, exitstatus: exitstatus)
  end

  around do |example|
    tmp_root = File.expand_path("../../../../tmp", __dir__)
    FileUtils.mkdir_p(tmp_root)
    Dir.mktmpdir("kettle-dev-reek-rake", tmp_root) do |root|
      Dir.chdir(root) { example.run }
    end
  end

  it "writes the REEK file by resolving the gem executable directly" do
    reek_executable = "/gems/reek/exe/reek"
    allow(Gem).to receive(:bin_path).with("reek", "reek").and_return(reek_executable)
    allow(Open3).to receive(:capture2e)
      .with(RbConfig.ruby, reek_executable)
      .and_return(["smells\n", status(false, 1)])

    invoke

    expect(File.read("REEK")).to eq("smells\n")
  end

  it "fails when the reek executable exits for a reason other than smells" do
    allow(Gem).to receive(:bin_path).with("reek", "reek").and_return("/gems/reek/exe/reek")
    allow(Open3).to receive(:capture2e).and_return(["usage error\n", status(false, 2)])

    expect { invoke }.to raise_error(SystemExit)
    expect(File.read("REEK")).to eq("usage error\n")
  end
end
