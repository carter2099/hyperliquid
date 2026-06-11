# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Signing::MultiSig do
  # Fixtures captured 2026-05-07 against Python eth_account 0.13.7 + msgpack 1.1.2.
  # Capture script: ~/agent-state/hyperliquid-sdk-fixtures/capture_multi_sig_signatures.py
  # Do not modify these values without re-capturing — they lock down byte-parity with the
  # Python reference for both msgpack action_hash and EIP-712 signing of bytes32.
  let(:fixture_private_key) { '0x1111111111111111111111111111111111111111111111111111111111111111' }
  let(:fixture_signer) { Hyperliquid::Signing::Signer.new(private_key: fixture_private_key, testnet: false) }
  let(:fixture_signer_address) { '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A' }
  let(:fixture_nonce) { 1_700_000_000_000 }
  let(:multi_sig_user) { '0x0000000000000000000000000000000000000005' }
  let(:outer_signer) { fixture_signer_address.downcase }

  describe '.build_envelope' do
    it 'constructs the multiSig action body with lowercased addresses' do
      envelope = described_class.build_envelope(
        inner_action: { type: 'noop' },
        multi_sig_user: '0xABCDEF1234567890ABCDEF1234567890ABCDEF12',
        outer_signer: '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A',
        signatures: [{ r: '0x1', s: '0x2', v: 27 }]
      )

      expect(envelope[:type]).to eq('multiSig')
      expect(envelope[:signatureChainId]).to eq('0x66eee')
      expect(envelope[:signatures]).to eq([{ r: '0x1', s: '0x2', v: 27 }])
      expect(envelope[:payload][:multiSigUser]).to eq('0xabcdef1234567890abcdef1234567890abcdef12')
      expect(envelope[:payload][:outerSigner]).to eq('0x19e7e376e7c213b7e7e7e46cc70a5dd086daff2a')
      expect(envelope[:payload][:action]).to eq({ type: 'noop' })
    end
  end

  describe '.payload_action (userSetAbstraction wire-form normalization)' do
    it 'translates long-form abstraction "disabled" to wire enum "i"' do
      action = {
        type: 'userSetAbstraction',
        signatureChainId: '0x66eee',
        hyperliquidChain: 'Testnet',
        user: '0x3b4d2cc2e144a0044002506c8b44508e9ace82e9',
        abstraction: 'disabled',
        nonce: 1_780_130_409_592
      }
      result = described_class.payload_action(action)
      expect(result[:abstraction]).to eq('i')
      expect(action[:abstraction]).to eq('disabled') # original is not mutated
    end

    it 'translates "unifiedAccount" → "u" and "portfolioMargin" → "p"' do
      unified = described_class.payload_action({ type: 'userSetAbstraction', abstraction: 'unifiedAccount' })
      portfolio = described_class.payload_action({ type: 'userSetAbstraction', abstraction: 'portfolioMargin' })
      expect(unified[:abstraction]).to eq('u')
      expect(portfolio[:abstraction]).to eq('p')
    end

    it 'passes through wire enum values unchanged' do
      %w[i u p].each do |code|
        result = described_class.payload_action({ type: 'userSetAbstraction', abstraction: code })
        expect(result[:abstraction]).to eq(code)
      end
    end

    it 'passes through non-userSetAbstraction actions unchanged' do
      action = { type: 'order', orders: [], grouping: 'na' }
      expect(described_class.payload_action(action)).to equal(action)
    end

    it 'handles string-keyed inner actions (e.g. parsed from JSON)' do
      action = { 'type' => 'userSetAbstraction', 'abstraction' => 'disabled' }
      result = described_class.payload_action(action)
      expect(result['abstraction']).to eq('i')
    end

    it 'build_envelope routes userSetAbstraction inner action through wire-form normalization' do
      envelope = described_class.build_envelope(
        inner_action: { type: 'userSetAbstraction', abstraction: 'disabled', user: '0x1' },
        multi_sig_user: '0x0000000000000000000000000000000000000005',
        outer_signer: '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A',
        signatures: []
      )
      expect(envelope[:payload][:action][:abstraction]).to eq('i')
    end
  end

  describe '.envelope_action_hash' do
    it 'matches Python SDK byte-parity for the multi-sig envelope (Fixture A: empty signatures + noop inner)' do
      envelope = described_class.build_envelope(
        inner_action: { type: 'noop' },
        multi_sig_user: multi_sig_user,
        outer_signer: outer_signer,
        signatures: []
      )
      hash = described_class.envelope_action_hash(envelope: envelope, nonce: fixture_nonce)
      expect(hash).to eq('0x897feed4f5053a54739850d8af2354f592b667b27cab36a917afe8333fec2156')
    end
  end

  describe '.sign_as_co_signer_l1' do
    it 'signs the [multi_sig_user, outer_signer, action] phantom-agent envelope (Fixture B co-signer)' do
      inner_order = {
        type: 'order',
        orders: [{ a: 4, b: true, p: '1100', s: '0.2', r: false, t: { limit: { tif: 'Gtc' } } }],
        grouping: 'na'
      }
      sig = described_class.sign_as_co_signer_l1(
        signer: fixture_signer,
        inner_action: inner_order,
        multi_sig_user: multi_sig_user,
        outer_signer: outer_signer,
        nonce: fixture_nonce
      )
      expect(sig[:r]).to eq('0x9635450d1274007c5b83f819654b4994af3e76d732f99c677ed82058eae640d4')
      expect(sig[:s]).to eq('0x7b8beeb8dc6e70adde2df6defe73fea946d061ae1255482c1e2d0a54e6c9f3ec')
      expect(sig[:v]).to eq(27)
    end
  end

  describe '.sign_as_co_signer_user_signed' do
    it 'enriches inner action with payloadMultiSigUser+outerSigner and signs (Fixture C)' do
      send_asset_action = {
        type: 'sendAsset',
        destination: '0x0000000000000000000000000000000000000000',
        sourceDex: '',
        destinationDex: '',
        token: 'USDC',
        amount: '100.0',
        fromSubAccount: '',
        nonce: fixture_nonce
      }
      sig = described_class.sign_as_co_signer_user_signed(
        signer: fixture_signer,
        inner_action: send_asset_action,
        multi_sig_user: multi_sig_user,
        outer_signer: outer_signer,
        primary_type: 'HyperliquidTransaction:SendAsset',
        sign_types: Hyperliquid::Signing::EIP712::SEND_ASSET_TYPES
      )
      expect(sig[:r]).to eq('0x888d2aef4c2485bea4c74568157c04886e89509dea6ac0fd9c44e854f0c228d7')
      expect(sig[:s]).to eq('0x2b96e934360dccc295e085dfb0ed55d4c297dc857132f091c832c183379fb51e')
      expect(sig[:v]).to eq(27)
    end

    it 'inserts payloadMultiSigUser+outerSigner address fields right after hyperliquidChain' do
      enriched = described_class.send(:enrich_user_signed_types,
                                      Hyperliquid::Signing::EIP712::SEND_ASSET_TYPES)
      fields = enriched[:'HyperliquidTransaction:SendAsset']
      names = fields.map { |f| f[:name] }
      expect(names.first(3)).to eq(%i[hyperliquidChain payloadMultiSigUser outerSigner])
      expect(fields[1][:type]).to eq('address')
      expect(fields[2][:type]).to eq('address')
    end
  end
end
