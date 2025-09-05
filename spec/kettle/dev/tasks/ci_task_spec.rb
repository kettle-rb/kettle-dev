# frozen_string_literal: true

# rubocop:disable RSpec/MultipleExpectations, RSpec/StubbedMock, RSpec/MessageSpies, RSpec/ReceiveMessages

require "tmpdir"
require "fileutils"

RSpec.describe Kettle::Dev::Tasks::CITask do
  def http_ok_with(body_hash)
    instance_double(Net::HTTPOK, is_a?: true, body: JSON.dump(body_hash), code: "200")
  end

  before do
    # Default stubs for git/repo context used by the task
    allow(Kettle::Dev::CIHelpers).to receive_messages(
      current_branch: "main",
      repo_info: ["acme", "demo"],
      default_token: nil,
    )

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
    it "prints emoji for queued/in_progress/completed failure statuses", :check_output do
      with_workflows(["ci.yml"]) do |_root, dir|
        seq = [
          http_ok_with({"workflow_runs" => [{"status" => "queued"}]}),
          http_ok_with({"workflow_runs" => [{"status" => "in_progress"}]}),
          http_ok_with({"workflow_runs" => [{"status" => "completed", "conclusion" => "failure"}]}),
        ]
        allow(Net::HTTP).to receive(:start).and_return(*seq)
        file_path = File.join(dir, "ci.yml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true).at_least(:once)
        expect { described_class.act("ci") }.not_to raise_error
      end
    end

    it "runs act for a short code mapping" do
      with_workflows(["ci.yml", "style.yaml"]) do |_root, dir|
        file_path = File.join(dir, "ci.yml")
        expect(File).to exist(file_path)
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act("ci") }.not_to raise_error
      end
    end

    it "runs act for an explicit filename with extension" do
      with_workflows(["ci.yml", "style.yaml"]) do |_root, dir|
        file_path = File.join(dir, "style.yaml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act("style.yaml") }.not_to raise_error
      end
    end

    it "resolves a basename without extension when .yaml exists" do
      with_workflows(["style.yaml"]) do |_root, dir|
        file_path = File.join(dir, "style.yaml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act("style") }.not_to raise_error
      end
    end

    it "resolves a basename without extension when .yml exists" do
      with_workflows(["build.yml"]) do |_root, dir|
        file_path = File.join(dir, "build.yml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act("build") }.not_to raise_error
      end
    end

    it "skips GHA status when git context is missing (branch or repo)", :check_output do
      allow(Kettle::Dev::CIHelpers).to receive(:current_branch).and_return(nil)
      with_workflows(["ci.yml"]) do |_root, dir|
        file_path = File.join(dir, "ci.yml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act("ci") }.not_to raise_error
      end
    end

    it "handles GitHub API 'none' (no runs)", :check_output do
      allow(Net::HTTP).to receive(:start).and_return(
        http_ok_with({"workflow_runs" => []}),
      )
      with_workflows(["ci.yml"]) do |_root, dir|
        file_path = File.join(dir, "ci.yml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act("ci") }.not_to raise_error
      end
    end

    it "handles GitHub API request failure (non-success)", :check_output do
      bad = instance_double(Net::HTTPServerError, is_a?: false, code: "500", body: "boom")
      allow(Net::HTTP).to receive(:start).and_return(bad)
      with_workflows(["ci.yml"]) do |_root, dir|
        file_path = File.join(dir, "ci.yml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act("ci") }.not_to raise_error
      end
    end

    it "handles GitHub API exceptions gracefully", :check_output do
      allow(Net::HTTP).to receive(:start).and_raise(StandardError.new("timeout"))
      with_workflows(["ci.yml"]) do |_root, dir|
        file_path = File.join(dir, "ci.yml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act("ci") }.not_to raise_error
      end
    end

    it "aborts and lists available options including (others) when dynamic files exist", :check_output do
      # Two files with same first 3 letters so one becomes a dynamic file
      with_workflows(["che_one.yml", "che_two.yml"]) do |_root, _dir|
        expect { described_class.act("does_not_exist") }.to raise_error(Kettle::Dev::Error, /ci:act aborted/)
      end
    end
  end

  describe "::act (interactive)", :skip_ci do
    it "highlights mismatch when GitHub and GitLab HEAD SHAs differ", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        # Ensure both remotes are detected
        allow(Kettle::Dev::CIMonitor).to receive(:preferred_github_remote).and_return("origin")
        allow(Kettle::Dev::CIMonitor).to receive(:gitlab_remote_candidates).and_return(["gitlab"])
        # Provide ls-remote outputs for each
        allow(Open3).to receive(:capture2).and_wrap_original do |m, *args|
          if args == ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]
            ["origin/main\n", instance_double(Process::Status, success?: true)]
          elsif args == ["git", "rev-parse", "--short", "HEAD"]
            ["abc123\n", instance_double(Process::Status, success?: true)]
          elsif args == ["git", "ls-remote", "origin", "refs/heads/main"]
            ["1111111111111111111111111111111111111111\trefs/heads/main\n", instance_double(Process::Status, success?: true)]
          elsif args == ["git", "ls-remote", "gitlab", "refs/heads/main"]
            ["2222222222222222222222222222222222222222\trefs/heads/main\n", instance_double(Process::Status, success?: true)]
          else
            m.call(*args)
          end
        end
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        expect { described_class.act(nil) }.to output(/HEAD mismatch on main: GitHub 1111111 vs GitLab 2222222/).to_stdout
      end
    end

    it "does not warn when GitHub and GitLab HEAD SHAs match", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow(Kettle::Dev::CIMonitor).to receive(:preferred_github_remote).and_return("origin")
        allow(Kettle::Dev::CIMonitor).to receive(:gitlab_remote_candidates).and_return(["gitlab"])
        allow(Open3).to receive(:capture2).and_wrap_original do |m, *args|
          if args == ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]
            ["origin/main\n", instance_double(Process::Status, success?: true)]
          elsif args == ["git", "rev-parse", "--short", "HEAD"]
            ["abc123\n", instance_double(Process::Status, success?: true)]
          elsif args == ["git", "ls-remote", "origin", "refs/heads/main"] || args == ["git", "ls-remote", "gitlab", "refs/heads/main"]
            ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/heads/main\n", instance_double(Process::Status, success?: true)]
          else
            m.call(*args)
          end
        end
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        expect { described_class.act(nil) }.not_to output(/HEAD mismatch/).to_stdout
      end
    end

    it "handles missing GitLab remote gracefully (no mismatch check)", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow(Kettle::Dev::CIMonitor).to receive(:preferred_github_remote).and_return("origin")
        allow(Kettle::Dev::CIMonitor).to receive(:gitlab_remote_candidates).and_return([])
        allow(Open3).to receive(:capture2).and_wrap_original do |m, *args|
          if args == ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]
            ["origin/main\n", instance_double(Process::Status, success?: true)]
          elsif args == ["git", "rev-parse", "--short", "HEAD"]
            ["abc123\n", instance_double(Process::Status, success?: true)]
          elsif args == ["git", "ls-remote", "origin", "refs/heads/main"]
            ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/heads/main\n", instance_double(Process::Status, success?: true)]
          else
            m.call(*args)
          end
        end
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        expect { described_class.act(nil) }.not_to raise_error
      end
    end
    it "quits when user enters 'q'", :check_output do
      with_workflows(["ci.yml", "style.yaml"]) do |_root, _dir|
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        # Should not run system at all
        expect(described_class).not_to receive(:system)
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "prints repo info even when branch missing", :check_output do
      allow(Kettle::Dev::CIHelpers).to receive(:current_branch).and_return(nil)
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "prints repo n/a when repo info missing", :check_output do
      allow(Kettle::Dev::CIHelpers).to receive(:repo_info).and_return(nil)
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "prints n/a for upstream and sha when git commands fail", :check_output do
      allow(Open3).to receive(:capture2).and_raise(StandardError)
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "updates status lines in non-tty mode (early exit and err/fail/none)", :check_output do
      # Make ENV poll interval zero so sleep is immediate
      stub_env("CI_ACT_POLL_INTERVAL" => "0")
      # Return sequence: fail (500), err (exception), none (no runs), completed success
      bad = instance_double(Net::HTTPServerError, is_a?: false, code: "500", body: "boom")
      ok_none = http_ok_with({"workflow_runs" => []})
      ok_done = http_ok_with({"workflow_runs" => [{"status" => "completed", "conclusion" => "success"}]})
      allow(Net::HTTP).to receive(:start).and_return(bad, -> { raise StandardError }, ok_none, ok_done)

      with_workflows(["ci.yml"]) do |_root, _dir|
        # Cause early-exit path for worker when missing org/branch
        allow(Kettle::Dev::CIHelpers).to receive(:repo_info).and_return(["acme", "demo"]) # present
        allow(Kettle::Dev::CIHelpers).to receive(:current_branch).and_return("main") # present
        # Normal interactive, then choose to quit to end quickly
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "polls queued→in_progress→completed in worker loop (with TTY)", :check_output, :skip_ci do
      stub_env("CI_ACT_POLL_INTERVAL" => "0")
      seq = [
        http_ok_with({"workflow_runs" => [{"status" => "queued"}]}),
        http_ok_with({"workflow_runs" => [{"status" => "in_progress"}]}),
        http_ok_with({"workflow_runs" => [{"status" => "completed", "conclusion" => "success"}]}),
      ]
      allow(Net::HTTP).to receive(:start).and_return(*seq)
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow($stdout).to receive(:tty?).and_return(true)
        allow(Kettle::Dev::InputAdapter).to receive(:gets) {
          sleep 0.1
          "q\n"
        }
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "prints simple non-tty status lines before input arrives", :check_output, :skip_ci do
      # ensure non-tty
      allow($stdout).to receive(:tty?).and_return(false)
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow(Kettle::Dev::InputAdapter).to receive(:gets) {
          sleep 0.05
          "q\n"
        }
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "handles Integer error for poll interval (outer rescue in worker)", :check_output, :skip_ci do
      stub_env("CI_ACT_POLL_INTERVAL" => "oops")
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        expect { described_class.act(nil) }.not_to raise_error
      end
    end
  end

  describe "::act (no workflows dir)" do
    it "handles missing workflows directory gracefully", :check_output do
      Dir.mktmpdir do |root|
        # Do NOT create .github/workflows
        allow(Kettle::Dev::CIHelpers).to receive(:project_root).and_return(root)
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        expect { described_class.act(nil) }.not_to raise_error
      end
    end
  end

  describe "::act edge cases and interactive behaviors", :skip_ci do
    it "uses default emoji for unknown status in non-interactive fetch", :check_output do
      with_workflows(["ci.yml"]) do |_root, dir|
        seq = [
          http_ok_with({"workflow_runs" => [{"status" => "unknown_state"}]}),
          http_ok_with({"workflow_runs" => [{"status" => "completed", "conclusion" => "success"}]}),
        ]
        allow(Net::HTTP).to receive(:start).and_return(*seq)
        file_path = File.join(dir, "ci.yml")
        # Spy on system first, then assert after the call; ensure only this exact call occurs
        allow(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act("ci") }.not_to raise_error
        expect(described_class).to have_received(:system).with("act", "-W", file_path).once
        expect(described_class).to have_received(:system).exactly(1).time
      end
    end

    it "covers worker default emoji branch for unknown status before completion (TTY)", :check_output do
      stub_env("CI_ACT_POLL_INTERVAL" => "0")
      seq = [
        http_ok_with({"workflow_runs" => [{"status" => "mystery"}]}),
        http_ok_with({"workflow_runs" => [{"status" => "completed", "conclusion" => "success"}]}),
      ]
      allow(Net::HTTP).to receive(:start).and_return(*seq)
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow($stdout).to receive(:tty?).and_return(true)
        allow(Kettle::Dev::InputAdapter).to receive(:gets) {
          sleep 0.15
          "q\n"
        }
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "worker early-exits with n/a when repo or branch missing (pushes n/a)", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow(Kettle::Dev::CIHelpers).to receive(:repo_info).and_return(nil)
        allow($stdout).to receive(:tty?).and_return(true)
        # Let the worker thread run before we quit
        allow(Kettle::Dev::InputAdapter).to receive(:gets) {
          sleep 0.15
          "q\n"
        }
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "ensures TTY status update lines are printed before input arrives", :check_output do
      stub_env("CI_ACT_POLL_INTERVAL" => "0")
      seq = [
        http_ok_with({"workflow_runs" => [{"status" => "queued"}]}),
        http_ok_with({"workflow_runs" => [{"status" => "in_progress"}]}),
        http_ok_with({"workflow_runs" => [{"status" => "completed", "conclusion" => "success"}]}),
      ]
      allow(Net::HTTP).to receive(:start).and_return(*seq)
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow($stdout).to receive(:tty?).and_return(true)
        # Delay input so worker can print at least one line in TTY branch
        allow(Kettle::Dev::InputAdapter).to receive(:gets) {
          sleep 0.25
          "q\n"
        }
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "prints idx.nil? branch when queue contains unknown code (TTY)", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow($stdout).to receive(:tty?).and_return(true)
        # Provide input after we injected a fake status update
        allow(Kettle::Dev::InputAdapter).to receive(:gets) {
          sleep 0.1
          "q\n"
        }
        # Use a dedicated queue instance to avoid any_instance stubbing
        q = Queue.new
        injected = false
        # Provide a default stub for pop without args to use real behavior
        allow(q).to receive(:pop).and_call_original
        allow(q).to receive(:pop).with(true) do |_arg|
          if injected
            raise ThreadError
          else
            injected = true
            ["zzz", "fake.yml", "weird"]
          end
        end
        allow(Queue).to receive(:new).and_return(q)
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "recovers from ThreadError on first input pop and continues", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        # Provide input immediately to make queue non-empty soon
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("q\n")
        # Make the first Queue#pop(true) raise, then behave normally
        q = Queue.new
        cnt = 0
        # Provide a default stub for pop without args to use real behavior
        allow(q).to receive(:pop).and_call_original
        allow(q).to receive(:pop).with(true) do |_arg|
          cnt += 1
          if cnt == 1
            raise ThreadError
          else
            # Fallback to real behavior
            Queue.instance_method(:pop).bind(q).call(true)
          end
        end
        allow(Queue).to receive(:new).and_return(q)
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "aborts on invalid numeric selection (too high)", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        # Only 1 option + quit => entering 99 should abort
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("99\n")
        expect { described_class.act(nil) }.to raise_error(Kettle::Dev::Error, /invalid selection/)
      end
    end

    it "quits when numeric selection points to quit option", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        # Menu has 2 items (1: workflow, 2: quit)
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("2\n")
        expect(described_class).not_to receive(:system)
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "runs when numeric selection points to a valid option", :check_output do
      with_workflows(["ci.yml"]) do |_root, dir|
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("1\n")
        file_path = File.join(dir, "ci.yml")
        expect(described_class).to receive(:system).with("act", "-W", file_path).and_return(true)
        expect { described_class.act(nil) }.not_to raise_error
      end
    end

    it "aborts on unknown non-numeric code entry", :check_output do
      with_workflows(["ci.yml"]) do |_root, _dir|
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("zzz\n")
        expect { described_class.act(nil) }.to raise_error(Kettle::Dev::Error, /unknown code/)
      end
    end

    it "aborts when chosen workflow file is missing at run time", :check_output do
      with_workflows(["ci.yml"]) do |_root, dir|
        allow(Kettle::Dev::InputAdapter).to receive(:gets).and_return("1\n")
        file_path = File.join(dir, "ci.yml")
        # Pretend file is missing at the final check
        allow(File).to receive(:file?).and_call_original
        allow(File).to receive(:file?).with(file_path).and_return(false)
        expect { described_class.act(nil) }.to raise_error(Kettle::Dev::Error, /workflow not found/)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleExpectations, RSpec/StubbedMock, RSpec/MessageSpies, RSpec/ReceiveMessages
