# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Exchange do
  let(:base_url) { Hyperliquid::Constants::TESTNET_API_URL }
  let(:info_endpoint) { "#{base_url}/info" }
  let(:exchange_endpoint) { "#{base_url}/exchange" }
  let(:client) { Hyperliquid::Client.new(base_url: base_url) }
  let(:info) { Hyperliquid::Info.new(client) }

  # Well-known test private key
  let(:test_private_key) { '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' }
  let(:signer) { Hyperliquid::Signing::Signer.new(private_key: test_private_key, testnet: true) }
  let(:exchange) { described_class.new(client: client, signer: signer, info: info) }

  let(:meta_response) do
    {
      'universe' => [
        { 'name' => 'BTC', 'szDecimals' => 5 },
        { 'name' => 'ETH', 'szDecimals' => 4 },
        { 'name' => 'SOL', 'szDecimals' => 3 },
        { 'name' => 'DOGE', 'szDecimals' => 1 }
      ]
    }
  end

  let(:spot_meta_response) do
    {
      'universe' => [
        { 'name' => 'PURR/USDC', 'szDecimals' => 2, 'tokens' => [1, 0] }
      ],
      'tokens' => [
        { 'name' => 'USDC', 'index' => 0 },
        { 'name' => 'PURR', 'index' => 1 }
      ]
    }
  end

  before do
    stub_request(:post, info_endpoint)
      .with(body: { type: 'meta' }.to_json)
      .to_return(status: 200, body: meta_response.to_json)

    stub_request(:post, info_endpoint)
      .with(body: { type: 'spotMeta' }.to_json)
      .to_return(status: 200, body: spot_meta_response.to_json)
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
          'data' => { 'statuses' => [{ 'resting' => { 'oid' => 12_345 } }] }
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

      result = exchange.order(coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000')
      expect(result['status']).to eq('ok')
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

      result = exchange.order(coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000')
      expect(result['status']).to eq('ok')
    end

    it 'includes nonce in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['nonce'].is_a?(Integer) && body['nonce'].positive?
        end
        .to_return(status: 200, body: order_response.to_json)

      result = exchange.order(coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000')
      expect(result['status']).to eq('ok')
    end

    it 'includes client order ID when provided as Cloid' do
      cloid = Hyperliquid::Cloid.from_int(123)

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['orders'][0]['c'] == cloid.to_raw
        end
        .to_return(status: 200, body: order_response.to_json)

      result = exchange.order(
        coin: 'BTC',
        is_buy: true,
        size: '0.01',
        limit_px: '95000',
        cloid: cloid
      )
      expect(result['status']).to eq('ok')
    end

    it 'includes client order ID when provided as string' do
      cloid_str = '0x0000000000000000000000000000007b'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['orders'][0]['c'] == cloid_str
        end
        .to_return(status: 200, body: order_response.to_json)

      result = exchange.order(
        coin: 'BTC',
        is_buy: true,
        size: '0.01',
        limit_px: '95000',
        cloid: cloid_str
      )
      expect(result['status']).to eq('ok')
    end

    it 'raises ArgumentError for invalid cloid string format' do
      expect do
        exchange.order(
          coin: 'BTC',
          is_buy: true,
          size: '0.01',
          limit_px: '95000',
          cloid: 'my-order-123'
        )
      end.to raise_error(ArgumentError, /must be '0x' followed by 32 hex characters/)
    end

    it 'includes vault address when provided' do
      vault_addr = '0x1234567890123456789012345678901234567890'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault_addr
        end
        .to_return(status: 200, body: order_response.to_json)

      result = exchange.order(
        coin: 'BTC',
        is_buy: true,
        size: '0.01',
        limit_px: '95000',
        vault_address: vault_addr
      )
      expect(result['status']).to eq('ok')
    end

    it 'raises ArgumentError for unknown asset' do
      expect do
        exchange.order(coin: 'UNKNOWN', is_buy: true, size: '1', limit_px: '100')
      end.to raise_error(ArgumentError, /Unknown asset/)
    end

    context 'with trigger types' do
      it 'places stop loss order' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            order = body['action']['orders'][0]
            trigger = order['t']['trigger']

            trigger['tpsl'] == 'sl' &&
              trigger['isMarket'] == true &&
              trigger['triggerPx'].is_a?(String)
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.order(
          coin: 'BTC',
          is_buy: false,
          size: '0.1',
          limit_px: '89900',
          order_type: {
            trigger: {
              trigger_px: 90_000,
              is_market: true,
              tpsl: 'sl'
            }
          }
        )
        expect(result['status']).to eq('ok')
      end

      it 'places take profit order' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            trigger = body['action']['orders'][0]['t']['trigger']
            trigger['tpsl'] == 'tp'
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.order(
          coin: 'BTC',
          is_buy: false,
          size: '0.1',
          limit_px: '100100',
          order_type: {
            trigger: {
              trigger_px: 100_000,
              is_market: false,
              tpsl: 'tp'
            }
          }
        )
        expect(result['status']).to eq('ok')
      end

      it 'formats triggerPx with float_to_wire (no scientific notation)' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            trigger_px = body['action']['orders'][0]['t']['trigger']['triggerPx']
            !trigger_px.include?('e') && !trigger_px.include?('E')
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.order(
          coin: 'BTC',
          is_buy: false,
          size: '0.1',
          limit_px: '89900',
          order_type: {
            trigger: {
              trigger_px: 0.00001,
              is_market: true,
              tpsl: 'sl'
            }
          }
        )
        expect(result['status']).to eq('ok')
      end

      it 'raises error for missing trigger_px' do
        expect do
          exchange.order(
            coin: 'BTC',
            is_buy: false,
            size: '0.1',
            limit_px: '89900',
            order_type: {
              trigger: {
                is_market: true,
                tpsl: 'sl'
              }
            }
          )
        end.to raise_error(ArgumentError, /require :trigger_px/)
      end

      it 'raises error for missing tpsl' do
        expect do
          exchange.order(
            coin: 'BTC',
            is_buy: false,
            size: '0.1',
            limit_px: '89900',
            order_type: {
              trigger: {
                trigger_px: 90_000,
                is_market: true
              }
            }
          )
        end.to raise_error(ArgumentError, /require :tpsl/)
      end

      it 'raises error for invalid tpsl value' do
        expect do
          exchange.order(
            coin: 'BTC',
            is_buy: false,
            size: '0.1',
            limit_px: '89900',
            order_type: {
              trigger: {
                trigger_px: 90_000,
                is_market: true,
                tpsl: 'invalid'
              }
            }
          )
        end.to raise_error(ArgumentError, /must be 'tp' or 'sl'/)
      end
    end

    context 'with wire formatting' do
      it 'formats prices without scientific notation' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            price = body['action']['orders'][0]['p']
            !price.include?('e') && !price.include?('E')
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.order(
          coin: 'BTC',
          is_buy: true,
          size: '0.00001',
          limit_px: '0.00001'
        )
        expect(result['status']).to eq('ok')
      end

      it 'normalizes trailing zeros' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            price = body['action']['orders'][0]['p']
            # 95000.00 should become "95000"
            price == '95000'
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.order(
          coin: 'BTC',
          is_buy: true,
          size: '0.01',
          limit_px: '95000.00'
        )
        expect(result['status']).to eq('ok')
      end
    end

    context 'with expires_after' do
      let(:expires_after) { (Time.now.to_f * 1000).to_i + 30_000 }
      let(:exchange_with_expiry) do
        described_class.new(
          client: client,
          signer: signer,
          info: info,
          expires_after: expires_after
        )
      end

      it 'includes expiresAfter in payload' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['expiresAfter'] == expires_after
          end
          .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

        result = exchange_with_expiry.order(
          coin: 'BTC',
          is_buy: true,
          size: '0.01',
          limit_px: '95000'
        )
        expect(result['status']).to eq('ok')
      end
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

      result = exchange.bulk_orders(orders: orders, grouping: 'normalTpsl')
      expect(result['status']).to eq('ok')
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

    it 'applies slippage correctly for buy orders (price increases)' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          limit_px = body['action']['orders'][0]['p'].to_f
          # 96000 * 1.05 = 100800, rounded per algorithm
          limit_px > 100_000
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      result = exchange.market_order(coin: 'BTC', is_buy: true, size: '0.01', slippage: 0.05)
      expect(result['status']).to eq('ok')
    end

    it 'applies slippage correctly for sell orders (price decreases)' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          limit_px = body['action']['orders'][0]['p'].to_f
          # 96000 * 0.95 = 91200
          limit_px < 92_000
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      result = exchange.market_order(coin: 'BTC', is_buy: false, size: '0.01', slippage: 0.05)
      expect(result['status']).to eq('ok')
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

    it 'cancels order by client order ID (Cloid object)' do
      cloid = Hyperliquid::Cloid.from_int(123)

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancelByCloid' &&
            action['cancels'][0]['asset'] == 0 &&
            action['cancels'][0]['cloid'] == cloid.to_raw
        end
        .to_return(status: 200, body: cancel_response.to_json)

      result = exchange.cancel_by_cloid(coin: 'BTC', cloid: cloid)
      expect(result['status']).to eq('ok')
    end

    it 'cancels order by client order ID (string)' do
      cloid_str = '0x0000000000000000000000000000007b'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancelByCloid' &&
            action['cancels'][0]['cloid'] == cloid_str
        end
        .to_return(status: 200, body: cancel_response.to_json)

      result = exchange.cancel_by_cloid(coin: 'BTC', cloid: cloid_str)
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
  end

  describe '#bulk_cancel_by_cloid' do
    let(:bulk_cancel_response) do
      {
        'status' => 'ok',
        'response' => { 'type' => 'cancel', 'data' => { 'statuses' => %w[success success] } }
      }
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
        { coin: 'BTC', cloid: Hyperliquid::Cloid.from_int(1) },
        { coin: 'ETH', cloid: Hyperliquid::Cloid.from_int(2) }
      ]

      result = exchange.bulk_cancel_by_cloid(cancels: cancels)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#modify_order' do
    let(:modify_response) do
      {
        'status' => 'ok',
        'response' => {
          'type' => 'batchModify',
          'data' => { 'statuses' => [{ 'filled' => { 'oid' => 99_999 } }] }
        }
      }
    end

    it 'modifies an order with integer oid' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'batchModify' &&
            action['modifies'].length == 1 &&
            action['modifies'][0]['oid'] == 12_345 &&
            action['modifies'][0]['order']['a'] == 0 &&
            action['modifies'][0]['order']['b'] == true &&
            action['modifies'][0]['order']['p'].is_a?(String) &&
            action['modifies'][0]['order']['s'].is_a?(String) &&
            action['modifies'][0]['order']['r'] == false &&
            action['modifies'][0]['order']['t'].is_a?(Hash)
        end
        .to_return(status: 200, body: modify_response.to_json)

      result = exchange.modify_order(
        oid: 12_345,
        coin: 'BTC',
        is_buy: true,
        size: '0.02',
        limit_px: '96000'
      )
      expect(result['status']).to eq('ok')
    end

    it 'modifies an order with Cloid oid' do
      cloid = Hyperliquid::Cloid.from_int(456)

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['modifies'][0]['oid'] == cloid.to_raw
        end
        .to_return(status: 200, body: modify_response.to_json)

      result = exchange.modify_order(
        oid: cloid,
        coin: 'BTC',
        is_buy: true,
        size: '0.02',
        limit_px: '96000'
      )
      expect(result['status']).to eq('ok')
    end

    it 'includes signature and nonce' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['signature'].is_a?(Hash) &&
            body['signature']['r']&.start_with?('0x') &&
            body['nonce'].is_a?(Integer) && body['nonce'].positive?
        end
        .to_return(status: 200, body: modify_response.to_json)

      result = exchange.modify_order(
        oid: 12_345,
        coin: 'BTC',
        is_buy: true,
        size: '0.02',
        limit_px: '96000'
      )
      expect(result['status']).to eq('ok')
    end

    it 'supports vault_address' do
      vault_addr = '0x1234567890123456789012345678901234567890'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault_addr
        end
        .to_return(status: 200, body: modify_response.to_json)

      result = exchange.modify_order(
        oid: 12_345,
        coin: 'BTC',
        is_buy: true,
        size: '0.02',
        limit_px: '96000',
        vault_address: vault_addr
      )
      expect(result['status']).to eq('ok')
    end

    it 'raises ArgumentError for invalid oid type' do
      expect do
        exchange.modify_order(
          oid: 12.5,
          coin: 'BTC',
          is_buy: true,
          size: '0.02',
          limit_px: '96000'
        )
      end.to raise_error(ArgumentError, /oid must be Integer, Cloid, or String/)
    end
  end

  describe '#batch_modify' do
    let(:batch_modify_response) do
      {
        'status' => 'ok',
        'response' => {
          'type' => 'batchModify',
          'data' => {
            'statuses' => [
              { 'filled' => { 'oid' => 99_999 } },
              { 'filled' => { 'oid' => 99_998 } }
            ]
          }
        }
      }
    end

    it 'modifies multiple orders' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'batchModify' &&
            action['modifies'].length == 2
        end
        .to_return(status: 200, body: batch_modify_response.to_json)

      modifies = [
        { oid: 111, coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000' },
        { oid: 222, coin: 'ETH', is_buy: false, size: '0.5', limit_px: '3200' }
      ]

      result = exchange.batch_modify(modifies: modifies)
      expect(result['status']).to eq('ok')
    end

    it 'includes oid and order wire fields in each entry' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          m = body['action']['modifies'][0]
          m['oid'] == 111 &&
            m['order']['a'].is_a?(Integer) &&
            m['order']['b'] == true &&
            m['order']['p'].is_a?(String) &&
            m['order']['s'].is_a?(String) &&
            m['order']['r'] == false &&
            m['order']['t'].is_a?(Hash)
        end
        .to_return(status: 200, body: batch_modify_response.to_json)

      modifies = [
        { oid: 111, coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000' },
        { oid: 222, coin: 'ETH', is_buy: false, size: '0.5', limit_px: '3200' }
      ]

      result = exchange.batch_modify(modifies: modifies)
      expect(result['status']).to eq('ok')
    end

    it 'supports mixed oid types (Integer and Cloid)' do
      cloid = Hyperliquid::Cloid.from_int(789)

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          modifies = body['action']['modifies']
          modifies[0]['oid'] == 111 &&
            modifies[1]['oid'] == cloid.to_raw
        end
        .to_return(status: 200, body: batch_modify_response.to_json)

      modifies = [
        { oid: 111, coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000' },
        { oid: cloid, coin: 'ETH', is_buy: false, size: '0.5', limit_px: '3200' }
      ]

      result = exchange.batch_modify(modifies: modifies)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#update_leverage' do
    let(:leverage_response) do
      { 'status' => 'ok', 'response' => { 'type' => 'updateLeverage' } }
    end

    it 'sets cross leverage' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'updateLeverage' &&
            action['isCross'] == true &&
            action['leverage'] == 5 &&
            action['asset'] == 0
        end
        .to_return(status: 200, body: leverage_response.to_json)

      result = exchange.update_leverage(coin: 'BTC', leverage: 5)
      expect(result['status']).to eq('ok')
    end

    it 'sets isolated leverage' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['isCross'] == false && action['leverage'] == 10
        end
        .to_return(status: 200, body: leverage_response.to_json)

      result = exchange.update_leverage(coin: 'BTC', leverage: 10, is_cross: false)
      expect(result['status']).to eq('ok')
    end

    it 'resolves asset index correctly' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['asset'] == 1 # ETH is index 1
        end
        .to_return(status: 200, body: leverage_response.to_json)

      result = exchange.update_leverage(coin: 'ETH', leverage: 3)
      expect(result['status']).to eq('ok')
    end

    it 'raises ArgumentError for unknown asset' do
      expect do
        exchange.update_leverage(coin: 'UNKNOWN', leverage: 5)
      end.to raise_error(ArgumentError, /Unknown asset/)
    end
  end

  describe '#update_isolated_margin' do
    let(:margin_response) do
      { 'status' => 'ok', 'response' => { 'type' => 'updateIsolatedMargin' } }
    end

    it 'adds margin with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'updateIsolatedMargin' &&
            action['asset'] == 0 &&
            action['isBuy'] == true &&
            action['ntli'].is_a?(Integer)
        end
        .to_return(status: 200, body: margin_response.to_json)

      result = exchange.update_isolated_margin(coin: 'BTC', amount: 100)
      expect(result['status']).to eq('ok')
    end

    it 'converts amount to USD int correctly' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['ntli'] == 100_500_000
        end
        .to_return(status: 200, body: margin_response.to_json)

      result = exchange.update_isolated_margin(coin: 'BTC', amount: 100.5)
      expect(result['status']).to eq('ok')
    end

    it 'includes signature' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['signature'].is_a?(Hash) &&
            body['signature']['r']&.start_with?('0x')
        end
        .to_return(status: 200, body: margin_response.to_json)

      result = exchange.update_isolated_margin(coin: 'BTC', amount: 50)
      expect(result['status']).to eq('ok')
    end

    it 'raises ArgumentError for amount that causes rounding' do
      expect do
        exchange.update_isolated_margin(coin: 'BTC', amount: 100.0000019)
      end.to raise_error(ArgumentError, /float_to_usd_int causes rounding/)
    end
  end

  describe '#schedule_cancel' do
    let(:schedule_response) do
      { 'status' => 'ok', 'response' => { 'type' => 'scheduleCancel' } }
    end

    it 'schedules cancel with time' do
      cancel_time = 1_700_000_000_000

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'scheduleCancel' &&
            action['time'] == cancel_time
        end
        .to_return(status: 200, body: schedule_response.to_json)

      result = exchange.schedule_cancel(time: cancel_time)
      expect(result['status']).to eq('ok')
    end

    it 'schedules cancel without time' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'scheduleCancel' &&
            !action.key?('time')
        end
        .to_return(status: 200, body: schedule_response.to_json)

      result = exchange.schedule_cancel
      expect(result['status']).to eq('ok')
    end
  end

  describe '#usd_send' do
    let(:send_response) { { 'status' => 'ok', 'response' => { 'type' => 'usdSend' } } }

    it 'sends USD with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'usdSend' &&
            action['destination'] == '0x1234567890123456789012345678901234567890' &&
            action['amount'] == '100' &&
            action['time'].is_a?(Integer) &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet'
        end
        .to_return(status: 200, body: send_response.to_json)

      result = exchange.usd_send(
        amount: 100,
        destination: '0x1234567890123456789012345678901234567890'
      )
      expect(result['status']).to eq('ok')
    end

    it 'includes signature in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['signature'].is_a?(Hash) &&
            body['signature']['r']&.start_with?('0x')
        end
        .to_return(status: 200, body: send_response.to_json)

      result = exchange.usd_send(amount: '50', destination: '0x1234567890123456789012345678901234567890')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#spot_send' do
    let(:send_response) { { 'status' => 'ok', 'response' => { 'type' => 'spotSend' } } }

    it 'sends spot token with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'spotSend' &&
            action['destination'] == '0x1234567890123456789012345678901234567890' &&
            action['token'] == 'PURR' &&
            action['amount'] == '10' &&
            action['time'].is_a?(Integer) &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet'
        end
        .to_return(status: 200, body: send_response.to_json)

      result = exchange.spot_send(
        amount: 10,
        destination: '0x1234567890123456789012345678901234567890',
        token: 'PURR'
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#usd_class_transfer' do
    let(:transfer_response) { { 'status' => 'ok', 'response' => { 'type' => 'usdClassTransfer' } } }

    it 'transfers to perp with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'usdClassTransfer' &&
            action['amount'] == '100' &&
            action['toPerp'] == true &&
            action['nonce'].is_a?(Integer) &&
            action['signatureChainId'] == '0x66eee'
        end
        .to_return(status: 200, body: transfer_response.to_json)

      result = exchange.usd_class_transfer(amount: 100, to_perp: true)
      expect(result['status']).to eq('ok')
    end

    it 'transfers to spot with toPerp false' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['toPerp'] == false
        end
        .to_return(status: 200, body: transfer_response.to_json)

      result = exchange.usd_class_transfer(amount: 50, to_perp: false)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#withdraw_from_bridge' do
    let(:withdraw_response) { { 'status' => 'ok', 'response' => { 'type' => 'withdraw3' } } }

    it 'withdraws with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'withdraw3' &&
            action['destination'] == '0x1234567890123456789012345678901234567890' &&
            action['amount'] == '100' &&
            action['time'].is_a?(Integer) &&
            action['signatureChainId'] == '0x66eee'
        end
        .to_return(status: 200, body: withdraw_response.to_json)

      result = exchange.withdraw_from_bridge(
        amount: 100,
        destination: '0x1234567890123456789012345678901234567890'
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#send_asset' do
    let(:send_response) { { 'status' => 'ok', 'response' => { 'type' => 'sendAsset' } } }

    it 'sends asset with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'sendAsset' &&
            action['destination'] == '0x1234567890123456789012345678901234567890' &&
            action['sourceDex'] == 'dex1' &&
            action['destinationDex'] == 'dex2' &&
            action['token'] == 'USDC' &&
            action['amount'] == '100' &&
            action['fromSubAccount'] == '' &&
            action['nonce'].is_a?(Integer) &&
            action['signatureChainId'] == '0x66eee'
        end
        .to_return(status: 200, body: send_response.to_json)

      result = exchange.send_asset(
        destination: '0x1234567890123456789012345678901234567890',
        source_dex: 'dex1',
        destination_dex: 'dex2',
        token: 'USDC',
        amount: 100
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#create_sub_account' do
    let(:create_response) { { 'status' => 'ok', 'response' => { 'type' => 'createSubAccount' } } }

    it 'creates sub-account with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'createSubAccount' &&
            action['name'] == 'my-sub' &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: create_response.to_json)

      result = exchange.create_sub_account(name: 'my-sub')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#sub_account_transfer' do
    let(:transfer_response) { { 'status' => 'ok', 'response' => { 'type' => 'subAccountTransfer' } } }

    it 'deposits USD to sub-account with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'subAccountTransfer' &&
            action['subAccountUser'] == '0x1234567890123456789012345678901234567890' &&
            action['isDeposit'] == true &&
            action['usd'] == 10_000_000
        end
        .to_return(status: 200, body: transfer_response.to_json)

      result = exchange.sub_account_transfer(
        sub_account_user: '0x1234567890123456789012345678901234567890',
        is_deposit: true,
        usd: 10
      )
      expect(result['status']).to eq('ok')
    end

    it 'withdraws USD from sub-account' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['isDeposit'] == false && action['usd'] == 5_000_000
        end
        .to_return(status: 200, body: transfer_response.to_json)

      result = exchange.sub_account_transfer(
        sub_account_user: '0x1234567890123456789012345678901234567890',
        is_deposit: false,
        usd: 5
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#sub_account_spot_transfer' do
    let(:transfer_response) { { 'status' => 'ok', 'response' => { 'type' => 'subAccountSpotTransfer' } } }

    it 'transfers spot tokens to sub-account with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'subAccountSpotTransfer' &&
            action['subAccountUser'] == '0x1234567890123456789012345678901234567890' &&
            action['isDeposit'] == true &&
            action['token'] == 'PURR' &&
            action['amount'] == '100'
        end
        .to_return(status: 200, body: transfer_response.to_json)

      result = exchange.sub_account_spot_transfer(
        sub_account_user: '0x1234567890123456789012345678901234567890',
        is_deposit: true,
        token: 'PURR',
        amount: 100
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#vault_transfer' do
    let(:vault_response) { { 'status' => 'ok', 'response' => { 'type' => 'vaultTransfer' } } }

    it 'deposits to vault with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'vaultTransfer' &&
            action['vaultAddress'] == '0x1234567890123456789012345678901234567890' &&
            action['isDeposit'] == true &&
            action['usd'] == 10_000_000
        end
        .to_return(status: 200, body: vault_response.to_json)

      result = exchange.vault_transfer(
        vault_address: '0x1234567890123456789012345678901234567890',
        is_deposit: true,
        usd: 10
      )
      expect(result['status']).to eq('ok')
    end

    it 'withdraws from vault' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['isDeposit'] == false && action['usd'] == 5_000_000
        end
        .to_return(status: 200, body: vault_response.to_json)

      result = exchange.vault_transfer(
        vault_address: '0x1234567890123456789012345678901234567890',
        is_deposit: false,
        usd: 5
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#set_referrer' do
    let(:referrer_response) { { 'status' => 'ok', 'response' => { 'type' => 'setReferrer' } } }

    it 'sets referrer with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'setReferrer' &&
            action['code'] == 'MY_CODE' &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: referrer_response.to_json)

      result = exchange.set_referrer(code: 'MY_CODE')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#market_close' do
    let(:user_state_response) do
      {
        'assetPositions' => [
          {
            'position' => {
              'coin' => 'BTC',
              'szi' => '0.05'
            }
          },
          {
            'position' => {
              'coin' => 'ETH',
              'szi' => '-1.5'
            }
          }
        ],
        'marginSummary' => {}
      }
    end

    let(:mids_response) { { 'BTC' => '96000', 'ETH' => '3100' } }

    before do
      stub_request(:post, info_endpoint)
        .with(body: hash_including('type' => 'clearinghouseState'))
        .to_return(status: 200, body: user_state_response.to_json)

      stub_request(:post, info_endpoint)
        .with(body: { type: 'allMids' }.to_json)
        .to_return(status: 200, body: mids_response.to_json)
    end

    it 'closes long position with sell IoC order' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          order = body['action']['orders'][0]
          order['b'] == false && # sell to close long
            order['r'] == true && # reduce_only
            order['t']['limit']['tif'] == 'Ioc'
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      result = exchange.market_close(coin: 'BTC')
      expect(result['status']).to eq('ok')
    end

    it 'closes short position with buy IoC order' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          order = body['action']['orders'][0]
          order['b'] == true # buy to close short
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      result = exchange.market_close(coin: 'ETH')
      expect(result['status']).to eq('ok')
    end

    it 'uses correct position size from user_state' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          order = body['action']['orders'][0]
          order['s'] == '0.05' # BTC position size
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      result = exchange.market_close(coin: 'BTC')
      expect(result['status']).to eq('ok')
    end

    it 'custom size parameter overrides position size' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          order = body['action']['orders'][0]
          order['s'] == '0.02'
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      result = exchange.market_close(coin: 'BTC', size: 0.02)
      expect(result['status']).to eq('ok')
    end

    it 'raises ArgumentError when no position found' do
      expect do
        exchange.market_close(coin: 'SOL')
      end.to raise_error(ArgumentError, /No open position found for SOL/)
    end

    it 'applies slippage correctly for closing long (sell side)' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          limit_px = body['action']['orders'][0]['p'].to_f
          # Selling with slippage: 96000 * 0.95 = 91200
          limit_px < 92_000
        end
        .to_return(status: 200, body: { 'status' => 'ok' }.to_json)

      result = exchange.market_close(coin: 'BTC', slippage: 0.05)
      expect(result['status']).to eq('ok')
    end
  end
end
