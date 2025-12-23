# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Exchange do
  let(:base_url) { Hyperliquid::Constants::TESTNET_API_URL }
  let(:info_endpoint) { "#{base_url}/info" }
  let(:exchange_endpoint) { "#{base_url}/exchange" }
  let(:client) { Hyperliquid::Client.new(base_url: base_url) }
  let(:info) { Hyperliquid::Info.new(client) }

  # Test private key (DO NOT use in production)
  let(:test_private_key) { '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' }
  let(:signer) { Hyperliquid::Signing::Signer.new(private_key: test_private_key, mainnet: false) }
  let(:exchange) { described_class.new(client: client, signer: signer, info: info) }

  let(:meta_response) do
    {
      'universe' => [
        { 'name' => 'BTC', 'szDecimals' => 5 },
        { 'name' => 'ETH', 'szDecimals' => 4 },
        { 'name' => 'SOL', 'szDecimals' => 2 }
      ]
    }
  end

  before do
    # Stub metadata endpoint for asset index lookups
    stub_request(:post, info_endpoint)
      .with(body: { type: 'meta' }.to_json)
      .to_return(status: 200, body: meta_response.to_json)
  end

  describe '#address' do
    it 'returns the wallet address from signer' do
      expect(exchange.address).to eq(signer.address)
    end
  end

  describe '#order' do
    let(:order_response) do
      {
        'status' => 'ok',
        'response' => {
          'type' => 'order',
          'data' => {
            'statuses' => [{ 'resting' => { 'oid' => 12_345 } }]
          }
        }
      }
    end

    it 'places a limit buy order' do
      stub_request(:post, exchange_endpoint)
        .with { |req| JSON.parse(req.body)['action']['type'] == 'order' }
        .to_return(status: 200, body: order_response.to_json)

      result = exchange.order(
        coin: 'BTC',
        is_buy: true,
        size: '0.01',
        limit_px: '95000'
      )

      expect(result['status']).to eq('ok')
    end

    it 'places a limit sell order' do
      stub_request(:post, exchange_endpoint)
        .with { |req| JSON.parse(req.body)['action']['type'] == 'order' }
        .to_return(status: 200, body: order_response.to_json)

      result = exchange.order(
        coin: 'ETH',
        is_buy: false,
        size: '1.5',
        limit_px: '3200'
      )

      expect(result['status']).to eq('ok')
    end

    it 'includes correct action structure in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']

          action['type'] == 'order' &&
            action['orders'].is_a?(Array) &&
            action['orders'].length == 1 &&
            action['grouping'] == 'na'
        end
        .to_return(status: 200, body: order_response.to_json)

      exchange.order(coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000')
    end

    it 'includes signature in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          signature = body['signature']

          signature.is_a?(Hash) &&
            signature['r']&.start_with?('0x') &&
            signature['s']&.start_with?('0x') &&
            signature['v'].is_a?(Integer)
        end
        .to_return(status: 200, body: order_response.to_json)

      exchange.order(coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000')
    end

    it 'includes nonce in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['nonce'].is_a?(Integer) && body['nonce'] > 0
        end
        .to_return(status: 200, body: order_response.to_json)

      exchange.order(coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000')
    end

    it 'includes client order ID when provided' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['orders'][0]['c'] == 'my-order-123'
        end
        .to_return(status: 200, body: order_response.to_json)

      exchange.order(
        coin: 'BTC',
        is_buy: true,
        size: '0.01',
        limit_px: '95000',
        cloid: 'my-order-123'
      )
    end

    it 'includes vault address when provided' do
      vault_addr = '0x1234567890123456789012345678901234567890'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault_addr
        end
        .to_return(status: 200, body: order_response.to_json)

      exchange.order(
        coin: 'BTC',
        is_buy: true,
        size: '0.01',
        limit_px: '95000',
        vault_address: vault_addr
      )
    end

    it 'raises ArgumentError for unknown asset' do
      expect do
        exchange.order(coin: 'UNKNOWN', is_buy: true, size: '1', limit_px: '100')
      end.to raise_error(ArgumentError, /Unknown asset/)
    end
  end

  describe '#bulk_orders' do
    let(:bulk_response) do
      {
        'status' => 'ok',
        'response' => {
          'type' => 'order',
          'data' => {
            'statuses' => [
              { 'resting' => { 'oid' => 12_345 } },
              { 'resting' => { 'oid' => 12_346 } }
            ]
          }
        }
      }
    end

    it 'places multiple orders' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['type'] == 'order' &&
            body['action']['orders'].length == 2
        end
        .to_return(status: 200, body: bulk_response.to_json)

      orders = [
        { coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000' },
        { coin: 'ETH', is_buy: false, size: '0.5', limit_px: '3200' }
      ]

      result = exchange.bulk_orders(orders: orders)
      expect(result['status']).to eq('ok')
    end

    it 'supports custom grouping' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['grouping'] == 'normalTpsl'
        end
        .to_return(status: 200, body: bulk_response.to_json)

      orders = [
        { coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000' },
        { coin: 'BTC', is_buy: false, size: '0.01', limit_px: '100000' }
      ]

      exchange.bulk_orders(orders: orders, grouping: 'normalTpsl')
    end
  end

  describe '#market_order' do
    let(:mids_response) { { 'BTC' => '96000', 'ETH' => '3100' } }

    before do
      stub_request(:post, info_endpoint)
        .with(body: { type: 'allMids' }.to_json)
        .to_return(status: 200, body: mids_response.to_json)
    end

    it 'places IoC order with slippage for buy' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          order = body['action']['orders'][0]
          order['t']['limit']['tif'] == 'Ioc'
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      result = exchange.market_order(coin: 'BTC', is_buy: true, size: '0.01')
      expect(result['status']).to eq('ok')
    end

    it 'applies correct slippage for buy orders' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          limit_px = body['action']['orders'][0]['p'].to_f
          # 96000 * 1.05 = 100800
          limit_px > 100_000
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      exchange.market_order(coin: 'BTC', is_buy: true, size: '0.01', slippage: 0.05)
    end

    it 'applies correct slippage for sell orders' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          limit_px = body['action']['orders'][0]['p'].to_f
          # 96000 * 0.95 = 91200
          limit_px < 92_000
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      exchange.market_order(coin: 'BTC', is_buy: false, size: '0.01', slippage: 0.05)
    end

    it 'raises error for unknown asset' do
      stub_request(:post, info_endpoint)
        .with(body: { type: 'allMids' }.to_json)
        .to_return(status: 200, body: {}.to_json)

      expect do
        exchange.market_order(coin: 'UNKNOWN', is_buy: true, size: '1')
      end.to raise_error(ArgumentError, /Unknown asset or no price/)
    end
  end

  describe '#cancel' do
    let(:cancel_response) do
      {
        'status' => 'ok',
        'response' => { 'type' => 'cancel', 'data' => { 'statuses' => ['success'] } }
      }
    end

    it 'cancels order by ID' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancel' &&
            action['cancels'][0]['a'] == 0 && # BTC index
            action['cancels'][0]['o'] == 12_345
        end
        .to_return(status: 200, body: cancel_response.to_json)

      result = exchange.cancel(coin: 'BTC', oid: 12_345)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#cancel_by_cloid' do
    let(:cancel_response) do
      {
        'status' => 'ok',
        'response' => { 'type' => 'cancel', 'data' => { 'statuses' => ['success'] } }
      }
    end

    it 'cancels order by client order ID' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancelByCloid' &&
            action['cancels'][0]['asset'] == 0 &&
            action['cancels'][0]['cloid'] == 'my-order-123'
        end
        .to_return(status: 200, body: cancel_response.to_json)

      result = exchange.cancel_by_cloid(coin: 'BTC', cloid: 'my-order-123')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#bulk_cancel' do
    let(:bulk_cancel_response) do
      {
        'status' => 'ok',
        'response' => { 'type' => 'cancel', 'data' => { 'statuses' => %w[success success] } }
      }
    end

    it 'cancels multiple orders by OID' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancel' && action['cancels'].length == 2
        end
        .to_return(status: 200, body: bulk_cancel_response.to_json)

      cancels = [
        { coin: 'BTC', oid: 12_345 },
        { coin: 'ETH', oid: 12_346 }
      ]

      result = exchange.bulk_cancel(cancels: cancels)
      expect(result['status']).to eq('ok')
    end

    it 'cancels multiple orders by CLOID' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancelByCloid' && action['cancels'].length == 2
        end
        .to_return(status: 200, body: bulk_cancel_response.to_json)

      cancels = [
        { coin: 'BTC', cloid: 'order-1' },
        { coin: 'ETH', cloid: 'order-2' }
      ]

      result = exchange.bulk_cancel(cancels: cancels)
      expect(result['status']).to eq('ok')
    end
  end
end
