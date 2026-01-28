# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Signing::EIP712 do
  describe '.l1_action_domain' do
    it 'returns domain with Exchange name' do
      domain = described_class.l1_action_domain
      expect(domain[:name]).to eq('Exchange')
    end

    it 'returns domain with version 1' do
      domain = described_class.l1_action_domain
      expect(domain[:version]).to eq('1')
    end

    it 'returns domain with chain ID 1337' do
      domain = described_class.l1_action_domain
      expect(domain[:chainId]).to eq(1337)
    end

    it 'returns domain with zero verifying contract' do
      domain = described_class.l1_action_domain
      expect(domain[:verifyingContract]).to eq('0x0000000000000000000000000000000000000000')
    end
  end

  describe '.domain_type' do
    it 'returns correct field definitions' do
      domain_type = described_class.domain_type

      expect(domain_type).to include({ name: :name, type: 'string' })
      expect(domain_type).to include({ name: :version, type: 'string' })
      expect(domain_type).to include({ name: :chainId, type: 'uint256' })
      expect(domain_type).to include({ name: :verifyingContract, type: 'address' })
    end
  end

  describe '.agent_type' do
    it 'returns correct field definitions' do
      agent_type = described_class.agent_type

      expect(agent_type).to include({ name: :source, type: 'string' })
      expect(agent_type).to include({ name: :connectionId, type: 'bytes32' })
    end
  end

  describe '.source' do
    it 'returns "a" for mainnet' do
      expect(described_class.source(testnet: false)).to eq('a')
    end

    it 'returns "b" for testnet' do
      expect(described_class.source(testnet: true)).to eq('b')
    end
  end

  describe 'constants' do
    it 'defines L1 chain ID as 1337' do
      expect(described_class::L1_CHAIN_ID).to eq(1337)
    end

    it 'defines mainnet source as "a"' do
      expect(described_class::MAINNET_SOURCE).to eq('a')
    end

    it 'defines testnet source as "b"' do
      expect(described_class::TESTNET_SOURCE).to eq('b')
    end
  end
end
