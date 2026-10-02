# frozen_string_literal: true

require 'spec_helper'

# L1 phantom-agent vectors. Rows with `upstream_test` are the published vectors of hyperliquid-python-sdk
# tests/signing_test.py (0.24.0 / 2fdb18f95176), r/s left-padded to 64 hex chars; the others (expires_after,
# vault + expires_after) are captured with the same SDK primitives. Fixture written by
# tools/parity/capture_l1_signing_vectors.py (via tools/parity/regenerate.sh), which aborts if upstream drifts.
RSpec.describe Hyperliquid::Signing::Signer, 'Python SDK L1 vectors' do
  fixture = JSON.parse(File.read(File.expand_path('../../fixtures/parity/l1_signing_vectors.json', __dir__)))

  fixture['vectors'].each do |row|
    describe row['name'] do
      let(:signer) { described_class.new(private_key: fixture['private_key'], testnet: !row['mainnet']) }
      let(:action) { JSON.parse(row['action_json']) }
      let(:options) { { vault_address: row['vault_address'], expires_after: row['expires_after'] } }

      it 'reproduces the signature' do
        signature = signer.sign_l1_action(action, row['nonce'], **options)

        expect(signature).to eq(r: row['r'], s: row['s'], v: row['v'])
      end
    end
  end

  describe 'phantom agent for a production ETH order placed through Exchange#order' do
    phantom = fixture['phantom_agent']
    base_url = Hyperliquid::Constants::MAINNET_API_URL

    let(:client) { Hyperliquid::Client.new(base_url: base_url) }
    let(:exchange) do
      Hyperliquid::Exchange.new(
        client: client,
        signer: described_class.new(private_key: fixture['private_key'], testnet: !phantom['mainnet']),
        info: Hyperliquid::Info.new(client),
        testnet: !phantom['mainnet']
      )
    end
    # ETH is asset 4 in the upstream test
    let(:meta) { { universe: %w[BTC SOL ARB DOGE ETH].map { |name| { name: name, szDecimals: 4 } } } }

    it 'derives the upstream connectionId from the posted order' do
      stub_request(:post, "#{base_url}/info").with(body: { type: 'meta' }.to_json)
                                             .to_return(status: 200, body: meta.to_json)
      stub_request(:post, "#{base_url}/info").with(body: { type: 'spotMeta' }.to_json)
                                             .to_return(status: 200, body: { universe: [], tokens: [] }.to_json)
      posted = nil
      stub_request(:post, "#{base_url}/exchange").with { |req| posted = req.body }
                                                 .to_return(status: 200, body: '{"status":"ok"}')
      allow(exchange).to receive(:timestamp_ms).and_return(phantom['nonce'])
      hashes = []
      allow(described_class).to receive(:compute_action_hash).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs).tap { |hash| hashes << hash }
      end

      exchange.order(coin: phantom['coin'], is_buy: phantom['is_buy'], size: phantom['sz'],
                     limit_px: phantom['limit_px'], order_type: { limit: { tif: phantom['tif'] } })

      expect(JSON.generate(JSON.parse(posted)['action'])).to eq(phantom['action_json'])
      expect(hashes.uniq).to eq([phantom['connection_id']])
    end
  end
end
