# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Signing::Signer do
  # Test private key (DO NOT use in production - this is a well-known test key)
  let(:test_private_key) { '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' }
  let(:expected_address) { '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' }

  describe '#initialize' do
    it 'accepts private key with 0x prefix' do
      signer = described_class.new(private_key: test_private_key, mainnet: true)
      expect(signer.address.downcase).to eq(expected_address.downcase)
    end

    it 'accepts private key without 0x prefix' do
      key_without_prefix = test_private_key[2..]
      signer = described_class.new(private_key: key_without_prefix, mainnet: true)
      expect(signer.address.downcase).to eq(expected_address.downcase)
    end

    it 'defaults to mainnet' do
      signer = described_class.new(private_key: test_private_key)
      expect(signer.address.downcase).to eq(expected_address.downcase)
    end
  end

  describe '#address' do
    it 'returns checksummed Ethereum address' do
      signer = described_class.new(private_key: test_private_key, mainnet: true)
      address = signer.address

      expect(address).to start_with('0x')
      expect(address.length).to eq(42)
    end
  end

  describe '#sign_l1_action' do
    let(:signer) { described_class.new(private_key: test_private_key, mainnet: true) }
    let(:action) { { type: 'order', orders: [], grouping: 'na' } }
    let(:nonce) { 1_703_123_456_789 }

    it 'returns signature with r, s, v components' do
      signature = signer.sign_l1_action(action, nonce)

      expect(signature).to have_key(:r)
      expect(signature).to have_key(:s)
      expect(signature).to have_key(:v)
    end

    it 'returns r as hex string with 0x prefix' do
      signature = signer.sign_l1_action(action, nonce)

      expect(signature[:r]).to start_with('0x')
      expect(signature[:r].length).to eq(66) # 0x + 64 hex chars
    end

    it 'returns s as hex string with 0x prefix' do
      signature = signer.sign_l1_action(action, nonce)

      expect(signature[:s]).to start_with('0x')
      expect(signature[:s].length).to eq(66)
    end

    it 'returns v as integer' do
      signature = signer.sign_l1_action(action, nonce)

      expect(signature[:v]).to be_a(Integer)
      expect([27, 28]).to include(signature[:v])
    end

    it 'produces consistent signatures for same input' do
      sig1 = signer.sign_l1_action(action, nonce)
      sig2 = signer.sign_l1_action(action, nonce)

      expect(sig1).to eq(sig2)
    end

    it 'produces different signatures for different actions' do
      action2 = { type: 'cancel', cancels: [] }

      sig1 = signer.sign_l1_action(action, nonce)
      sig2 = signer.sign_l1_action(action2, nonce)

      expect(sig1).not_to eq(sig2)
    end

    it 'produces different signatures for different nonces' do
      nonce2 = nonce + 1000

      sig1 = signer.sign_l1_action(action, nonce)
      sig2 = signer.sign_l1_action(action, nonce2)

      expect(sig1).not_to eq(sig2)
    end

    context 'with testnet signer' do
      let(:testnet_signer) { described_class.new(private_key: test_private_key, mainnet: false) }

      it 'produces different signature than mainnet for same action' do
        mainnet_sig = signer.sign_l1_action(action, nonce)
        testnet_sig = testnet_signer.sign_l1_action(action, nonce)

        expect(mainnet_sig).not_to eq(testnet_sig)
      end
    end
  end
end
