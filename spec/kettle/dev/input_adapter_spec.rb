# frozen_string_literal: true

RSpec.describe Kettle::Dev::InputAdapter, :real_input_adapter do
  describe "::gets" do
    context "when $stdin is replaced by KettleTestInputMachine with a default" do
      it "returns the provided line including a single trailing newline" do
        $stdin = KettleTestInputMachine.new(default: "yes")
        begin
          line = described_class.gets
          expect(line).to eq("yes\n")
        ensure
          $stdin = STDIN
        end
      end
    end

    context "when $stdin is replaced by KettleTestInputMachine without a default" do
      it "returns just a newline (accept default)" do
        $stdin = KettleTestInputMachine.new
        begin
          line = described_class.gets
          expect(line).to eq("\n")
        ensure
          $stdin = STDIN
        end
      end
    end

    context "when KettleTestInputMachine default already ends with a newline" do
      it "does not add an extra newline" do
        $stdin = KettleTestInputMachine.new(default: "no\n")
        begin
          line = described_class.gets
          expect(line).to eq("no\n")
        ensure
          $stdin = STDIN
        end
      end
    end
  end

  describe "::tty?" do
    it "delegates to $stdin.tty? (false for KettleTestInputMachine)" do
      $stdin = KettleTestInputMachine.new(default: "ignored")
      begin
        expect(described_class.tty?).to be(false)
      ensure
        $stdin = STDIN
      end
    end
  end

  describe "::readline" do
    it "returns the next line when available" do
      $stdin = KettleTestInputMachine.new(default: "answer")
      begin
        expect(described_class.readline).to eq("answer\n")
      ensure
        $stdin = STDIN
      end
    end

    it "raises EOFError when gets returns nil" do
      # Build a minimal stub that simulates EOF by returning nil for gets
      eof_stdin = Class.new do
        def gets(*)
          nil
        end

        def tty?
          false
        end
      end.new

      old = $stdin
      $stdin = eof_stdin
      begin
        expect { described_class.readline }.to raise_error(EOFError, /end of file/i)
      ensure
        $stdin = old
      end
    end
  end
end
