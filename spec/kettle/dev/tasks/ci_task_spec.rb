# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, RSpec/StubbedMock, RSpec/MessageSpies, RSpec/ReceiveMessages

require "tmpdir"
require "fileutils"

RSpec.describe Kettle::Dev::Tasks::CITask do
  include_context "with stubbed env"

  def http_ok_with(body_hash)
    instance_double(Net::HTTPOK, is_a?: true, body: JSON.dump(body_hash), code: "200")
  end

  before do
    # Default stubs for git/repo context used by the task
    allow(Kettle::Dev::CIHelpers).to receive(:current_branch).and_return("main")
    allow(Kettle::Dev::CIHelpers).to receive(:repo_info).and_return(["acme", "demo"])
    allow(Kettle::Dev::CIHelpers).to receive(:default_token).and_return(nil)

    # Avoid dependence on tty rendering in tests
    allow($stdout).to receive(:tty?).and_return(false)

    # Upstream and HEAD sha lookups used in interactive menu
    allow(Open3).to receive(:capture2) do |*args|
      if args == ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]
        ["origin/main\n", instance_double(Process::Status, success?: true)]
      elsif args == ["git", "rev-parse", "--short", "HEAD"]
        ["abc123\n", instance_double(Process::Status, success?: true)]
      else
        ["", instance_double(Process::Status, success?: false)]
      end
    end

    # Default GitHub API stub: return a completed successful run so polling ends quickly
    allow(Net::HTTP).to receive(:start).and_return(
      http_ok_with({"workflow_runs" => [{"status" => "completed", "conclusion" => "success", "id" => 1, "html_url" => "https://x/y"}]}),
    )
  end

  def with_workflows(files)
    Dir.mktmpdir do |root|
      dir = File.join(root, ".github", "workflows")
      FileUtils.mkdir_p(dir)
      files.each do |name|
        File.write(File.join(dir, name), "name: test\n")
      end
      allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
      yield(root, dir)
    end
  end

  describe "::act (non-interactive option)" do
    it "runs act for a short code mapping" do
      with_workflows(["ci.yml", "style.yaml"]) do |root, dir|
        file_path = File.join(dir, "ci.yml")
        expect(File).to exist(file_path)
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        require "kettle/dev/tasks/ci_task"
        expect { described_class.act("ci") }.not_to raise_error
      end
    end

    it "runs act for an explicit filename with extension" do
      with_workflows(["ci.yml", "style.yaml"]) do |_root, dir|
        file_path = File.join(dir, "style.yaml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        require "kettle/dev/tasks/ci_task"
        expect { described_class.act("style.yaml") }.not_to raise_error
      end
    end

    it "resolves a basename without extension when .yaml exists" do
      with_workflows(["style.yaml"]) do |_root, dir|
        file_path = File.join(dir, "style.yaml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        require "kettle/dev/tasks/ci_task"
        expect { described_class.act("style") }.not_to raise_error
      end
    end

    it "aborts and lists available options when workflow file is missing", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        require "kettle/dev/tasks/ci_task"
        expect do
          described_class.act("bogus")
        end.to raise_error(SystemExit, /ci:act aborted/)
      end
    end
  end

  describe "::act (interactive)" do
    it "quits when user enters 'q'", :check_output do
      with_workflows(["ci.yml", "style.yaml"]) do |_root, dir|
        allow($stdin).to receive(:gets).and_return("q\n")
        # Should not run system at all
        expect(described_class).not_to receive(:system)
        require "kettle/dev/tasks/ci_task"
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "runs act for numeric selection 1", :check_output do
      with_workflows(["ci.yml", "style.yaml"]) do |_root, dir|
        allow($stdin).to receive(:gets).and_return("1\n")
        file_path = File.join(dir, "ci.yml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        require "kettle/dev/tasks/ci_task"
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "aborts for unknown code", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow($stdin).to receive(:gets).and_return("zzz\n")
        require "kettle/dev/tasks/ci_task"
        expect { described_class.act(nil) }.to raise_error(SystemExit, /unknown code 'zzz'/)
      end
    end

    it "aborts when user provides empty input", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        # Simulate user just pressing Enter; gets -> "\n" then strip -> ""
        allow($stdin).to receive(:gets).and_return("\n")
        require "kettle/dev/tasks/ci_task"
        expect { described_class.act(nil) }.to raise_error(SystemExit, /no selection/)
      end
    end

    it "aborts for invalid numeric selection (out of bounds)", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow($stdin).to receive(:gets).and_return("9\n")
        require "kettle/dev/tasks/ci_task"
        expect { described_class.act(nil) }.to raise_error(SystemExit, /invalid selection 9/)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/StubbedMock, RSpec/MessageSpies, RSpec/ReceiveMessages
