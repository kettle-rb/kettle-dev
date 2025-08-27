# frozen_string_literal: true

require "kettle/dev/versioning"

RSpec.describe Kettle::Dev::Versioning do
  describe '::classify_bump' do
    it 'returns :epic when major version exceeds 1000' do
      expect(described_class.classify_bump('1000.0.0', '1001.0.0')).to eq(:epic)
    end

    it 'returns :major when major increases but is not epic' do
      expect(described_class.classify_bump('0.9.9', '1.0.0')).to eq(:major)
    end

    it 'returns :minor when minor increases' do
      expect(described_class.classify_bump('1.2.3', '1.3.0')).to eq(:minor)
    end

    it 'returns :patch when patch increases' do
      expect(described_class.classify_bump('1.2.3', '1.2.4')).to eq(:patch)
    end

    it 'falls back to :same for weird segment shapes (e.g., prerelease -> release)' do
      # 1.2.3 is greater than 1.2.3.a, but the MAJOR/MINOR/PATCH comparisons are equal,
      # exercising the fallback :same branch inside classify_bump
      expect(described_class.classify_bump('1.2.3.a', '1.2.3')).to eq(:same)
    end
  end

  describe '::epic_major?' do
    it 'is true for > 1000' do
      expect(described_class.epic_major?(1001)).to be true
    end

    it 'is false for 1000' do
      expect(described_class.epic_major?(1000)).to be false
    end

    it 'is falsey for nil' do
      expect(described_class.epic_major?(nil)).to be_falsey
    end
  end

  describe '::abort!' do
    it 'delegates to ExitAdapter.abort (no rescue)', :real_exit_adapter do
      # Ensure ExitAdapter.abort raises SystemExit which is not rescued (rescue StandardError)
      allow(Kettle::Dev::ExitAdapter).to receive(:abort).and_raise(SystemExit.new(1))
      expect { described_class.abort!('boom') }.to raise_error(SystemExit)
    end

    it 'rescues StandardError from ExitAdapter.abort and falls back to Kernel.abort', :real_exit_adapter do
      allow(Kettle::Dev::ExitAdapter).to receive(:abort).and_raise(StandardError.new('fail'))
      expect { described_class.abort!('fallback') }.to raise_error(SystemExit)
    end
  end
end
