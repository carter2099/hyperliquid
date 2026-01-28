# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Signing::Signer do
  # Well-known test private key
  let(:test_private_key) { '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' }
  let(:expected_address) { '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' }

  describe '#initialize' do
    it 'accepts private key with 0x prefix' do
      signer = described_class.new(private_key: test_private_key, testnet: false)
      expect(signer.address.downcase).to eq(expected_address.downcase)
    end

    it 'accepts private key without 0x prefix' do
      key_without_prefix = test_private_key[2..]
      signer = described_class.new(private_key: key_without_prefix, testnet: false)
      expect(signer.address.downcase).to eq(expected_address.downcase)
    end

    it 'defaults to mainnet' do
      signer = described_class.new(private_key: test_private_key)
      expect(signer.address.downcase).to eq(expected_address.downcase)
    end
  end

  describe '#address' do
    it 'returns checksummed Ethereum address' do
      signer = described_class.new(private_key: test_private_key, testnet: false)
      address = signer.address

      expect(address).to start_with('0x')
      expect(address.length).to eq(42)
    end
  end

  describe '#sign_l1_action' do
    let(:signer) { described_class.new(private_key: test_private_key, testnet: false) }
    let(:action) { { type: 'order', orders: [], grouping: 'na' } }
    let(:nonce) { 1_703_123_456_789 }

    it 'returns signature with r, s, v components' do
      signature = signer.sign_l1_action(action, nonce)

      expect(signature).to have_key(:r)
      expect(signature).to have_key(:s)
      expect(signature).to have_key(:v)
    end

    it 'returns r as hex string with 0x prefix and 64 hex chars' do
      signature = signer.sign_l1_action(action, nonce)

      expect(signature[:r]).to start_with('0x')
      expect(signature[:r].length).to eq(66) # 0x + 64 hex chars
    end

    it 'returns s as hex string with 0x prefix and 64 hex chars' do
      signature = signer.sign_l1_action(action, nonce)

      expect(signature[:s]).to start_with('0x')
      expect(signature[:s].length).to eq(66)
    end

    it 'returns v as integer (27 or 28)' do
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
      let(:testnet_signer) { described_class.new(private_key: test_private_key, testnet: true) }

      it 'produces different signature than mainnet for same action' do
        mainnet_sig = signer.sign_l1_action(action, nonce)
        testnet_sig = testnet_signer.sign_l1_action(action, nonce)

        expect(mainnet_sig).not_to eq(testnet_sig)
      end
    end

    context 'with vault_address' do
      let(:vault_address) { '0x1234567890123456789012345678901234567890' }

      it 'produces different signature when vault_address is provided' do
        sig_without_vault = signer.sign_l1_action(action, nonce)
        sig_with_vault = signer.sign_l1_action(action, nonce, vault_address: vault_address)

        expect(sig_without_vault).not_to eq(sig_with_vault)
      end

      it 'produces consistent signatures with same vault_address' do
        sig1 = signer.sign_l1_action(action, nonce, vault_address: vault_address)
        sig2 = signer.sign_l1_action(action, nonce, vault_address: vault_address)

        expect(sig1).to eq(sig2)
      end

      it 'produces different signatures for different vault addresses' do
        vault_address2 = '0x9876543210987654321098765432109876543210'
        sig1 = signer.sign_l1_action(action, nonce, vault_address: vault_address)
        sig2 = signer.sign_l1_action(action, nonce, vault_address: vault_address2)

        expect(sig1).not_to eq(sig2)
      end
    end

    context 'with expires_after' do
      let(:expires_after) { nonce + 30_000 }

      it 'produces different signature when expires_after is provided' do
        sig_without = signer.sign_l1_action(action, nonce)
        sig_with = signer.sign_l1_action(action, nonce, expires_after: expires_after)

        expect(sig_without).not_to eq(sig_with)
      end

      it 'produces consistent signatures with same expires_after' do
        sig1 = signer.sign_l1_action(action, nonce, expires_after: expires_after)
        sig2 = signer.sign_l1_action(action, nonce, expires_after: expires_after)

        expect(sig1).to eq(sig2)
      end

      it 'produces different signatures for different expires_after' do
        sig1 = signer.sign_l1_action(action, nonce, expires_after: expires_after)
        sig2 = signer.sign_l1_action(action, nonce, expires_after: expires_after + 1000)

        expect(sig1).not_to eq(sig2)
      end
    end

    # Python SDK parity tests
    # These use the exact test vectors from the official Python SDK to verify signing parity
    # Source: https://github.com/hyperliquid-dex/hyperliquid-python-sdk/blob/master/tests/signing_test.py
    context 'Python SDK parity' do
      let(:parity_private_key) { '0x0123456789012345678901234567890123456789012345678901234567890123' }
      let(:mainnet_signer) { described_class.new(private_key: parity_private_key, testnet: false) }
      let(:testnet_signer) { described_class.new(private_key: parity_private_key, testnet: true) }

      # Order action matching Python SDK test_l1_action_signing_order_matches
      # Order: asset 1, buy, 100 sz, 100 limit_px, Gtc tif
      let(:order_action) do
        {
          type: 'order',
          orders: [{
            a: 1,
            b: true,
            p: '100',
            s: '100',
            r: false,
            t: { limit: { tif: 'Gtc' } }
          }],
          grouping: 'na'
        }
      end

      it 'signs order action matching Python SDK (mainnet)' do
        sig = mainnet_signer.sign_l1_action(order_action, 0)

        expect(sig[:r]).to eq('0xd65369825a9df5d80099e513cce430311d7d26ddf477f5b3a33d2806b100d78e')
        expect(sig[:s]).to eq('0x2b54116ff64054968aa237c20ca9ff68000f977c93289157748a3162b6ea940e')
        expect(sig[:v]).to eq(28)
      end

      it 'signs order action matching Python SDK (testnet)' do
        sig = testnet_signer.sign_l1_action(order_action, 0)

        expect(sig[:r]).to eq('0x82b2ba28e76b3d761093aaded1b1cdad4960b3af30212b343fb2e6cdfa4e3d54')
        expect(sig[:s]).to eq('0x6b53878fc99d26047f4d7e8c90eb98955a109f44209163f52d8dc4278cbbd9f5')
        expect(sig[:v]).to eq(27)
      end

      # Order with cloid matching Python SDK test_l1_action_signing_order_with_cloid_matches
      let(:order_with_cloid_action) do
        {
          type: 'order',
          orders: [{
            a: 1,
            b: true,
            p: '100',
            s: '100',
            r: false,
            t: { limit: { tif: 'Gtc' } },
            c: '0x00000000000000000000000000000001'
          }],
          grouping: 'na'
        }
      end

      it 'signs order with cloid matching Python SDK (mainnet)' do
        sig = mainnet_signer.sign_l1_action(order_with_cloid_action, 0)

        expect(sig[:r]).to eq('0x041ae18e8239a56cacbc5dad94d45d0b747e5da11ad564077fcac71277a946e3')
        expect(sig[:s]).to eq('0x3c61f667e747404fe7eea8f90ab0e76cc12ce60270438b2058324681a00116da')
        expect(sig[:v]).to eq(27)
      end

      it 'signs order with cloid matching Python SDK (testnet)' do
        sig = testnet_signer.sign_l1_action(order_with_cloid_action, 0)

        expect(sig[:r]).to eq('0xeba0664bed2676fc4e5a743bf89e5c7501aa6d870bdb9446e122c9466c5cd16d')
        expect(sig[:s]).to eq('0x7f3e74825c9114bc59086f1eebea2928c190fdfbfde144827cb02b85bbe90988')
        expect(sig[:v]).to eq(28)
      end
    end
  end
end
