# frozen_string_literal: true

RSpec.describe Kettle::Dev::InputAdapter do
  describe "#tty?" do
    it "delegates to $stdin.tty?" do
      orig = $stdin
      begin
        r, w = IO.pipe
        $stdin = r
        # IO.pipe returns a non-tty
        expect(described_class.tty?).to be false
      ensure
        $stdin = orig
        begin
          w.close
        rescue
          nil
        end
        begin
          r.close
        rescue
          nil
        end
      end
    end
  end

  describe "#readline" do
    it "raises EOFError when gets returns nil" do
      allow(described_class).to receive(:gets).and_return(nil)
      expect { described_class.readline }.to raise_error(EOFError)
    end

    it "returns line when present" do
      allow(described_class).to receive(:gets).and_return("abc\n")
      expect(described_class.readline).to eq("abc\n")
    end
  end
end
