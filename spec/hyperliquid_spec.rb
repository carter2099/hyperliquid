# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid do
  describe '.new' do
    it 'targets mainnet by default' do
      sdk = Hyperliquid.new
      expect(sdk).to be_a(Hyperliquid::SDK)
      expect(sdk.testnet?).to be false
      expect(sdk.base_url).to eq(Hyperliquid::Constants::MAINNET_API_URL)
    end

    it 'targets testnet when testnet: true' do
      sdk = Hyperliquid.new(testnet: true)
      expect(sdk.testnet?).to be true
      expect(sdk.base_url).to eq(Hyperliquid::Constants::TESTNET_API_URL)
    end

    it 'has no exchange without a private key' do
      expect(Hyperliquid.new.exchange).to be_nil
      expect(Hyperliquid.new(testnet: true).exchange).to be_nil
    end

    it 'routes info reads to the network API host' do
      { false => 'https://api.hyperliquid.xyz/info',
        true => 'https://api.hyperliquid-testnet.xyz/info' }.each do |testnet, url|
        stub_request(:post, url).with(body: { type: 'allMids' }.to_json).to_return(status: 200, body: '{"BTC":"1"}')
        expect(Hyperliquid.new(testnet: testnet).info.all_mids).to eq('BTC' => '1')
      end
    end

    it 'routes explorer reads to the network RPC host' do
      { false => 'https://rpc.hyperliquid.xyz/explorer',
        true => 'https://rpc.hyperliquid-testnet.xyz/explorer' }.each do |testnet, url|
        stub_request(:post, url).with(body: { type: 'txDetails', hash: '0xabc' }.to_json)
                                .to_return(status: 200, body: '{"type":"txDetails"}')
        expect(Hyperliquid.new(testnet: testnet).info.tx_details('0xabc')).to eq('type' => 'txDetails')
      end
    end

    it 'retries info reads only when retry_enabled: true' do
      url = 'https://api.hyperliquid.xyz/info'
      allow_any_instance_of(Faraday::Retry::Middleware).to receive(:sleep)

      stub_request(:post, url).to_return({ status: 503, body: '{}' }, { status: 200, body: '{"BTC":"1"}' })
      expect(Hyperliquid.new(retry_enabled: true).info.all_mids).to eq('BTC' => '1')
      expect(a_request(:post, url)).to have_been_made.times(2)

      WebMock.reset!
      stub_request(:post, url).to_return({ status: 503, body: '{}' }, { status: 200, body: '{"BTC":"1"}' })
      expect { Hyperliquid.new.info.all_mids }.to raise_error(Hyperliquid::ServerError)
      expect(a_request(:post, url)).to have_been_made.once
    end

    describe 'exchange wiring' do
      let(:private_key) { "0x#{'ab' * 32}" }
      let(:expires_after) { 1_900_000_000_000 }
      let(:address) { Eth::Key.new(priv: private_key).address.to_s }

      def posted_noop(url, sdk)
        body = nil
        stub_request(:post, url).to_return do |request|
          body = JSON.parse(request.body)
          { status: 200, body: { status: 'ok', response: { type: 'default' } }.to_json }
        end
        sdk.exchange.noop
        body
      end

      def recover_signer(body, source)
        connection_id = Hyperliquid::Signing::Signer.compute_action_hash(
          body['action'], body['nonce'], expires_after: body['expiresAfter']
        )
        eip712 = Hyperliquid::Signing::EIP712
        typed_data = {
          types: { EIP712Domain: eip712.domain_type, Agent: eip712.agent_type },
          primaryType: 'Agent',
          domain: eip712.l1_action_domain,
          message: { source: source, connectionId: connection_id }
        }
        sig = body['signature']
        hex = "#{sig['r'].delete_prefix('0x')}#{sig['s'].delete_prefix('0x')}#{sig['v'].to_s(16)}"
        public_key = Eth::Signature.recover(Eth::Eip712.hash(typed_data), hex)
        Eth::Util.public_key_to_address(public_key).to_s
      end

      it 'signs testnet actions with source b and the global expires_after, posted to the testnet host' do
        sdk = Hyperliquid.new(testnet: true, private_key: private_key, expires_after: expires_after)
        body = posted_noop('https://api.hyperliquid-testnet.xyz/exchange', sdk)

        expect(body['action']).to eq('type' => 'noop')
        expect(body['expiresAfter']).to eq(expires_after)
        expect(recover_signer(body, 'b')).to eq(address)
        expect(recover_signer(body, 'a')).not_to eq(address)
      end

      it 'signs mainnet actions with source a, posted to the mainnet host' do
        sdk = Hyperliquid.new(private_key: private_key)
        body = posted_noop('https://api.hyperliquid.xyz/exchange', sdk)

        expect(body).not_to have_key('expiresAfter')
        expect(recover_signer(body, 'a')).to eq(address)
        expect(recover_signer(body, 'b')).not_to eq(address)
      end
    end

    describe 'websocket wiring' do
      let(:mock_ws) do
        instance_double('WSLite::Client').tap do |ws|
          allow(ws).to receive(:on)
          allow(ws).to receive(:send)
          allow(ws).to receive(:close)
        end
      end

      {
        false => %w[wss://api.hyperliquid.xyz/ws wss://rpc.hyperliquid.xyz/ws],
        true => %w[wss://api.hyperliquid-testnet.xyz/ws wss://rpc.hyperliquid-testnet.xyz/ws]
      }.each do |testnet, (api_ws_url, explorer_ws_url)|
        it "connects to the #{testnet ? 'testnet' : 'mainnet'} API and explorer WebSocket hosts" do
          ws = Hyperliquid.new(testnet: testnet).ws
          expect(WSLite).to receive(:connect).with(api_ws_url).and_return(mock_ws)
          expect(WSLite).to receive(:connect).with(explorer_ws_url).and_return(mock_ws)

          ws.subscribe({ type: 'allMids' }) { |_d| }
          ws.subscribe_explorer_block { |_d| }
        ensure
          ws&.close
        end
      end
    end
  end
end
