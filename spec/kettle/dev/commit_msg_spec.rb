# frozen_string_literal: true

# rubocop:disable RSpec/AnyInstance, RSpec/MultipleExpectations

require "tmpdir"
require "fileutils"

RSpec.describe Kettle::Dev::CommitMsg do
  include_context "with stubbed env"

  let(:path) { File.join(Dir.mktmpdir, "COMMIT_EDITMSG") }

  before do
    File.write(path, "Initial commit\n\nBody\n")
  end

  after do
    FileUtils.rm_f(path)
  end

  def stub_branch(name)
    allow(Kernel).to receive(:`).and_call_original
    allow_any_instance_of(Object).to receive(:`).with("git branch 2> /dev/null | grep -e ^* | awk '{print $2}'").and_return("#{name}\n")
  end

  it "does nothing when validation is disabled by ENV" do
    stub_env("GIT_HOOK_BRANCH_VALIDATE" => "false")
    expect { described_class.enforce_branch_rule!(path) }.not_to change { File.read(path) }
  end

  it "appends footer when branch matches jira rule and id missing" do
    stub_env("GIT_HOOK_BRANCH_VALIDATE" => "jira")
    stub_branch("feature/12345678-awesome")
    described_class.enforce_branch_rule!(path)
    content = File.read(path)
    expect(content).to include("[feature][12345678]")
  end

  it "does not duplicate footer if id already present" do
    stub_env("GIT_HOOK_BRANCH_VALIDATE" => "jira")
    stub_branch("bug/12345678-fix")
    File.write(path, "feat: includes 12345678 already\n")
    expect { described_class.enforce_branch_rule!(path) }.not_to change { File.read(path) }
  end

  it "does nothing if branch does not match rule" do
    stub_env("GIT_HOOK_BRANCH_VALIDATE" => "jira")
    stub_branch("chore/no-ticket")
    expect { described_class.enforce_branch_rule!(path) }.not_to change { File.read(path) }
  end
end
# rubocop:enable RSpec/AnyInstance, RSpec/MultipleExpectations
