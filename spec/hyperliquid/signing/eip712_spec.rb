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

  describe '.hyperliquid_chain' do
    it 'returns "Mainnet" for mainnet' do
      expect(described_class.hyperliquid_chain(testnet: false)).to eq('Mainnet')
    end

    it 'returns "Testnet" for testnet' do
      expect(described_class.hyperliquid_chain(testnet: true)).to eq('Testnet')
    end
  end

  describe '.user_signed_domain' do
    it 'returns domain with HyperliquidSignTransaction name' do
      domain = described_class.user_signed_domain
      expect(domain[:name]).to eq('HyperliquidSignTransaction')
    end

    it 'returns domain with version 1' do
      domain = described_class.user_signed_domain
      expect(domain[:version]).to eq('1')
    end

    it 'returns domain with chain ID 421614' do
      domain = described_class.user_signed_domain
      expect(domain[:chainId]).to eq(421_614)
    end

    it 'returns domain with zero verifying contract' do
      domain = described_class.user_signed_domain
      expect(domain[:verifyingContract]).to eq('0x0000000000000000000000000000000000000000')
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

    it 'defines USER_SIGNED_CHAIN_ID as 421614' do
      expect(described_class::USER_SIGNED_CHAIN_ID).to eq(421_614)
    end
  end

  describe 'user-signed type definitions' do
    it 'defines USD_SEND_TYPES with correct fields' do
      types = described_class::USD_SEND_TYPES
      fields = types[:'HyperliquidTransaction:UsdSend']
      expect(fields.map { |f| f[:name] }).to eq(%i[hyperliquidChain destination amount time])
    end

    it 'defines SPOT_SEND_TYPES with correct fields' do
      types = described_class::SPOT_SEND_TYPES
      fields = types[:'HyperliquidTransaction:SpotSend']
      expect(fields.map { |f| f[:name] }).to eq(%i[hyperliquidChain destination token amount time])
    end

    it 'defines USD_CLASS_TRANSFER_TYPES with correct fields' do
      types = described_class::USD_CLASS_TRANSFER_TYPES
      fields = types[:'HyperliquidTransaction:UsdClassTransfer']
      expect(fields.map { |f| f[:name] }).to eq(%i[hyperliquidChain amount toPerp nonce])
    end

    it 'defines WITHDRAW_TYPES with correct fields' do
      types = described_class::WITHDRAW_TYPES
      fields = types[:'HyperliquidTransaction:Withdraw']
      expect(fields.map { |f| f[:name] }).to eq(%i[hyperliquidChain destination amount time])
    end

    it 'defines SEND_ASSET_TYPES with correct fields' do
      types = described_class::SEND_ASSET_TYPES
      fields = types[:'HyperliquidTransaction:SendAsset']
      expect(fields.map { |f| f[:name] }).to eq(
        %i[hyperliquidChain destination sourceDex destinationDex token amount fromSubAccount nonce]
      )
    end
  end
end
