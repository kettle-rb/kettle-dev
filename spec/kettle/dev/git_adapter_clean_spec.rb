# frozen_string_literal: true

RSpec.describe Kettle::Dev::GitAdapter, :real_git_adapter do
  describe "#clean?" do
    context "when using git gem backend" do
      let(:git_repo) { double("Git::Base") }
      let(:status_obj) { double("Git::Status", changed: {}, added: {}, deleted: {}, untracked: {}) }

      it "returns true when status has no changes" do
        adapter = described_class.new
        adapter.instance_variable_set(:@backend, :gem)
        adapter.instance_variable_set(:@git, git_repo)
        expect(git_repo).to receive(:status).and_return(status_obj)
        expect(adapter.clean?).to be true
      end

      it "returns false when there are any changes" do
        dirty_status = double("Git::Status", changed: {"a"=>"M"}, added: {}, deleted: {}, untracked: {})
        adapter = described_class.new
        adapter.instance_variable_set(:@backend, :gem)
        adapter.instance_variable_set(:@git, git_repo)
        expect(git_repo).to receive(:status).and_return(dirty_status)
        expect(adapter.clean?).to be false
      end

      it "returns false when status raises an error" do
        adapter = described_class.new
        adapter.instance_variable_set(:@backend, :gem)
        adapter.instance_variable_set(:@git, git_repo)
        allow(git_repo).to receive(:status).and_raise(StandardError)
        expect(adapter.clean?).to be false
      end
    end

    context "when using CLI backend" do
      let(:ok) { instance_double(Process::Status, success?: true) }
      let(:fail_status) { instance_double(Process::Status, success?: false) }

      before do
        allow(Kernel).to receive(:require).with("git").and_raise(LoadError)
      end

      it "returns true when porcelain output is empty" do
        expect(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["\n", ok])
        adapter = described_class.new
        expect(adapter.clean?).to be true
      end

      it "returns false when porcelain output has content" do
        expect(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return([" M lib/file.rb\n?? new.rb\n", ok])
        adapter = described_class.new
        expect(adapter.clean?).to be false
      end

      it "returns false when git status fails" do
        expect(Open3).to receive(:capture2).with("git", "status", "--porcelain").and_return(["", fail_status])
        adapter = described_class.new
        expect(adapter.clean?).to be false
      end

      it "returns false on unexpected errors" do
        expect(Open3).to receive(:capture2).and_raise(StandardError)
        adapter = described_class.new
        expect(adapter.clean?).to be false
      end
    end
  end
end
