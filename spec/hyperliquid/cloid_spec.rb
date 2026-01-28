# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Cloid do
  describe '#initialize' do
    it 'accepts valid hex string with 0x prefix' do
      cloid = described_class.new('0x1234567890abcdef1234567890abcdef')
      expect(cloid.to_raw).to eq('0x1234567890abcdef1234567890abcdef')
    end

    it 'normalizes to lowercase' do
      cloid = described_class.new('0xABCDEF1234567890ABCDEF1234567890')
      expect(cloid.to_raw).to eq('0xabcdef1234567890abcdef1234567890')
    end

    it 'rejects strings without 0x prefix' do
      expect do
        described_class.new('1234567890abcdef1234567890abcdef')
      end.to raise_error(ArgumentError, /must be '0x' followed by 32 hex characters/)
    end

    it 'rejects strings that are too short' do
      expect do
        described_class.new('0x1234')
      end.to raise_error(ArgumentError, /must be '0x' followed by 32 hex characters/)
    end

    it 'rejects strings that are too long' do
      expect do
        described_class.new('0x1234567890abcdef1234567890abcdef00')
      end.to raise_error(ArgumentError, /must be '0x' followed by 32 hex characters/)
    end

    it 'rejects non-hex characters' do
      expect do
        described_class.new('0xGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG')
      end.to raise_error(ArgumentError, /must be '0x' followed by 32 hex characters/)
    end
  end

  describe '.from_int' do
    it 'creates cloid from small integer with zero padding' do
      cloid = described_class.from_int(42)
      expect(cloid.to_raw).to eq('0x0000000000000000000000000000002a')
    end

    it 'creates cloid from zero' do
      cloid = described_class.from_int(0)
      expect(cloid.to_raw).to eq('0x00000000000000000000000000000000')
    end

    it 'creates cloid from large integer' do
      cloid = described_class.from_int(0x123456789abcdef0)
      expect(cloid.to_raw).to eq('0x0000000000000000123456789abcdef0')
    end

    it 'creates cloid from max 128-bit value' do
      max_value = (2**128) - 1
      cloid = described_class.from_int(max_value)
      # 0xfff ... ff
      expect(cloid.to_raw).to eq("0x#{'f' * 32}")
    end

    it 'raises error for negative integers' do
      expect do
        described_class.from_int(-1)
      end.to raise_error(ArgumentError, /must be non-negative/)
    end

    it 'raises error for values >= 2^128' do
      expect do
        described_class.from_int(2**128)
      end.to raise_error(ArgumentError, /must be less than 2\^128/)
    end
  end

  describe '.from_str' do
    it 'creates cloid from valid hex string' do
      cloid = described_class.from_str('0x1234567890abcdef1234567890abcdef')
      expect(cloid.to_raw).to eq('0x1234567890abcdef1234567890abcdef')
    end

    it 'raises error for invalid string' do
      expect do
        described_class.from_str('invalid')
      end.to raise_error(ArgumentError)
    end
  end

  describe '.random' do
    it 'generates valid cloid' do
      cloid = described_class.random
      expect(cloid.to_raw).to match(/\A0x[0-9a-f]{32}\z/)
    end

    it 'generates unique cloids' do
      cloids = 100.times.map { described_class.random.to_raw }
      expect(cloids.uniq.length).to eq(100)
    end
  end

  describe '.from_uuid' do
    it 'creates cloid from UUID with dashes' do
      uuid = '550e8400-e29b-41d4-a716-446655440000'
      cloid = described_class.from_uuid(uuid)
      expect(cloid.to_raw).to eq('0x550e8400e29b41d4a716446655440000')
    end

    it 'creates cloid from UUID without dashes' do
      uuid = '550e8400e29b41d4a716446655440000'
      cloid = described_class.from_uuid(uuid)
      expect(cloid.to_raw).to eq('0x550e8400e29b41d4a716446655440000')
    end

    it 'raises error for invalid UUID' do
      expect do
        described_class.from_uuid('invalid-uuid')
      end.to raise_error(ArgumentError, /UUID must be 32 hex characters/)
    end
  end

  describe '#to_s' do
    it 'returns raw cloid string' do
      cloid = described_class.from_int(42)
      expect(cloid.to_s).to eq('0x0000000000000000000000000000002a')
    end
  end

  describe '#==' do
    it 'returns true for equal cloids' do
      cloid1 = described_class.from_int(42)
      cloid2 = described_class.from_int(42)
      expect(cloid1).to eq(cloid2)
    end

    it 'returns true when comparing to matching string' do
      cloid = described_class.from_int(42)
      expect(cloid).to eq('0x0000000000000000000000000000002a')
    end

    it 'returns false for different cloids' do
      cloid1 = described_class.from_int(42)
      cloid2 = described_class.from_int(43)
      expect(cloid1).not_to eq(cloid2)
    end
  end

  describe '#hash' do
    it 'returns same hash for equal cloids' do
      cloid1 = described_class.from_int(42)
      cloid2 = described_class.from_int(42)
      expect(cloid1.hash).to eq(cloid2.hash)
    end

    it 'can be used as hash key' do
      cloid = described_class.from_int(42)
      hash = { cloid => 'value' }
      expect(hash[described_class.from_int(42)]).to eq('value')
    end
  end
end
