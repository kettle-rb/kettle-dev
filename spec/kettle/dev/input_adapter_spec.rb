# frozen_string_literal: true

RSpec.describe Kettle::Dev::InputAdapter, :real_input_adapter do
  describe "#gets" do
    it "delegates to $stdin.gets with arguments (separator) and returns the line" do
      require "stringio"
      original_stdin = $stdin
      begin
        io = StringIO.new("a|b|c")
        $stdin = io
        # StringIO#gets with a custom separator reads through that separator
        result = described_class.gets("|")
        expect(result).to eq("a|")
      ensure
        $stdin = original_stdin
      end
    end

    it "returns nil on EOF (consistent with IO#gets)" do
      require "stringio"
      original_stdin = $stdin
      begin
        $stdin = StringIO.new("")
        expect(described_class.gets).to be_nil
      ensure
        $stdin = original_stdin
      end
    end
  end

  describe "::readline" do
    it "returns the line when available and forwards args" do
      require "stringio"
      original_stdin = $stdin
      begin
        $stdin = StringIO.new("hello-world")
        # Using custom separator to ensure args are forwarded into gets
        expect(described_class.readline("-"))
          .to eq("hello-")
      ensure
        $stdin = original_stdin
      end
    end

    it "raises EOFError when no more input is available (nil from gets)" do
      require "stringio"
      original_stdin = $stdin
      begin
        $stdin = StringIO.new("")
        expect { described_class.readline }.to raise_error(EOFError, "end of file reached")
      ensure
        $stdin = original_stdin
      end
    end
  end
end
