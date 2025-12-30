# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Signing::EIP712 do
  describe '.l1_action_domain' do
    it 'returns domain with correct chain ID and name for mainnet' do
      domain = described_class.l1_action_domain(mainnet: true)

      expect(domain[:name]).to eq('Exchange')
      expect(domain[:version]).to eq('1')
      expect(domain[:chainId]).to eq(1337)
      expect(domain[:verifyingContract]).to eq('0x0000000000000000000000000000000000000000')
    end

    it 'returns same domain for testnet (L1 chain ID is always 1337)' do
      domain = described_class.l1_action_domain(mainnet: false)

      expect(domain[:name]).to eq('Exchange')
      expect(domain[:version]).to eq('1')
      expect(domain[:chainId]).to eq(1337)
      expect(domain[:verifyingContract]).to eq('0x0000000000000000000000000000000000000000')
    end
  end

  describe '.domain_type' do
    it 'returns EIP-712 domain type definition' do
      domain_type = described_class.domain_type

      expect(domain_type).to include(
        { name: :name, type: 'string' },
        { name: :version, type: 'string' },
        { name: :chainId, type: 'uint256' },
        { name: :verifyingContract, type: 'address' }
      )
    end
  end

  describe '.agent_type' do
    it 'returns Agent type definition' do
      agent_type = described_class.agent_type

      expect(agent_type).to include(
        { name: :source, type: 'string' },
        { name: :connectionId, type: 'bytes32' }
      )
    end
  end

  describe '.source' do
    it 'returns "a" for mainnet' do
      expect(described_class.source(mainnet: true)).to eq('a')
    end

    it 'returns "b" for testnet' do
      expect(described_class.source(mainnet: false)).to eq('b')
    end
  end

  describe 'constants' do
    it 'defines L1 chain ID as 1337' do
      expect(described_class::L1_CHAIN_ID).to eq(1337)
    end
  end
end
