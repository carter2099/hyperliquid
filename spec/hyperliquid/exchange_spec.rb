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
  let(:exchange) { described_class.new(client: client, signer: signer, info: info, testnet: true) }

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
          testnet: true,
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

    it 'supports fast cancel flag' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancel' &&
            action['cancels'][0]['f'] == true
        end
        .to_return(status: 200, body: cancel_response.to_json)

      result = exchange.cancel(coin: 'BTC', oid: 12_345, fast: true)
      expect(result['status']).to eq('ok')
    end

    it 'omits fast flag when not specified' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancel' &&
            !action['cancels'][0].key?('f')
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

    it 'supports fast cancel flag' do
      cloid = Hyperliquid::Cloid.from_int(123)

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancelByCloid' &&
            action['cancels'][0]['f'] == true
        end
        .to_return(status: 200, body: cancel_response.to_json)

      result = exchange.cancel_by_cloid(coin: 'BTC', cloid: cloid, fast: true)
      expect(result['status']).to eq('ok')
    end

    it 'omits fast flag when not specified' do
      cloid = Hyperliquid::Cloid.from_int(123)

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cancelByCloid' &&
            !action['cancels'][0].key?('f')
        end
        .to_return(status: 200, body: cancel_response.to_json)

      result = exchange.cancel_by_cloid(coin: 'BTC', cloid: cloid)
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

    it 'supports always_place flag' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['modifies'][0]['a'] == true
        end
        .to_return(status: 200, body: modify_response.to_json)

      result = exchange.modify_order(
        oid: 12_345,
        coin: 'BTC',
        is_buy: true,
        size: '0.02',
        limit_px: '96000',
        always_place: true
      )
      expect(result['status']).to eq('ok')
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

    it 'supports always_place flag on individual entries' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          modifies = body['action']['modifies']
          modifies[0]['a'] == true && !modifies[1].key?('a')
        end
        .to_return(status: 200, body: batch_modify_response.to_json)

      modifies = [
        { oid: 111, coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000', always_place: true },
        { oid: 222, coin: 'ETH', is_buy: false, size: '0.5', limit_px: '3200' }
      ]

      result = exchange.batch_modify(modifies: modifies)
      expect(result['status']).to eq('ok')
    end

    it 'omits always_place flag when not specified' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          modifies = body['action']['modifies']
          modifies.none? { |m| m.key?('a') }
        end
        .to_return(status: 200, body: batch_modify_response.to_json)

      modifies = [
        { oid: 111, coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000' },
        { oid: 222, coin: 'ETH', is_buy: false, size: '0.5', limit_px: '3200' }
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

    context 'with sub_account (TS SDK v0.33.1 amount union)' do
      let(:sub_account_addr) { '0x1234567890123456789012345678901234567890' }

      it 'appends the ` subaccount:<address>` suffix to the signed amount' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            action = body['action']
            action['type'] == 'usdClassTransfer' &&
              action['amount'] == '100 subaccount:0x1234567890123456789012345678901234567890' &&
              action['toPerp'] == true
          end
          .to_return(status: 200, body: transfer_response.to_json)

        result = exchange.usd_class_transfer(amount: 100, to_perp: true, sub_account: sub_account_addr)
        expect(result['status']).to eq('ok')
      end

      it 'passes the sub-account address through verbatim (no lowercasing)' do
        mixed_case = '0xAbCdef0123456789AbCdEf0123456789AbCdEf01'
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['action']['amount'] == "5 subaccount:#{mixed_case}"
          end
          .to_return(status: 200, body: transfer_response.to_json)

        exchange.usd_class_transfer(amount: 5, to_perp: false, sub_account: mixed_case)
      end

      it 'leaves the amount plain when sub_account is omitted (default nil)' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['action']['amount'] == '100' && !body['action']['amount'].to_s.include?('subaccount')
          end
          .to_return(status: 200, body: transfer_response.to_json)

        exchange.usd_class_transfer(amount: 100, to_perp: true)
      end
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

  describe '#approve_agent' do
    let(:approve_response) { { 'status' => 'ok', 'response' => { 'type' => 'approveAgent' } } }
    let(:agent_address) { '0x1234567890123456789012345678901234567890' }

    it 'approves agent with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'approveAgent' &&
            action['agentAddress'] == agent_address &&
            action['nonce'].is_a?(Integer) &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet' &&
            !action.key?('agentName')
        end
        .to_return(status: 200, body: approve_response.to_json)

      result = exchange.approve_agent(agent_address: agent_address)
      expect(result['status']).to eq('ok')
    end

    it 'includes agentName when provided' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'approveAgent' &&
            action['agentName'] == 'my-bot'
        end
        .to_return(status: 200, body: approve_response.to_json)

      result = exchange.approve_agent(agent_address: agent_address, agent_name: 'my-bot')
      expect(result['status']).to eq('ok')
    end

    it 'includes signature in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['signature'].is_a?(Hash) &&
            body['signature']['r']&.start_with?('0x')
        end
        .to_return(status: 200, body: approve_response.to_json)

      result = exchange.approve_agent(agent_address: agent_address)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#approve_builder_fee' do
    let(:approve_response) { { 'status' => 'ok', 'response' => { 'type' => 'approveBuilderFee' } } }
    let(:builder_address) { '0x250F311Ae04D3CEA03443C76340069eD26C47D7D' }

    it 'approves builder fee with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'approveBuilderFee' &&
            action['builder'] == builder_address &&
            action['maxFeeRate'] == '0.01%' &&
            action['nonce'].is_a?(Integer) &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet'
        end
        .to_return(status: 200, body: approve_response.to_json)

      result = exchange.approve_builder_fee(builder: builder_address, max_fee_rate: '0.01%')
      expect(result['status']).to eq('ok')
    end

    it 'includes signature in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['signature'].is_a?(Hash) &&
            body['signature']['r']&.start_with?('0x')
        end
        .to_return(status: 200, body: approve_response.to_json)

      result = exchange.approve_builder_fee(builder: builder_address, max_fee_rate: '0.01%')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#token_delegate' do
    let(:delegate_response) { { 'status' => 'ok', 'response' => { 'type' => 'tokenDelegate' } } }
    let(:validator_address) { '0x1234567890123456789012345678901234567890' }

    it 'delegates tokens with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'tokenDelegate' &&
            action['validator'] == validator_address &&
            action['wei'] == 1_000_000_000_000_000_000 &&
            action['isUndelegate'] == false &&
            action['nonce'].is_a?(Integer) &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet'
        end
        .to_return(status: 200, body: delegate_response.to_json)

      result = exchange.token_delegate(
        validator: validator_address,
        wei: 1_000_000_000_000_000_000,
        is_undelegate: false
      )
      expect(result['status']).to eq('ok')
    end

    it 'undelegates tokens' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['isUndelegate'] == true
        end
        .to_return(status: 200, body: delegate_response.to_json)

      result = exchange.token_delegate(
        validator: validator_address,
        wei: 500_000_000_000_000_000,
        is_undelegate: true
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
        .to_return(status: 200, body: delegate_response.to_json)

      result = exchange.token_delegate(
        validator: validator_address,
        wei: 1_000_000_000_000_000_000,
        is_undelegate: false
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#user_dex_abstraction' do
    let(:dex_response) { { 'status' => 'ok', 'response' => { 'type' => 'userDexAbstraction' } } }

    it 'enables DEX abstraction with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'userDexAbstraction' &&
            action['user'] == exchange.address &&
            action['enabled'] == true &&
            action['nonce'].is_a?(Integer) &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet'
        end
        .to_return(status: 200, body: dex_response.to_json)

      result = exchange.user_dex_abstraction(enabled: true)
      expect(result['status']).to eq('ok')
    end

    it 'disables DEX abstraction' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['enabled'] == false
        end
        .to_return(status: 200, body: dex_response.to_json)

      result = exchange.user_dex_abstraction(enabled: false)
      expect(result['status']).to eq('ok')
    end

    it 'uses custom user address when provided' do
      custom_user = '0x1234567890123456789012345678901234567890'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['user'] == custom_user
        end
        .to_return(status: 200, body: dex_response.to_json)

      result = exchange.user_dex_abstraction(enabled: true, user: custom_user)
      expect(result['status']).to eq('ok')
    end

    it 'includes signature in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['signature'].is_a?(Hash) &&
            body['signature']['r']&.start_with?('0x')
        end
        .to_return(status: 200, body: dex_response.to_json)

      result = exchange.user_dex_abstraction(enabled: true)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#agent_enable_dex_abstraction' do
    let(:dex_response) { { 'status' => 'ok', 'response' => { 'type' => 'agentEnableDexAbstraction' } } }

    it 'enables DEX abstraction via agent with correct action structure' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'agentEnableDexAbstraction' &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: dex_response.to_json)

      result = exchange.agent_enable_dex_abstraction
      expect(result['status']).to eq('ok')
    end

    it 'includes vault address when provided' do
      vault_addr = '0x1234567890123456789012345678901234567890'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault_addr
        end
        .to_return(status: 200, body: dex_response.to_json)

      result = exchange.agent_enable_dex_abstraction(vault_address: vault_addr)
      expect(result['status']).to eq('ok')
    end

    it 'includes signature in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['signature'].is_a?(Hash) &&
            body['signature']['r']&.start_with?('0x')
        end
        .to_return(status: 200, body: dex_response.to_json)

      result = exchange.agent_enable_dex_abstraction
      expect(result['status']).to eq('ok')
    end
  end

  describe '#expires_after=' do
    it 'updates @expires_after for subsequent L1 actions' do
      exchange.expires_after = 9_999_999_999_999

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['expiresAfter'] == 9_999_999_999_999
        end
        .to_return(status: 200, body: { 'status' => 'ok', 'response' => { 'type' => 'default' } }.to_json)

      result = exchange.agent_enable_dex_abstraction
      expect(result['status']).to eq('ok')
    end

    it 'clears @expires_after when nil is passed' do
      exchange.expires_after = 123_456_789
      exchange.expires_after = nil

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          !body.key?('expiresAfter')
        end
        .to_return(status: 200, body: { 'status' => 'ok', 'response' => { 'type' => 'default' } }.to_json)

      result = exchange.agent_enable_dex_abstraction
      expect(result['status']).to eq('ok')
    end

    it 'returns the assigned value' do
      expect(exchange.expires_after = 42).to eq(42)
      expect(exchange.expires_after = nil).to be_nil
    end
  end

  describe '#use_big_blocks' do
    let(:big_blocks_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends evmUserModify with usingBigBlocks: true' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'evmUserModify' &&
            action['usingBigBlocks'] == true &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: big_blocks_response.to_json)

      result = exchange.use_big_blocks(enable: true)
      expect(result['status']).to eq('ok')
    end

    it 'sends evmUserModify with usingBigBlocks: false' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['usingBigBlocks'] == false
        end
        .to_return(status: 200, body: big_blocks_response.to_json)

      result = exchange.use_big_blocks(enable: false)
      expect(result['status']).to eq('ok')
    end

    it 'does not include vaultAddress in the payload' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          !body.key?('vaultAddress')
        end
        .to_return(status: 200, body: big_blocks_response.to_json)

      result = exchange.use_big_blocks(enable: true)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#noop' do
    let(:noop_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends a noop L1 action with a generated nonce' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action == { 'type' => 'noop' } &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: noop_response.to_json)

      result = exchange.noop
      expect(result['status']).to eq('ok')
    end

    it 'uses the caller-provided nonce when given' do
      explicit_nonce = 1_700_000_000_000

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['nonce'] == explicit_nonce
        end
        .to_return(status: 200, body: noop_response.to_json)

      result = exchange.noop(nonce: explicit_nonce)
      expect(result['status']).to eq('ok')
    end

    it 'includes vaultAddress when provided' do
      vault_addr = '0x1234567890123456789012345678901234567890'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault_addr
        end
        .to_return(status: 200, body: noop_response.to_json)

      result = exchange.noop(vault_address: vault_addr)
      expect(result['status']).to eq('ok')
    end
  end

  describe 'builder parameter' do
    let(:order_response) do
      {
        'status' => 'ok',
        'response' => {
          'type' => 'order',
          'data' => { 'statuses' => [{ 'resting' => { 'oid' => 12_345 } }] }
        }
      }
    end

    let(:builder) { { b: '0x250F311Ae04D3CEA03443C76340069eD26C47D7D', f: 10 } }

    describe '#order with builder' do
      it 'includes builder in action' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            action = body['action']
            action['builder']['b'] == '0x250f311ae04d3cea03443c76340069ed26c47d7d' &&
              action['builder']['f'] == 10
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.order(
          coin: 'BTC',
          is_buy: true,
          size: '0.01',
          limit_px: '95000',
          builder: builder
        )
        expect(result['status']).to eq('ok')
      end

      it 'lowercases builder address' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['action']['builder']['b'] == '0x250f311ae04d3cea03443c76340069ed26c47d7d'
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.order(
          coin: 'BTC',
          is_buy: true,
          size: '0.01',
          limit_px: '95000',
          builder: builder
        )
        expect(result['status']).to eq('ok')
      end

      it 'does not include builder when nil' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            !body['action'].key?('builder')
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.order(
          coin: 'BTC',
          is_buy: true,
          size: '0.01',
          limit_px: '95000'
        )
        expect(result['status']).to eq('ok')
      end
    end

    describe '#bulk_orders with builder' do
      it 'includes builder in action' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            action = body['action']
            action['builder']['b'] == '0x250f311ae04d3cea03443c76340069ed26c47d7d' &&
              action['builder']['f'] == 10 &&
              action['orders'].length == 2
          end
          .to_return(status: 200, body: order_response.to_json)

        orders = [
          { coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000' },
          { coin: 'ETH', is_buy: false, size: '0.5', limit_px: '3200' }
        ]
        result = exchange.bulk_orders(orders: orders, builder: builder)
        expect(result['status']).to eq('ok')
      end
    end

    describe '#market_order with builder' do
      let(:mids_response) { { 'BTC' => '96000' } }

      before do
        stub_request(:post, info_endpoint)
          .with(body: { type: 'allMids' }.to_json)
          .to_return(status: 200, body: mids_response.to_json)
      end

      it 'passes builder through to order' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['action']['builder']['b'] == '0x250f311ae04d3cea03443c76340069ed26c47d7d'
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.market_order(
          coin: 'BTC',
          is_buy: true,
          size: '0.01',
          builder: builder
        )
        expect(result['status']).to eq('ok')
      end
    end

    describe '#market_close with builder' do
      let(:user_state_response) do
        {
          'assetPositions' => [
            { 'position' => { 'coin' => 'BTC', 'szi' => '0.05' } }
          ],
          'marginSummary' => {}
        }
      end

      let(:mids_response) { { 'BTC' => '96000' } }

      before do
        stub_request(:post, info_endpoint)
          .with(body: hash_including('type' => 'clearinghouseState'))
          .to_return(status: 200, body: user_state_response.to_json)

        stub_request(:post, info_endpoint)
          .with(body: { type: 'allMids' }.to_json)
          .to_return(status: 200, body: mids_response.to_json)
      end

      it 'passes builder through to order' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['action']['builder']['b'] == '0x250f311ae04d3cea03443c76340069ed26c47d7d'
          end
          .to_return(status: 200, body: order_response.to_json)

        result = exchange.market_close(coin: 'BTC', builder: builder)
        expect(result['status']).to eq('ok')
      end
    end
  end

  describe 'HIP-3 dex support' do
    let(:hip3_meta_response) do
      {
        'universe' => [
          { 'name' => 'xyz:GOLD', 'szDecimals' => 4 },
          { 'name' => 'xyz:SILVER', 'szDecimals' => 2 }
        ]
      }
    end

    let(:order_response) do
      {
        'status' => 'ok',
        'response' => {
          'type' => 'order',
          'data' => { 'statuses' => [{ 'resting' => { 'oid' => 12_345 } }] }
        }
      }
    end

    it 'lazily loads HIP-3 dex metadata when ordering a prefixed asset' do
      # Stub perpDexs to return xyz at index 2 (perp_dex_index = 2)
      perp_dexs_response = [nil, nil, { 'name' => 'xyz', 'deployer' => '0x123' }]
      stub_request(:post, info_endpoint)
        .with(body: { type: 'perpDexs' }.to_json)
        .to_return(status: 200, body: perp_dexs_response.to_json)

      stub_request(:post, info_endpoint)
        .with(body: { type: 'meta', dex: 'xyz' }.to_json)
        .to_return(status: 200, body: hip3_meta_response.to_json)

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          # HIP-3 asset ID: 100000 + 2*10000 + 0 = 120000
          action['type'] == 'order' && action['orders'][0]['a'] == 120_000
        end
        .to_return(status: 200, body: order_response.to_json)

      result = exchange.order(
        coin: 'xyz:GOLD',
        is_buy: true,
        size: '1.0',
        limit_px: '2500'
      )

      expect(result['status']).to eq('ok')
    end

    it 'extracts dex prefix correctly' do
      expect(exchange.send(:extract_dex_prefix, 'xyz:GOLD')).to eq('xyz')
      expect(exchange.send(:extract_dex_prefix, 'BTC')).to be_nil
      expect(exchange.send(:extract_dex_prefix, 'PURR/USDC')).to be_nil
    end
  end

  describe '#agent_set_abstraction' do
    let(:abstraction_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends agentSetAbstraction with the given mode' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'agentSetAbstraction' &&
            action['abstraction'] == 'u' &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: abstraction_response.to_json)

      result = exchange.agent_set_abstraction(abstraction: 'u')
      expect(result['status']).to eq('ok')
    end

    it 'forwards different abstraction modes verbatim' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['abstraction'] == 'p'
        end
        .to_return(status: 200, body: abstraction_response.to_json)

      result = exchange.agent_set_abstraction(abstraction: 'p')
      expect(result['status']).to eq('ok')
    end

    it 'includes vaultAddress when provided' do
      vault_addr = '0x1234567890123456789012345678901234567890'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault_addr
        end
        .to_return(status: 200, body: abstraction_response.to_json)

      result = exchange.agent_set_abstraction(abstraction: 'i', vault_address: vault_addr)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#gossip_priority_bid' do
    let(:bid_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends gossipPriorityBid with the given fields' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'gossipPriorityBid' &&
            action['slotId'] == 42 &&
            action['ip'] == '198.51.100.7' &&
            action['maxGas'] == 1_000 &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: bid_response.to_json)

      result = exchange.gossip_priority_bid(slot_id: 42, ip: '198.51.100.7', max_gas: 1_000)
      expect(result['status']).to eq('ok')
    end

    it 'includes vaultAddress when provided' do
      vault_addr = '0x1234567890123456789012345678901234567890'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault_addr
        end
        .to_return(status: 200, body: bid_response.to_json)

      result = exchange.gossip_priority_bid(
        slot_id: 1, ip: '203.0.113.1', max_gas: 500, vault_address: vault_addr
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#convert_to_multi_sig_user' do
    let(:convert_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sorts authorized_users and JSON-encodes signers with threshold' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          signers = JSON.parse(action['signers'])
          action['type'] == 'convertToMultiSigUser' &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet' &&
            action['nonce'].is_a?(Integer) &&
            signers['authorizedUsers'] == %w[
              0x1111111111111111111111111111111111111111
              0x2222222222222222222222222222222222222222
              0x3333333333333333333333333333333333333333
            ] &&
            signers['threshold'] == 2 &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: convert_response.to_json)

      result = exchange.convert_to_multi_sig_user(
        authorized_users: %w[
          0x3333333333333333333333333333333333333333
          0x1111111111111111111111111111111111111111
          0x2222222222222222222222222222222222222222
        ],
        threshold: 2
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
        .to_return(status: 200, body: convert_response.to_json)

      result = exchange.convert_to_multi_sig_user(
        authorized_users: ['0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
        threshold: 1
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#user_set_abstraction' do
    let(:abstraction_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends userSetAbstraction with lowercased user and correct envelope' do
      mixed_case_user = '0xABCDEF1234567890ABCDEF1234567890ABCDEF12'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'userSetAbstraction' &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet' &&
            action['user'] == mixed_case_user.downcase &&
            action['abstraction'] == 'unifiedAccount' &&
            action['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: abstraction_response.to_json)

      result = exchange.user_set_abstraction(user: mixed_case_user, abstraction: 'unifiedAccount')
      expect(result['status']).to eq('ok')
    end

    it 'forwards the abstraction value verbatim' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['abstraction'] == 'portfolioMargin'
        end
        .to_return(status: 200, body: abstraction_response.to_json)

      result = exchange.user_set_abstraction(
        user: '0x1111111111111111111111111111111111111111',
        abstraction: 'portfolioMargin'
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
        .to_return(status: 200, body: abstraction_response.to_json)

      result = exchange.user_set_abstraction(
        user: '0x1111111111111111111111111111111111111111',
        abstraction: 'disabled'
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#multi_sig' do
    let(:multi_sig_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:multi_sig_user) { '0x0000000000000000000000000000000000000005' }
    let(:inner_action) { { type: 'noop' } }

    it 'posts a multiSig envelope with lowercased addresses and the outer user signature' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'multiSig' &&
            action['signatureChainId'] == '0x66eee' &&
            action['signatures'] == [] &&
            action['payload']['multiSigUser'] == multi_sig_user.downcase &&
            action['payload']['outerSigner'] == signer.address.downcase &&
            action['payload']['action'] == { 'type' => 'noop' } &&
            body['signature'].is_a?(Hash) &&
            body['nonce'].is_a?(Integer)
        end
        .to_return(status: 200, body: multi_sig_response.to_json)

      result = exchange.multi_sig(
        multi_sig_user: multi_sig_user,
        inner_action: inner_action,
        signatures: []
      )
      expect(result['status']).to eq('ok')
    end

    it 'forwards a caller-provided nonce verbatim and includes pre-collected signatures' do
      pre_sigs = [{ r: '0x1', s: '0x2', v: 27 }]
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          body['nonce'] == 1_700_000_000_000 &&
            action['signatures'] == [{ 'r' => '0x1', 's' => '0x2', 'v' => 27 }]
        end
        .to_return(status: 200, body: multi_sig_response.to_json)

      result = exchange.multi_sig(
        multi_sig_user: multi_sig_user,
        inner_action: inner_action,
        signatures: pre_sigs,
        nonce: 1_700_000_000_000
      )
      expect(result['status']).to eq('ok')
    end

    it 'invokes sign_user_signed_action with SendMultiSig primary type and MULTI_SIG_TYPES' do
      stub_request(:post, exchange_endpoint).to_return(status: 200, body: multi_sig_response.to_json)

      expect(signer).to receive(:sign_user_signed_action).with(
        hash_including(:multiSigActionHash, :nonce),
        'HyperliquidTransaction:SendMultiSig',
        Hyperliquid::Signing::EIP712::MULTI_SIG_TYPES
      ).and_call_original

      exchange.multi_sig(
        multi_sig_user: multi_sig_user,
        inner_action: inner_action,
        signatures: []
      )
    end

    it 'normalizes userSetAbstraction long-form abstraction values to wire enum in the L1 payload' do
      # Python SDK 0.24.0 parity: when wrapping userSetAbstraction in multi_sig, the
      # human-readable abstraction string ("disabled"/"unifiedAccount"/"portfolioMargin")
      # must be translated to the wire enum ("i"/"u"/"p") in the payload sent to /exchange.
      # Co-signers separately sign the long-form action — that part is unaffected.
      inner = {
        type: 'userSetAbstraction',
        signatureChainId: '0x66eee',
        hyperliquidChain: 'Testnet',
        user: '0x3b4d2cc2e144a0044002506c8b44508e9ace82e9',
        abstraction: 'disabled',
        nonce: 1_780_130_409_592
      }
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          payload_action = body['action']['payload']['action']
          payload_action['type'] == 'userSetAbstraction' &&
            payload_action['abstraction'] == 'i'
        end
        .to_return(status: 200, body: multi_sig_response.to_json)

      result = exchange.multi_sig(
        multi_sig_user: multi_sig_user,
        inner_action: inner,
        signatures: []
      )
      expect(result['status']).to eq('ok')
    end

    it 'propagates vault_address into the wire payload' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == '0xabcdef1234567890abcdef1234567890abcdef12'
        end
        .to_return(status: 200, body: multi_sig_response.to_json)

      result = exchange.multi_sig(
        multi_sig_user: multi_sig_user,
        inner_action: inner_action,
        signatures: [],
        vault_address: '0xabcdef1234567890abcdef1234567890abcdef12'
      )
      expect(result['status']).to eq('ok')
    end

    # Signature parity regression: catches future eth gem regressions on `bytes32` handling
    # in the outer envelope. Fixtures captured 2026-05-07 against Python's eth_account 0.13.7.
    # See: ~/agent-state/hyperliquid-sdk-fixtures/capture_multi_sig_signatures.py
    describe 'EIP-712 outer-signature parity (regression guard for bytes32 type)' do
      let(:fixture_private_key) { '0x1111111111111111111111111111111111111111111111111111111111111111' }
      let(:fixture_signer) { Hyperliquid::Signing::Signer.new(private_key: fixture_private_key, testnet: false) }
      let(:fixture_nonce) { 1_700_000_000_000 }

      it 'Fixture A: signs envelope (noop inner action, no co-signers) matching reference output' do
        envelope = Hyperliquid::Signing::MultiSig.build_envelope(
          inner_action: { type: 'noop' },
          multi_sig_user: '0x0000000000000000000000000000000000000005',
          outer_signer: fixture_signer.address,
          signatures: []
        )
        hash = Hyperliquid::Signing::MultiSig.envelope_action_hash(envelope: envelope, nonce: fixture_nonce)
        expect(hash).to eq('0x897feed4f5053a54739850d8af2354f592b667b27cab36a917afe8333fec2156')

        sig = fixture_signer.sign_user_signed_action(
          { multiSigActionHash: hash, nonce: fixture_nonce },
          'HyperliquidTransaction:SendMultiSig',
          Hyperliquid::Signing::EIP712::MULTI_SIG_TYPES
        )
        expect(sig[:r]).to eq('0x673bd8bb32fd0d3faa1fc7282ad6af724ddd069b3a36441d879fa0a2a40abc31')
        expect(sig[:s]).to eq('0x303b2f9c475130962e6b34f82eac3a91c52a2c860f57eabd1d7c99fffb10f0eb')
        expect(sig[:v]).to eq(27)
      end

      it 'Fixture B: signs envelope (order inner action + populated co-signer sig) matching reference output' do
        co_signer_sig = {
          r: '0x9635450d1274007c5b83f819654b4994af3e76d732f99c677ed82058eae640d4',
          s: '0x7b8beeb8dc6e70adde2df6defe73fea946d061ae1255482c1e2d0a54e6c9f3ec',
          v: 27
        }
        envelope = Hyperliquid::Signing::MultiSig.build_envelope(
          inner_action: {
            type: 'order',
            orders: [{ a: 4, b: true, p: '1100', s: '0.2', r: false, t: { limit: { tif: 'Gtc' } } }],
            grouping: 'na'
          },
          multi_sig_user: '0x0000000000000000000000000000000000000005',
          outer_signer: fixture_signer.address,
          signatures: [co_signer_sig]
        )
        hash = Hyperliquid::Signing::MultiSig.envelope_action_hash(envelope: envelope, nonce: fixture_nonce)
        expect(hash).to eq('0x7bc3a36d385f1decbe4983d98deb4c272e83ed1bb9d7d9736b225960cf5c32c5')

        sig = fixture_signer.sign_user_signed_action(
          { multiSigActionHash: hash, nonce: fixture_nonce },
          'HyperliquidTransaction:SendMultiSig',
          Hyperliquid::Signing::EIP712::MULTI_SIG_TYPES
        )
        expect(sig[:r]).to eq('0xe8c710d9ff10597a6960f5a69f02f63351845e7cd31733eb03e6799f085ca60a')
        expect(sig[:s]).to eq('0x5895b4b2fb542667d858e8de39e2adf948916182a52e44cf6dfaa44528beeded')
        expect(sig[:v]).to eq(28)
      end
    end
  end

  describe '#claim_rewards' do
    let(:claim_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends claimRewards with no extra fields' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action == { 'type' => 'claimRewards' } &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: claim_response.to_json)

      result = exchange.claim_rewards
      expect(result['status']).to eq('ok')
    end
  end

  describe '#set_display_name' do
    let(:display_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends setDisplayName with the provided display name' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'setDisplayName' &&
            action['displayName'] == 'Carter' &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: display_response.to_json)

      result = exchange.set_display_name(display_name: 'Carter')
      expect(result['status']).to eq('ok')
    end

    it 'allows clearing the display name with an empty string' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['displayName'] == ''
        end
        .to_return(status: 200, body: display_response.to_json)

      result = exchange.set_display_name(display_name: '')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#register_referrer' do
    let(:register_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends registerReferrer with the provided code' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'registerReferrer' &&
            action['code'] == 'CARTER2099' &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: register_response.to_json)

      result = exchange.register_referrer(code: 'CARTER2099')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#top_up_isolated_only_margin' do
    let(:top_up_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends topUpIsolatedOnlyMargin with asset index and leverage as a string' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'topUpIsolatedOnlyMargin' &&
            action['asset'] == 0 &&
            action['leverage'] == '5' &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: top_up_response.to_json)

      result = exchange.top_up_isolated_only_margin(coin: 'BTC', leverage: 5)
      expect(result['status']).to eq('ok')
    end

    it 'preserves fractional leverage when passed as a string' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['leverage'] == '0.5'
        end
        .to_return(status: 200, body: top_up_response.to_json)

      result = exchange.top_up_isolated_only_margin(coin: 'BTC', leverage: '0.5')
      expect(result['status']).to eq('ok')
    end

    it 'includes vaultAddress at payload level when provided' do
      vault = '0x1111111111111111111111111111111111111111'
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault
        end
        .to_return(status: 200, body: top_up_response.to_json)

      result = exchange.top_up_isolated_only_margin(coin: 'BTC', leverage: 3, vault_address: vault)
      expect(result['status']).to eq('ok')
    end

    it 'raises ArgumentError for unknown asset' do
      expect do
        exchange.top_up_isolated_only_margin(coin: 'UNKNOWN', leverage: 5)
      end.to raise_error(ArgumentError, /Unknown asset/)
    end
  end

  describe '#vault_modify' do
    let(:vault_modify_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:vault) { '0x2222222222222222222222222222222222222222' }

    it 'sends vaultModify with both flags set' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'vaultModify' &&
            action['vaultAddress'] == vault &&
            action['allowDeposits'] == true &&
            action['alwaysCloseOnWithdraw'] == false &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: vault_modify_response.to_json)

      result = exchange.vault_modify(
        vault_address: vault,
        allow_deposits: true,
        always_close_on_withdraw: false
      )
      expect(result['status']).to eq('ok')
    end

    it 'sends null for unspecified flags' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action.key?('allowDeposits') &&
            action['allowDeposits'].nil? &&
            action.key?('alwaysCloseOnWithdraw') &&
            action['alwaysCloseOnWithdraw'].nil?
        end
        .to_return(status: 200, body: vault_modify_response.to_json)

      result = exchange.vault_modify(vault_address: vault)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#vault_distribute' do
    let(:vault_distribute_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:vault) { '0x3333333333333333333333333333333333333333' }

    it 'sends vaultDistribute with usd scaled to 1e6 integer' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'vaultDistribute' &&
            action['vaultAddress'] == vault &&
            action['usd'] == 10_000_000 &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: vault_distribute_response.to_json)

      result = exchange.vault_distribute(vault_address: vault, usd: 10)
      expect(result['status']).to eq('ok')
    end

    it 'allows usd: 0 (close vault)' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['usd'] == 0
        end
        .to_return(status: 200, body: vault_distribute_response.to_json)

      result = exchange.vault_distribute(vault_address: vault, usd: 0)
      expect(result['status']).to eq('ok')
    end

    it 'raises ArgumentError for usd that causes rounding' do
      expect do
        exchange.vault_distribute(vault_address: vault, usd: 100.0000019)
      end.to raise_error(ArgumentError, /float_to_usd_int causes rounding/)
    end
  end

  describe '#create_vault' do
    let(:create_vault_response) do
      { 'status' => 'ok',
        'response' => { 'type' => 'createVault',
                        'data' => '0x4444444444444444444444444444444444444444' } }
    end

    it 'sends createVault with name, description, initialUsd scaled to 1e6, and inner nonce matching outer nonce' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'createVault' &&
            action['name'] == 'TestVault' &&
            action['description'] == 'Test description' &&
            action['initialUsd'] == 100_000_000 &&
            action['nonce'] == body['nonce'] &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: create_vault_response.to_json)

      result = exchange.create_vault(
        name: 'TestVault',
        description: 'Test description',
        initial_usd: 100
      )
      expect(result['status']).to eq('ok')
      expect(result.dig('response', 'data')).to eq('0x4444444444444444444444444444444444444444')
    end

    it 'scales fractional usd values via float_to_usd_int (100.5 -> 100_500_000)' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          JSON.parse(req.body).dig('action', 'initialUsd') == 100_500_000
        end
        .to_return(status: 200, body: create_vault_response.to_json)

      result = exchange.create_vault(name: 'V', description: 'd' * 10, initial_usd: 100.5)
      expect(result['status']).to eq('ok')
    end

    it 'raises ArgumentError for initial_usd that causes rounding' do
      expect do
        exchange.create_vault(name: 'V', description: 'd' * 10, initial_usd: 100.0000019)
      end.to raise_error(ArgumentError, /float_to_usd_int causes rounding/)
    end

    it 'propagates expires_after when set on the exchange' do
      exchange.expires_after = 9_999_999_999_999
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['expiresAfter'] == 9_999_999_999_999 &&
            body.dig('action', 'type') == 'createVault'
        end
        .to_return(status: 200, body: create_vault_response.to_json)

      result = exchange.create_vault(name: 'V', description: 'd' * 10, initial_usd: 100)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#borrow_lend' do
    let(:borrow_lend_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends borrowLend with operation, token, and amount as a string' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'borrowLend' &&
            action['operation'] == 'supply' &&
            action['token'] == 0 &&
            action['amount'] == '20' &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: borrow_lend_response.to_json)

      result = exchange.borrow_lend(operation: 'supply', token: 0, amount: 20)
      expect(result['status']).to eq('ok')
    end

    it 'sends amount: null when amount is nil (full position)' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action.key?('amount') && action['amount'].nil? &&
            action['operation'] == 'withdraw'
        end
        .to_return(status: 200, body: borrow_lend_response.to_json)

      result = exchange.borrow_lend(operation: 'withdraw', token: 0)
      expect(result['status']).to eq('ok')
    end

    it 'includes vaultAddress at payload level when provided' do
      vault = '0x4444444444444444444444444444444444444444'
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault
        end
        .to_return(status: 200, body: borrow_lend_response.to_json)

      result = exchange.borrow_lend(
        operation: 'borrow', token: 0, amount: '5', vault_address: vault
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#sub_account_modify' do
    let(:sub_modify_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:sub_user) { '0x5555555555555555555555555555555555555555' }

    it 'sends subAccountModify with subAccountUser and name' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'subAccountModify' &&
            action['subAccountUser'] == sub_user &&
            action['name'] == 'trading-bot' &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: sub_modify_response.to_json)

      result = exchange.sub_account_modify(sub_account_user: sub_user, name: 'trading-bot')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#link_staking_user' do
    let(:link_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:counterpart) { '0x6666666666666666666666666666666666666666' }

    it 'sends linkStakingUser with user-signed envelope when initiating' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'linkStakingUser' &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet' &&
            action['user'] == counterpart &&
            action['isFinalize'] == false &&
            action['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: link_response.to_json)

      result = exchange.link_staking_user(user: counterpart, is_finalize: false)
      expect(result['status']).to eq('ok')
    end

    it 'forwards isFinalize: true when staking user finalizes' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['isFinalize'] == true
        end
        .to_return(status: 200, body: link_response.to_json)

      result = exchange.link_staking_user(user: counterpart, is_finalize: true)
      expect(result['status']).to eq('ok')
    end

    it 'includes signature in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['signature'].is_a?(Hash) &&
            body['signature']['r']&.start_with?('0x')
        end
        .to_return(status: 200, body: link_response.to_json)

      result = exchange.link_staking_user(user: counterpart, is_finalize: false)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#agent_send_asset' do
    let(:agent_send_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:principal) { '0x1111111111111111111111111111111111111111' }

    it 'sends agentSendAsset as an L1 action with inner nonce matching outer nonce' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'agentSendAsset' &&
            action['destination'] == principal &&
            action['sourceDex'] == '' &&
            action['destinationDex'] == 'xyz' &&
            action['token'] == 'USDC:0x6d1e7cde53ba9467b783cb7c530ce054' &&
            action['amount'] == '0.01' &&
            action['fromSubAccount'] == '' &&
            action['nonce'].is_a?(Integer) &&
            action['nonce'] == body['nonce'] &&
            !action.keys.intersect?(%w[signatureChainId hyperliquidChain]) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: agent_send_response.to_json)

      result = exchange.agent_send_asset(
        destination: principal,
        source_dex: '',
        destination_dex: 'xyz',
        token: 'USDC:0x6d1e7cde53ba9467b783cb7c530ce054',
        amount: 0.01
      )
      expect(result['status']).to eq('ok')
    end

    it 'forwards a non-empty fromSubAccount when provided' do
      sub = '0x9999999999999999999999999999999999999999'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['fromSubAccount'] == sub
        end
        .to_return(status: 200, body: agent_send_response.to_json)

      result = exchange.agent_send_asset(
        destination: principal,
        source_dex: 'spot',
        destination_dex: '',
        token: 'USDC:0xabc',
        amount: '5',
        from_sub_account: sub
      )
      expect(result['status']).to eq('ok')
    end

    it 'coerces numeric amount to string' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['amount'] == '1.5'
        end
        .to_return(status: 200, body: agent_send_response.to_json)

      result = exchange.agent_send_asset(
        destination: principal,
        source_dex: '',
        destination_dex: 'xyz',
        token: 'USDC:0xabc',
        amount: 1.5
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#hip3_liquidator_transfer' do
    let(:liq_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends hip3LiquidatorTransfer with the given fields' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'hip3LiquidatorTransfer' &&
            action['dex'] == 'xyz' &&
            action['ntl'] == 1_000_000_000 &&
            action['isDeposit'] == true &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: liq_response.to_json)

      result = exchange.hip3_liquidator_transfer(dex: 'xyz', ntl: 1_000_000_000, is_deposit: true)
      expect(result['status']).to eq('ok')
    end

    it 'forwards isDeposit: false for withdrawals' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['isDeposit'] == false
        end
        .to_return(status: 200, body: liq_response.to_json)

      result = exchange.hip3_liquidator_transfer(dex: 'xyz', ntl: 2_000_000_000, is_deposit: false)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#send_to_evm_with_data' do
    let(:send_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:default_args) do
      {
        token: 'USDC',
        amount: '1',
        source_dex: 'spot',
        destination_recipient: '0xABCDEF1234567890ABCDEF1234567890ABCDEF12',
        address_encoding: 'hex',
        destination_chain_id: 998,
        gas_limit: 200_000
      }
    end

    it 'sends sendToEvmWithData with full user-signed envelope and default empty data' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'sendToEvmWithData' &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet' &&
            action['token'] == 'USDC' &&
            action['amount'] == '1' &&
            action['sourceDex'] == 'spot' &&
            action['destinationRecipient'] == default_args[:destination_recipient] &&
            action['addressEncoding'] == 'hex' &&
            action['destinationChainId'] == 998 &&
            action['gasLimit'] == 200_000 &&
            action['data'] == '0x' &&
            action['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: send_response.to_json)

      result = exchange.send_to_evm_with_data(**default_args)
      expect(result['status']).to eq('ok')
    end

    it 'forwards a non-empty data payload verbatim' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['data'] == '0xdeadbeef'
        end
        .to_return(status: 200, body: send_response.to_json)

      result = exchange.send_to_evm_with_data(**default_args, data: '0xdeadbeef')
      expect(result['status']).to eq('ok')
    end

    it 'does NOT lowercase destinationRecipient (base58 safety)' do
      mixed_recipient = '5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty' # base58 example
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['destinationRecipient'] == mixed_recipient &&
            body['action']['addressEncoding'] == 'base58'
        end
        .to_return(status: 200, body: send_response.to_json)

      result = exchange.send_to_evm_with_data(
        **default_args, destination_recipient: mixed_recipient, address_encoding: 'base58'
      )
      expect(result['status']).to eq('ok')
    end

    it 'coerces numeric amount to string' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['amount'] == '1.5'
        end
        .to_return(status: 200, body: send_response.to_json)

      result = exchange.send_to_evm_with_data(**default_args, amount: 1.5)
      expect(result['status']).to eq('ok')
    end

    it 'coerces destination_chain_id and gas_limit to Integer' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['destinationChainId'] == 998 && action['destinationChainId'].is_a?(Integer) &&
            action['gasLimit'] == 200_000 && action['gasLimit'].is_a?(Integer)
        end
        .to_return(status: 200, body: send_response.to_json)

      # Pass floats — defensively coerced to int by the SDK
      result = exchange.send_to_evm_with_data(
        **default_args, destination_chain_id: 998.0, gas_limit: 200_000.0
      )
      expect(result['status']).to eq('ok')
    end

    it 'invokes sign_user_signed_action with the new primary type and constant' do
      stub_request(:post, exchange_endpoint)
        .to_return(status: 200, body: send_response.to_json)

      expect(signer).to receive(:sign_user_signed_action).with(
        hash_including(
          token: 'USDC', amount: '1', sourceDex: 'spot',
          destinationRecipient: default_args[:destination_recipient],
          addressEncoding: 'hex', destinationChainId: 998, gasLimit: 200_000,
          data: '0x'
        ),
        'HyperliquidTransaction:SendToEvmWithData',
        Hyperliquid::Signing::EIP712::SEND_TO_EVM_WITH_DATA_TYPES
      ).and_call_original

      exchange.send_to_evm_with_data(**default_args)
    end

    # Signature parity regression: catches future eth gem regressions on `bytes` handling.
    # Fixtures captured 2026-05-04 against Python's eth_account 0.13.7. Do not modify
    # without re-capturing via ~/agent-state/hyperliquid-sdk-fixtures/capture_send_to_evm_with_data_signatures.py
    describe 'EIP-712 signature parity (regression guard for bytes type)' do
      let(:fixture_private_key) { '0x1111111111111111111111111111111111111111111111111111111111111111' }
      let(:fixture_signer) { Hyperliquid::Signing::Signer.new(private_key: fixture_private_key, testnet: false) }
      let(:fixture_nonce) { 1_700_000_000_000 }
      let(:base_message) do
        {
          token: 'USDC',
          amount: '1',
          sourceDex: 'spot',
          destinationRecipient: '0x0000000000000000000000000000000000000001',
          addressEncoding: 'hex',
          destinationChainId: 998,
          gasLimit: 200_000,
          nonce: fixture_nonce
        }
      end

      it 'fixture signer address sanity check' do
        expect(fixture_signer.address).to eq('0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A')
      end

      it 'Fixture A: signs empty data (data: "0x") matching reference eth_account output' do
        sig = fixture_signer.sign_user_signed_action(
          base_message.merge(data: '0x'),
          'HyperliquidTransaction:SendToEvmWithData',
          Hyperliquid::Signing::EIP712::SEND_TO_EVM_WITH_DATA_TYPES
        )
        expect(sig[:r]).to eq('0x74d708bb7b212d2449c5dc82aff2565d9813a2e1d47ad486c8bde843618d1fdb')
        expect(sig[:s]).to eq('0x30f760fccdaacd3bfa1cb877fdbeb25468c9576128f0b38cfbc6059f05d3a179')
        expect(sig[:v]).to eq(28)
      end

      it 'Fixture B: signs non-empty data ("0xdeadbeef") matching reference eth_account output' do
        sig = fixture_signer.sign_user_signed_action(
          base_message.merge(data: '0xdeadbeef'),
          'HyperliquidTransaction:SendToEvmWithData',
          Hyperliquid::Signing::EIP712::SEND_TO_EVM_WITH_DATA_TYPES
        )
        expect(sig[:r]).to eq('0xc628edcdf24aa7a5916314418f738eb1f1fdad468ef499dd706d7cf164e58a02')
        expect(sig[:s]).to eq('0x11542fd00026ce84da9cd3004a31ddff18a1e70ce00f1a6dce6fbf16d618cf67')
        expect(sig[:v]).to eq(27)
      end
    end
  end

  describe '#user_portfolio_margin' do
    let(:portfolio_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends userPortfolioMargin with lowercased user and full user-signed envelope' do
      mixed_case_user = '0xABCDEF1234567890ABCDEF1234567890ABCDEF12'

      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'userPortfolioMargin' &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet' &&
            action['user'] == mixed_case_user.downcase &&
            action['enabled'] == true &&
            action['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: portfolio_response.to_json)

      result = exchange.user_portfolio_margin(user: mixed_case_user, enabled: true)
      expect(result['status']).to eq('ok')
    end

    it 'forwards enabled: false verbatim' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['enabled'] == false
        end
        .to_return(status: 200, body: portfolio_response.to_json)

      result = exchange.user_portfolio_margin(
        user: '0x1111111111111111111111111111111111111111',
        enabled: false
      )
      expect(result['status']).to eq('ok')
    end

    it 'invokes sign_user_signed_action with the new primary type and constant' do
      stub_request(:post, exchange_endpoint)
        .to_return(status: 200, body: portfolio_response.to_json)

      expect(signer).to receive(:sign_user_signed_action).with(
        hash_including(
          user: '0x1111111111111111111111111111111111111111',
          enabled: true
        ),
        'HyperliquidTransaction:UserPortfolioMargin',
        Hyperliquid::Signing::EIP712::USER_PORTFOLIO_MARGIN_TYPES
      ).and_call_original

      exchange.user_portfolio_margin(
        user: '0x1111111111111111111111111111111111111111',
        enabled: true
      )
    end
  end

  describe '#spot_user' do
    let(:spot_user_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends spotUser with toggleSpotDusting wrapping when opt_out: true' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'spotUser' &&
            action['toggleSpotDusting'] == { 'optOut' => true } &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: spot_user_response.to_json)

      result = exchange.spot_user(opt_out: true)
      expect(result['status']).to eq('ok')
    end

    it 'sends spotUser with optOut: false when opt_out: false' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['toggleSpotDusting'] == { 'optOut' => false }
        end
        .to_return(status: 200, body: spot_user_response.to_json)

      result = exchange.spot_user(opt_out: false)
      expect(result['status']).to eq('ok')
    end

    it 'propagates expires_after when set on the exchange' do
      exchange.expires_after = 9_999_999_999_999
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['expiresAfter'] == 9_999_999_999_999 &&
            body.dig('action', 'type') == 'spotUser'
        end
        .to_return(status: 200, body: spot_user_response.to_json)

      result = exchange.spot_user(opt_out: true)
      expect(result['status']).to eq('ok')
    end

    it 'does not include vaultAddress in the payload' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          !body.key?('vaultAddress')
        end
        .to_return(status: 200, body: spot_user_response.to_json)

      result = exchange.spot_user(opt_out: true)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#authorize_aqav2_role' do
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends authorizeAqav2Role with token and role' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'authorizeAqav2Role' &&
            action['token'] == 0 &&
            action['role'] == 'technical' &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.authorize_aqav2_role(token: 0, role: 'technical')
      expect(result['status']).to eq('ok')
    end

    it 'sends treasury role when role: "treasury"' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['role'] == 'treasury'
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.authorize_aqav2_role(token: 1, role: 'treasury')
      expect(result['status']).to eq('ok')
    end

    it 'coerces token to integer' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['token'] == 5
        end
        .to_return(status: 200, body: ok_response.to_json)

      exchange.authorize_aqav2_role(token: '5', role: 'technical')
    end

    it 'propagates expires_after when set on the exchange' do
      exchange.expires_after = 9_999_999_999_999
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['expiresAfter'] == 9_999_999_999_999 &&
            body.dig('action', 'type') == 'authorizeAqav2Role'
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.authorize_aqav2_role(token: 0, role: 'technical')
      expect(result['status']).to eq('ok')
    end

    it 'does not include vaultAddress in the payload' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          !body.key?('vaultAddress')
        end
        .to_return(status: 200, body: ok_response.to_json)

      exchange.authorize_aqav2_role(token: 0, role: 'technical')
    end
  end

  # Byte-parity fixtures captured 2026-10-01 against hyperliquid-python-sdk 0.24.0 (master 2fdb18f95176),
  # eth_account 0.13.7, msgpack 1.2.3 — see ~/agent-state/hyperliquid-sdk-fixtures/capture_perp_deploy_signatures.py.
  # P* fixtures come from the Python SDK's own perp_deploy_* methods; D* are hand-built in live-explorer key order
  # and signed with the Python SDK's sign_l1_action. Pre-verified 19/19 against the current Ruby Signer.
  describe 'perpDeploy (HIP-3 deployer actions)' do
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:fixture_private_key) { '0x1111111111111111111111111111111111111111111111111111111111111111' }
    let(:fixture_signer) { Hyperliquid::Signing::Signer.new(private_key: fixture_private_key, testnet: false) }
    let(:fixture_exchange) { described_class.new(client: client, signer: fixture_signer, info: info, testnet: false) }
    let(:fixture_nonce) { 1_700_000_000_000 }

    before { allow(fixture_exchange).to receive(:timestamp_ms).and_return(fixture_nonce) }

    # Captures the posted body; returns [action JSON string in wire key order, parsed body].
    def capture_perp_deploy
      raw = nil
      stub_request(:post, exchange_endpoint)
        .with { |req| raw = req.body }
        .to_return(status: 200, body: ok_response.to_json)
      result = yield
      expect(result['status']).to eq('ok')
      body = JSON.parse(raw)
      [JSON.generate(body['action']), body]
    end

    def expect_signature(body, sig_r, sig_s, sig_v)
      expect(body['signature']).to eq('r' => sig_r, 's' => sig_s, 'v' => sig_v)
      expect(body['nonce']).to eq(fixture_nonce)
      expect(body).not_to have_key('vaultAddress')
    end

    it 'P1: registerAsset with max_gas and no schema matches the Python SDK' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_register_asset(
          dex: 'test', max_gas: 1_000_000_000_000, coin: 'test:TEST0', sz_decimals: 2,
          oracle_px: '10', margin_table_id: 10, only_isolated: false
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","registerAsset":{"maxGas":1000000000000,"assetRequest":' \
        '{"coin":"test:TEST0","szDecimals":2,"oraclePx":"10","marginTableId":10,"onlyIsolated":false},' \
        '"dex":"test","schema":null}}'
      )
      expect_signature(body,
                       '0x0008115d5c4d25e4f3b59dd1cbab8333160bd910f807d527fd127d81d8af7bb9',
                       '0x247732d929724cd4cd39290e04494e0bd96a7093572bf7a3fcfa5494f0cce184', 27)
    end

    it 'P2: registerAsset with schema sends null maxGas and lowercases oracleUpdater' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_register_asset(
          dex: 'test', coin: 'test:TEST0', sz_decimals: 2, oracle_px: 10, margin_table_id: 10,
          only_isolated: true,
          schema: { full_name: 'test dex', collateral_token: 0,
                    oracle_updater: '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A' }
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","registerAsset":{"maxGas":null,"assetRequest":' \
        '{"coin":"test:TEST0","szDecimals":2,"oraclePx":"10","marginTableId":10,"onlyIsolated":true},' \
        '"dex":"test","schema":{"fullName":"test dex","collateralToken":0,' \
        '"oracleUpdater":"0x19e7e376e7c213b7e7e7e46cc70a5dd086daff2a"}}}'
      )
      expect_signature(body,
                       '0x88f7ad23cfbbf1071abe334c9800c730b2f3bb931efcd96b887c187dda6452fb',
                       '0x32d59c5e07a8cb4d1496693c43f86e023d988f19b0ef8e5698a5604b14d01f89', 27)
    end

    it 'D1: registerAsset2 normalizes a numeric oracle_px and sends null schema' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_register_asset2(
          dex: 'test', coin: 'test:TEST1', sz_decimals: 3, oracle_px: 2.5, margin_table_id: 20,
          margin_mode: 'strictIsolated'
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","registerAsset2":{"maxGas":null,"assetRequest":' \
        '{"coin":"test:TEST1","szDecimals":3,"oraclePx":"2.5","marginTableId":20,"marginMode":"strictIsolated"},' \
        '"dex":"test","schema":null}}'
      )
      expect_signature(body,
                       '0x25f3c3bfbf5d184b7ca6e89cda796c9de6ddd162091cb76c84674283215e480c',
                       '0x4011bfa29eb8c1fe86f77477470e75e1dbfeffb7efac48ffb288a1ddb0e3cf3b', 27)
    end

    it 'D2: registerAsset2 with schema sends null oracleUpdater and no isStar' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_register_asset2(
          dex: 'test', max_gas: 500_000_000, coin: 'test:TEST1', sz_decimals: 3, oracle_px: '2.5',
          margin_table_id: 20, margin_mode: 'noCross', schema: { full_name: 'test dex', collateral_token: 0 }
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","registerAsset2":{"maxGas":500000000,"assetRequest":' \
        '{"coin":"test:TEST1","szDecimals":3,"oraclePx":"2.5","marginTableId":20,"marginMode":"noCross"},' \
        '"dex":"test","schema":{"fullName":"test dex","collateralToken":0,"oracleUpdater":null}}}'
      )
      expect(json).not_to include('isStar')
      expect_signature(body,
                       '0x2f780e22da1a7e0ac38031e760729d669f078fd1dd9d12d262ec22c0cb5cd8a0',
                       '0x1800cbaf5709af341ee255b9f6ee0b1869ca30d5c0f63341c4ed8193f36f0660', 27)
    end

    it 'appends isStar after oracleUpdater when the schema has :is_star' do
      json, = capture_perp_deploy do
        exchange.perp_deploy_register_asset2(
          dex: 'test', coin: 'test:TEST1', sz_decimals: 3, oracle_px: '2.5', margin_table_id: 20,
          margin_mode: 'noCross', schema: { full_name: 'x', collateral_token: 0, is_star: true }
        )
      end
      expect(json).to include(
        '"schema":{"fullName":"x","collateralToken":0,"oracleUpdater":null,"isStar":true}'
      )
    end

    it 'raises ArgumentError for a non-String, non-Numeric decimal without posting' do
      expect do
        exchange.perp_deploy_register_asset(
          dex: 'test', coin: 'test:TEST0', sz_decimals: 2, oracle_px: :bad, margin_table_id: 10,
          only_isolated: false
        )
      end.to raise_error(ArgumentError, /decimal must be String or Numeric/)
      expect(a_request(:post, exchange_endpoint)).not_to have_been_made
    end

    it 'P3: setOracle sorts each price list and normalizes numerics' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_oracle(
          dex: 'test',
          oracle_pxs: { 'test:TEST1' => 1, 'test:TEST0' => 12.0 },
          all_mark_pxs: [{ 'test:TEST1' => '3', 'test:TEST0' => '14' }],
          external_perp_pxs: { 'test:TEST0' => '12.1', 'test:TEST1' => '1.1' }
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","setOracle":{"dex":"test",' \
        '"oraclePxs":[["test:TEST0","12"],["test:TEST1","1"]],' \
        '"markPxs":[[["test:TEST0","14"],["test:TEST1","3"]]],' \
        '"externalPerpPxs":[["test:TEST0","12.1"],["test:TEST1","1.1"]]}}'
      )
      expect_signature(body,
                       '0x29a1917249c8e0b179fdc155f20fb7523900d4c287fa9d9755d914069fd00bdf',
                       '0x7339a3eea1e3f106f9b79105f2e6d615108f6a8c3b88b1030f8ca3255caef9ba', 27)
    end

    it 'setOracle with no mark prices sends an empty markPxs list' do
      json, = capture_perp_deploy do
        exchange.perp_deploy_set_oracle(
          dex: 'test', oracle_pxs: { 'test:A' => '1' }, all_mark_pxs: [], external_perp_pxs: { 'test:A' => '1' }
        )
      end
      expect(json).to include('"markPxs":[]')
    end

    it 'D3: setFundingMultipliers sorts by coin and normalizes numerics' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_funding_multipliers(multipliers: { 'test:B' => 2, 'test:A' => '0.5' })
      end
      expect(json).to eq('{"type":"perpDeploy","setFundingMultipliers":[["test:A","0.5"],["test:B","2"]]}')
      expect_signature(body,
                       '0xe094af5e0147a7f986554314c3bfdf9f2232463a0219a09ac94b852d18979a4f',
                       '0x4b1c02770a3291e4c07e12641ccec0b00ab0337163dc8803fb5dbc2dfd59191a', 28)
    end

    it 'D4: setFundingInterestRates keeps signed decimals' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_funding_interest_rates(rates: { 'test:A' => -0.0001, 'test:B' => '0.00005' })
      end
      expect(json).to eq(
        '{"type":"perpDeploy","setFundingInterestRates":[["test:A","-0.0001"],["test:B","0.00005"]]}'
      )
      expect_signature(body,
                       '0xf0d4bef909927f77abcf2c248b380bdd498c2b64198ede5f73d99923a44332a1',
                       '0x4db0eab46a724be79df52d1127e691b7952e786335ff7a670f80933ce3e7de6f', 27)
    end

    it 'D5: setFundingClamps sorts by coin and normalizes numerics' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_funding_clamps(clamps: { 'test:A' => '0.0003', 'test:B' => 0.01 })
      end
      expect(json).to eq('{"type":"perpDeploy","setFundingClamps":[["test:A","0.0003"],["test:B","0.01"]]}')
      expect_signature(body,
                       '0x40a0321ff5eab42664b1106ddceaab3b134212006e86b394683c9c82e13eaaa3',
                       '0x48e2adf87085182c1f8cb3d3a3860b314c87bc37facbf2173bcb3b1efe473fd3', 27)
    end

    it 'D6: haltTrading sends coin and isHalted' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_halt_trading(coin: 'test:A', is_halted: true)
      end
      expect(json).to eq('{"type":"perpDeploy","haltTrading":{"coin":"test:A","isHalted":true}}')
      expect_signature(body,
                       '0x23a967f621a19a85e5d7d26e605902e28f92c2f9894b9e573c09d63f9afec93a',
                       '0x2eba0cf40566517e588dc6f8d939b49ad164141312fb79fd2579ff96e62eaf91', 27)
    end

    it 'D7: insertMarginTable keeps tier order and coerces integers' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_insert_margin_table(
          dex: 'test', description: 'tiered',
          margin_tiers: [{ lower_bound: 0, max_leverage: 20 }, { lower_bound: '1000000', max_leverage: 10 }]
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","insertMarginTable":{"dex":"test","marginTable":{"description":"tiered",' \
        '"marginTiers":[{"lowerBound":0,"maxLeverage":20},{"lowerBound":1000000,"maxLeverage":10}]}}}'
      )
      expect_signature(body,
                       '0x96b7b729f59cad9e76c5988ca0c495f8d5b4482de932fe2127c8ef4cd6b538a9',
                       '0x77964b77ede19e8863c7975770062c92c565226069bc68303cde8bcacd20e7a7', 27)
    end

    it 'D8: setMarginTableIds sorts by coin and coerces ids to Integer' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_margin_table_ids(margin_table_ids: { 'test:B' => 20, 'test:A' => '10' })
      end
      expect(json).to eq('{"type":"perpDeploy","setMarginTableIds":[["test:A",10],["test:B",20]]}')
      expect_signature(body,
                       '0xe9fd3950d7d2f99154d04c54566f961f4a7b8aff9522962a0f018575c058da00',
                       '0x01f47a245b78195d2bb3851919576dc121791a946cbca9fd575569944ce75ddb', 28)
    end

    it 'D12: setMarginModes sorts by coin and passes modes through' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_margin_modes(
          margin_modes: { 'test:B' => 'strictIsolated', 'test:A' => 'noCross' }
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","setMarginModes":[["test:A","noCross"],["test:B","strictIsolated"]]}'
      )
      expect_signature(body,
                       '0x5385a57fd6f57c1c1c57a115641af91c8ff52635fb8e73c1520b9d4a0168dba0',
                       '0x4aae95c24660336b03b72d9db8ea5816a0e66b3350a75b52f7fa28cf4510db76', 27)
    end

    it 'D10: setOpenInterestCaps sorts by coin and sends nil caps as null' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_open_interest_caps(caps: { 'test:B' => nil, 'test:A' => 1_000_000 })
      end
      expect(json).to eq('{"type":"perpDeploy","setOpenInterestCaps":[["test:A",1000000],["test:B",null]]}')
      expect_signature(body,
                       '0xad771891b3b5b3fca5aa292885cb3846e691c60965a60ad893b025963de1f5d4',
                       '0x77a48e15a935cdb8681591a064c63c6607e4c6049a21bd393dfafca6dd342faa', 27)
    end

    it 'D9: setFeeRecipient lowercases the recipient' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_fee_recipient(
          dex: 'test', fee_recipient: '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A'
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","setFeeRecipient":{"dex":"test",' \
        '"feeRecipient":"0x19e7e376e7c213b7e7e7e46cc70a5dd086daff2a"}}'
      )
      expect_signature(body,
                       '0xa0bd1cf078ace3162be390db3c33b2e36548cfc76202a83ee8754e1af5fc09d7',
                       '0x1447f036b2f1927d558267d3f1e3404fb44d51235b19531d096e4a9b37bf91b9', 28)
    end

    it 'D13: setDeployerFees sorts by coin and normalizes scale' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_deployer_fees(
          fees: { 'test:B' => { scale: '3.01', growth_mode: true }, 'test:A' => { scale: 0.5, growth_mode: false } }
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","setDeployerFees":[["test:A",{"scale":"0.5","growthMode":false}],' \
        '["test:B",{"scale":"3.01","growthMode":true}]]}'
      )
      expect_signature(body,
                       '0xbe7b0c152491cbb0bf81a18459057dc0ec00e5879c67725e48a3722f6703fe0f',
                       '0x5bad12e9690590368c26e2b9c531044ae0e4bff0ccc235ebb929e064a998ea5c', 27)
    end

    it 'D11: setSubDeployers keeps caller order and lowercases user' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_sub_deployers(
          dex: 'test',
          sub_deployers: [
            { variant: 'setOracle', user: '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A', allowed: true },
            { variant: 'haltTrading', user: '0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A', allowed: false }
          ]
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","setSubDeployers":{"dex":"test","subDeployers":[' \
        '{"variant":"setOracle","user":"0x19e7e376e7c213b7e7e7e46cc70a5dd086daff2a","allowed":true},' \
        '{"variant":"haltTrading","user":"0x19e7e376e7c213b7e7e7e46cc70a5dd086daff2a","allowed":false}]}}'
      )
      expect_signature(body,
                       '0x25086d86dd87241723d5211a37eaf9043f3f193b1a14119788946321b4db840f',
                       '0x4e29652c1d7289876412253e0a3daabf6cae35ff206f4f51f486f6b76b0182ae', 27)
    end

    it 'setSubDeployers passes a Hash variant through verbatim' do
      json, = capture_perp_deploy do
        exchange.perp_deploy_set_sub_deployers(
          dex: 'test',
          sub_deployers: [{ variant: { hip3Star: 'modifyApproval' }, user: '0xABCDEF0000000000000000000000000000000001',
                            allowed: true }]
        )
      end
      expect(json).to include(
        '{"variant":{"hip3Star":"modifyApproval"},"user":"0xabcdef0000000000000000000000000000000001","allowed":true}'
      )
    end

    it 'D14: setPerpAnnotation sends a null displayName by default' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_set_perp_annotation(
          coin: 'test:A', category: 'stocks', description: 'Test asset', keywords: %w[test demo]
        )
      end
      expect(json).to eq(
        '{"type":"perpDeploy","setPerpAnnotation":{"coin":"test:A","category":"stocks",' \
        '"description":"Test asset","displayName":null,"keywords":["test","demo"]}}'
      )
      expect_signature(body,
                       '0x693fa311a645b9115ec314b6146ccf4cf80bec1fc99353976a49aec2bb372279',
                       '0x7c8586f6b9c1b2b28e598f61f4b07f21569cb13a38c34084ddcd69e9ea497c54', 27)
    end

    it 'D15: disableDex sends the dex name as a bare string' do
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_disable_dex(dex: 'test')
      end
      expect(json).to eq('{"type":"perpDeploy","disableDex":"test"}')
      expect_signature(body,
                       '0x94ec2a17a9ddf3eb620130f783241421d6ba5d4bb3ae05a5a2cbf89c80157c88',
                       '0x34688c81da1cc2ed1678b0ec0750e484680fc55f6b02579dd19d571696b13fb4', 28)
    end

    it 'D16: propagates expires_after into the hash and the posted body' do
      fixture_exchange.expires_after = 1_700_000_060_000
      json, body = capture_perp_deploy do
        fixture_exchange.perp_deploy_halt_trading(coin: 'test:A', is_halted: false)
      end
      expect(json).to eq('{"type":"perpDeploy","haltTrading":{"coin":"test:A","isHalted":false}}')
      expect(body['expiresAfter']).to eq(1_700_000_060_000)
      expect_signature(body,
                       '0x6bb02fb51b10d56c6bef6f39c9719a77ce77720440c24108c5ef6d834654e88b',
                       '0x5e2307268178d684b3cede5b8f5ecc446ac709844fb529e9895e5a2353395409', 28)
    end
  end

  describe '#c_deposit' do
    let(:c_deposit_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends cDeposit with wei as Integer and full user-signed envelope' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cDeposit' &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet' &&
            action['wei'] == 100_000_000 &&
            action['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: c_deposit_response.to_json)

      result = exchange.c_deposit(wei: 100_000_000)
      expect(result['status']).to eq('ok')
    end

    it 'coerces wei to Integer defensively' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['wei'] == 500_000_000
        end
        .to_return(status: 200, body: c_deposit_response.to_json)

      result = exchange.c_deposit(wei: 500_000_000.0)
      expect(result['status']).to eq('ok')
    end

    it 'invokes sign_user_signed_action with the new primary type and constant' do
      stub_request(:post, exchange_endpoint)
        .to_return(status: 200, body: c_deposit_response.to_json)

      expect(signer).to receive(:sign_user_signed_action).with(
        hash_including(wei: 100_000_000),
        'HyperliquidTransaction:CDeposit',
        Hyperliquid::Signing::EIP712::C_DEPOSIT_TYPES
      ).and_call_original

      exchange.c_deposit(wei: 100_000_000)
    end
  end

  describe '#c_withdraw' do
    let(:c_withdraw_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends cWithdraw with wei as Integer and full user-signed envelope' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'cWithdraw' &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet' &&
            action['wei'] == 100_000_000 &&
            action['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: c_withdraw_response.to_json)

      result = exchange.c_withdraw(wei: 100_000_000)
      expect(result['status']).to eq('ok')
    end

    it 'coerces wei to Integer defensively' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['wei'] == 500_000_000
        end
        .to_return(status: 200, body: c_withdraw_response.to_json)

      result = exchange.c_withdraw(wei: 500_000_000.0)
      expect(result['status']).to eq('ok')
    end

    it 'invokes sign_user_signed_action with the new primary type and constant' do
      stub_request(:post, exchange_endpoint)
        .to_return(status: 200, body: c_withdraw_response.to_json)

      expect(signer).to receive(:sign_user_signed_action).with(
        hash_including(wei: 100_000_000),
        'HyperliquidTransaction:CWithdraw',
        Hyperliquid::Signing::EIP712::C_WITHDRAW_TYPES
      ).and_call_original

      exchange.c_withdraw(wei: 100_000_000)
    end
  end

  describe '#twap_order' do
    let(:twap_order_response) do
      { 'status' => 'ok',
        'response' => { 'type' => 'twapOrder',
                        'data' => { 'status' => { 'running' => { 'twapId' => 42 } } } } }
    end

    it 'sends twapOrder with the nested twap shape and correct field order' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'twapOrder' &&
            action['twap'] == { 'a' => 1, 'b' => true, 's' => '1.5', 'r' => false, 'm' => 30, 't' => true } &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: twap_order_response.to_json)

      result = exchange.twap_order(
        coin: 'ETH', is_buy: true, size: '1.5', reduce_only: false, minutes: 30, randomize: true
      )
      expect(result['status']).to eq('ok')
    end

    it 'normalizes size via float_to_wire' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['twap']['s'] == '0.5'
        end
        .to_return(status: 200, body: twap_order_response.to_json)

      result = exchange.twap_order(
        coin: 'BTC', is_buy: false, size: 0.5, reduce_only: true, minutes: 5, randomize: false
      )
      expect(result['status']).to eq('ok')
    end

    it 'propagates vault_address into the payload' do
      vault = '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd'
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault
        end
        .to_return(status: 200, body: twap_order_response.to_json)

      result = exchange.twap_order(
        coin: 'ETH', is_buy: true, size: '1', reduce_only: false, minutes: 10, randomize: false,
        vault_address: vault
      )
      expect(result['status']).to eq('ok')
    end

    it 'passes the details field through verbatim when provided' do
      details = { 't' => { 'p' => '100.5', 'a' => true }, 's' => '95' }
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'twapOrder' &&
            action['details'] == { 't' => { 'p' => '100.5', 'a' => true }, 's' => '95' }
        end
        .to_return(status: 200, body: twap_order_response.to_json)

      result = exchange.twap_order(
        coin: 'ETH', is_buy: true, size: '1', reduce_only: false, minutes: 10, randomize: true,
        details: details
      )
      expect(result['status']).to eq('ok')
    end

    it 'accepts nil trigger and stop price (details with nulls)' do
      details = { 't' => nil, 's' => nil }
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['details'] == { 't' => nil, 's' => nil }
        end
        .to_return(status: 200, body: twap_order_response.to_json)

      result = exchange.twap_order(
        coin: 'BTC', is_buy: false, size: '0.5', reduce_only: true, minutes: 5, randomize: false,
        details: details
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe '#twap_cancel' do
    let(:twap_cancel_response) do
      { 'status' => 'ok',
        'response' => { 'type' => 'twapCancel', 'data' => { 'status' => 'success' } } }
    end

    it 'sends twapCancel with asset index and twap id' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'twapCancel' &&
            action['a'] == 0 &&
            action['t'] == 42 &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: twap_cancel_response.to_json)

      result = exchange.twap_cancel(coin: 'BTC', twap_id: 42)
      expect(result['status']).to eq('ok')
    end

    it 'propagates vault_address into the payload' do
      vault = '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd'
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault
        end
        .to_return(status: 200, body: twap_cancel_response.to_json)

      result = exchange.twap_cancel(coin: 'BTC', twap_id: 7, vault_address: vault)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#trailing_stop' do
    let(:trailing_stop_response) do
      { 'status' => 'ok',
        'response' => { 'type' => 'trailingStop', 'data' => { 'oid' => 7_773_830_8 } } }
    end

    it 'sends trailingStop with the documented action shape' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'trailingStop' &&
            action['asset'] == 1 &&
            action['isBuy'] == true &&
            action['sz'] == '1.5' &&
            action['reduceOnly'] == false &&
            action['retracement'] == { 'pct' => '1.234%' } &&
            action['activationPx'].nil? &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: trailing_stop_response.to_json)

      result = exchange.trailing_stop(
        coin: 'ETH', is_buy: true, size: '1.5', reduce_only: false, retracement: { pct: '1.234%' }
      )
      expect(result['status']).to eq('ok')
    end

    it 'normalizes numeric size and passes px retracement and activation_px through' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['sz'] == '0.5' &&
            action['retracement'] == { 'px' => '3500' } &&
            action['activationPx'] == '3600'
        end
        .to_return(status: 200, body: trailing_stop_response.to_json)

      result = exchange.trailing_stop(
        coin: 'BTC', is_buy: false, size: 0.5, reduce_only: true,
        retracement: { px: '3500' }, activation_px: '3600'
      )
      expect(result['status']).to eq('ok')
    end

    it 'propagates vault_address into the payload' do
      vault = '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd'
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['vaultAddress'] == vault
        end
        .to_return(status: 200, body: trailing_stop_response.to_json)

      result = exchange.trailing_stop(
        coin: 'ETH', is_buy: true, size: '1', reduce_only: false,
        retracement: { pct: '1%' }, vault_address: vault
      )
      expect(result['status']).to eq('ok')
    end
  end

  describe 'HIP-4 userOutcome variants' do
    let(:outcome_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    describe '#split_outcome' do
      it 'sends userOutcome with splitOutcome inner shape and string amount' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            action = body['action']
            action['type'] == 'userOutcome' &&
              action['splitOutcome'] == { 'outcome' => 0, 'amount' => '1' } &&
              body['signature'].is_a?(Hash) &&
              !body.key?('vaultAddress')
          end
          .to_return(status: 200, body: outcome_response.to_json)

        result = exchange.split_outcome(outcome: 0, amount: '1')
        expect(result['status']).to eq('ok')
      end

      it 'coerces numeric amount to string' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['action']['splitOutcome']['amount'] == '2.5'
          end
          .to_return(status: 200, body: outcome_response.to_json)

        result = exchange.split_outcome(outcome: 3, amount: 2.5)
        expect(result['status']).to eq('ok')
      end
    end

    describe '#merge_outcome' do
      it 'sends mergeOutcome with explicit amount as string' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['action']['mergeOutcome'] == { 'outcome' => 1, 'amount' => '5' }
          end
          .to_return(status: 200, body: outcome_response.to_json)

        result = exchange.merge_outcome(outcome: 1, amount: 5)
        expect(result['status']).to eq('ok')
      end

      it 'passes amount as null when omitted (maximum available)' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            inner = body['action']['mergeOutcome']
            inner['outcome'] == 2 && inner['amount'].nil?
          end
          .to_return(status: 200, body: outcome_response.to_json)

        result = exchange.merge_outcome(outcome: 2)
        expect(result['status']).to eq('ok')
      end
    end

    describe '#merge_question' do
      it 'sends mergeQuestion with explicit amount as string' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['action']['mergeQuestion'] == { 'question' => 7, 'amount' => '1.25' }
          end
          .to_return(status: 200, body: outcome_response.to_json)

        result = exchange.merge_question(question: 7, amount: '1.25')
        expect(result['status']).to eq('ok')
      end

      it 'passes amount as null when omitted (maximum available)' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            inner = body['action']['mergeQuestion']
            inner['question'] == 8 && inner['amount'].nil?
          end
          .to_return(status: 200, body: outcome_response.to_json)

        result = exchange.merge_question(question: 8)
        expect(result['status']).to eq('ok')
      end
    end

    describe '#negate_outcome' do
      it 'sends negateOutcome with question, outcome, and string amount' do
        stub_request(:post, exchange_endpoint)
          .with do |req|
            body = JSON.parse(req.body)
            body['action']['negateOutcome'] == {
              'question' => 4, 'outcome' => 1, 'amount' => '10'
            }
          end
          .to_return(status: 200, body: outcome_response.to_json)

        result = exchange.negate_outcome(question: 4, outcome: 1, amount: 10)
        expect(result['status']).to eq('ok')
      end
    end
  end

  describe 'HIP-4 outcome deployer actions' do
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:captured) { {} }

    before do
      stub_request(:post, exchange_endpoint)
        .with { |req| captured[:body] = JSON.parse(req.body) }
        .to_return(status: 200, body: ok_response.to_json)
    end

    # Not a `let`: examples that call twice must see the latest request body.
    def body
      captured[:body]
    end

    describe '#activate_outcome_deployer' do
      it 'sends the activate variant with the venue name and an L1 signature' do
        result = exchange.activate_outcome_deployer(venue_name: 'ab')

        expect(result['status']).to eq('ok')
        expect(body['action'].to_json).to eq(
          { type: 'activateOutcomeDeployer', activate: { venueName: 'ab' } }.to_json
        )
        expect(body).not_to have_key('vaultAddress')
        expect(body['nonce']).to be_a(Integer)
        expect(body['signature']).to be_a(Hash)
      end

      it 'propagates expires_after when set on the exchange' do
        exchange.expires_after = 9_999_999_999_999
        exchange.activate_outcome_deployer(venue_name: 'ab')

        expect(body['expiresAfter']).to eq(9_999_999_999_999)
      end

      it 'no longer accepts the removed is_deactivate: keyword' do
        expect { exchange.activate_outcome_deployer(is_deactivate: false) }.to raise_error(ArgumentError)
      end
    end

    describe '#deactivate_outcome_deployer' do
      it 'sends the deactivate variant with an explicit null value' do
        exchange.deactivate_outcome_deployer

        expect(body['action'].key?('deactivate') && body['action']['deactivate'].nil?).to be(true)
        expect(body['action'].to_json).to eq({ type: 'activateOutcomeDeployer', deactivate: nil }.to_json)
        expect(body).not_to have_key('vaultAddress')
      end
    end

    describe '#register_standalone_outcome_from_template' do
      it 'sends the docs example with keywords stringified and sorted' do
        exchange.register_standalone_outcome_from_template(
          venue: 'ab',
          template_id: 'abc',
          keyword_to_value: { underlying: 'ABC', expiry: '20260801-0600', target: 100 },
          deployer_fee_scale: '1'
        )

        expected = {
          type: 'outcomeDeploy',
          venue: 'ab',
          operation: {
            registerStandaloneOutcomeFromTemplate: {
              id: 'abc',
              keywordToValue: [%w[expiry 20260801-0600], %w[target 100], %w[underlying ABC]],
              deployerFeeScale: '1'
            }
          }
        }
        expect(body['action'].to_json).to eq(expected.to_json)
      end

      it 'converts Numeric fee scales to canonical decimal strings' do
        { 1.5 => '1.5', 1 => '1' }.each do |input, wire|
          exchange.register_standalone_outcome_from_template(
            venue: 'ab', template_id: 'abc', keyword_to_value: {}, deployer_fee_scale: input
          )
          instance = body.dig('action', 'operation', 'registerStandaloneOutcomeFromTemplate')
          expect(instance['deployerFeeScale']).to eq(wire)
        end
      end

      it 'sends an empty keyword list for an empty Hash' do
        exchange.register_standalone_outcome_from_template(
          venue: 'ab', template_id: 'sportsContestDraw', keyword_to_value: {}, deployer_fee_scale: '0'
        )

        expect(body.dig('action', 'operation', 'registerStandaloneOutcomeFromTemplate', 'keywordToValue')).to eq([])
      end

      it 'sends the venue verbatim, without vaultAddress, propagating expires_after' do
        exchange.expires_after = 9_999_999_999_999
        exchange.register_standalone_outcome_from_template(
          venue: 'AB', template_id: 'abc', keyword_to_value: [%w[k v]], deployer_fee_scale: '1'
        )

        expect(body['action']['venue']).to eq('AB')
        expect(body).not_to have_key('vaultAddress')
        expect(body['expiresAfter']).to eq(9_999_999_999_999)
      end
    end

    describe '#settle_outcome' do
      let(:settle_args) do
        {
          venue: 'ab',
          outcome: 7,
          settle_fraction: '1',
          name: 'template:abc',
          description: 'expiry:20260801-0600|target:100|underlying:ABC',
          side_names: ['template:Over', 'template:Under']
        }
      end

      it 'sends the docs example in wire key order with empty details by default' do
        exchange.settle_outcome(**settle_args)

        expected = {
          type: 'outcomeDeploy',
          venue: 'ab',
          operation: {
            settleOutcome: {
              outcome: 7,
              settleFraction: '1',
              details: '',
              nameAndDescription: ['template:abc', 'expiry:20260801-0600|target:100|underlying:ABC'],
              sideNames: ['template:Over', 'template:Under']
            }
          }
        }
        expect(body['action'].to_json).to eq(expected.to_json)
      end

      it 'converts Numeric settle fractions to canonical decimal strings' do
        { 0.66 => '0.66', 1 => '1' }.each do |input, wire|
          exchange.settle_outcome(**settle_args, settle_fraction: input)
          expect(body.dig('action', 'operation', 'settleOutcome', 'settleFraction')).to eq(wire)
        end
      end

      it 'coerces the outcome id to an Integer' do
        exchange.settle_outcome(**settle_args, outcome: '7')

        expect(body.dig('action', 'operation', 'settleOutcome', 'outcome')).to eq(7)
      end
    end

    describe '#register_question_from_template' do
      it 'sends named instances without a fee scale, in caller order, each with sorted keywords' do
        exchange.register_question_from_template(
          venue: 'ab',
          template_id: 'q',
          keyword_to_value: { 'z' => 1, 'a' => 2 },
          deployer_fee_scale: 0.5,
          named_outcomes: [
            { template_id: 'q-outcome', keyword_to_value: { 'choice' => 'B', 'arm' => 'x' } },
            { template_id: 'q-outcome', keyword_to_value: { 'choice' => 'A' } }
          ]
        )

        op = body.dig('action', 'operation', 'registerQuestionFromTemplate')
        expect(op.keys).to eq(%w[questionTemplateInstance namedOutcomeTemplateInstances])
        expect(op['questionTemplateInstance']).to eq(
          'id' => 'q', 'keywordToValue' => [%w[a 2], %w[z 1]], 'deployerFeeScale' => '0.5'
        )
        named = op['namedOutcomeTemplateInstances']
        expect(named.none? { |inst| inst.key?('deployerFeeScale') }).to be(true)
        expect(named.map { |inst| inst['keywordToValue'] }).to eq([[%w[arm x], %w[choice B]], [%w[choice A]]])
      end
    end

    describe '#register_and_associate_named_outcome_from_template' do
      it 'sends an Integer question and an instance with only id and keywordToValue' do
        exchange.register_and_associate_named_outcome_from_template(
          venue: 'ab', question: '3', template_id: 'q-outcome', keyword_to_value: { 'choice' => 'C' }
        )

        op = body.dig('action', 'operation', 'registerAndAssociateNamedOutcomeFromTemplate')
        expect(op['question']).to eq(3)
        expect(op['namedOutcomeTemplateInstance'].keys).to eq(%w[id keywordToValue])
      end
    end

    describe '#set_outcome_sub_deployers' do
      it 'lowercases users, stringifies variants, and keeps caller order' do
        exchange.set_outcome_sub_deployers(
          venue: 'ab',
          changes: [
            { variant: :settleQuestion, user: '0x00000000000000000000000000000000000000AB', allowed: true },
            { variant: 'registerQuestionFromTemplate', user: '0x00000000000000000000000000000000000000cd',
              allowed: false }
          ]
        )

        expect(body.dig('action', 'operation', 'setSubDeployers')).to eq(
          [
            { 'variant' => 'settleQuestion', 'user' => '0x00000000000000000000000000000000000000ab',
              'allowed' => true },
            { 'variant' => 'registerQuestionFromTemplate', 'user' => '0x00000000000000000000000000000000000000cd',
              'allowed' => false }
          ]
        )
      end
    end
  end

  describe 'HIP-4 deployer L1 signature parity' do
    let(:fixture_key) { '0x1111111111111111111111111111111111111111111111111111111111111111' }
    let(:fixture_signer) { Hyperliquid::Signing::Signer.new(private_key: fixture_key, testnet: true) }
    let(:fixture_exchange) { described_class.new(client: client, signer: fixture_signer, info: info, testnet: true) }
    let(:captured) { {} }

    before do
      allow(fixture_exchange).to receive(:timestamp_ms).and_return(1_700_000_000_000)
      stub_request(:post, exchange_endpoint)
        .with { |req| captured[:body] = JSON.parse(req.body) }
        .to_return(status: 200, body: { 'status' => 'ok', 'response' => { 'type' => 'default' } }.to_json)
    end

    def expect_parity(action_hash, signature, expires_after: nil)
      action = JSON.parse(captured[:body]['action'].to_json, symbolize_names: true)
      computed = Hyperliquid::Signing::Signer.compute_action_hash(
        action, 1_700_000_000_000, expires_after: expires_after
      )
      expect(computed).to eq(action_hash)
      expect(captured[:body]['signature']).to eq(signature)
    end

    let(:settle_outcome_args) do
      {
        venue: 'ab',
        outcome: 7,
        settle_fraction: '1',
        name: 'template:abc',
        description: 'expiry:20260801-0600|target:100|underlying:ABC',
        side_names: ['template:Over', 'template:Under']
      }
    end

    it 'uses the fixture signer address' do
      expect(fixture_signer.address).to eq('0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A')
    end

    it 'matches the Python SDK for activate' do
      fixture_exchange.activate_outcome_deployer(venue_name: 'ab')

      expect_parity(
        '0x05c9f76676ddbd600019b49b0aaa2f5c7f89d1af6fc68fab6ea0ba8300188edc',
        {
          'r' => '0x6b27aaf2ca4cdf95fb0689d9db0ac5e2c941429f1394bd2b107361c6ca4fce6b',
          's' => '0x596511dfaf58c5f066dccb8314bb73ae1378a9b1694f262db2ffcfd11bf44c07',
          'v' => 27
        }
      )
    end

    it 'matches the Python SDK for deactivate' do
      fixture_exchange.deactivate_outcome_deployer

      expect_parity(
        '0x52f61b4bc82bd41ad4637339b4c53ab60521799aba47b7bc9b94510498ddcfac',
        {
          'r' => '0xac3c56be7d35df53ad70791e81cc8846f587c64500dd6b247e7dc6847f15d714',
          's' => '0x4a113c46921befbba26459bc8e97a4cdf118433a69283f85d5c924105fc31452',
          'v' => 28
        }
      )
    end

    it 'matches the Python SDK for registerStandaloneOutcomeFromTemplate (unsorted input)' do
      fixture_exchange.register_standalone_outcome_from_template(
        venue: 'ab',
        template_id: 'abc',
        keyword_to_value: { 'underlying' => 'ABC', 'expiry' => '20260801-0600', 'target' => '100' },
        deployer_fee_scale: '1'
      )

      expect_parity(
        '0xa2465dfa5d3ccab1d358a580a43035338ddc0bac3764d5cf71137e7c6ba908c5',
        {
          'r' => '0x4cea80c3993345321133f64e5945efd584c2dc079a71381201d886590f6d8075',
          's' => '0x32cd917c22e6532ae1b4aff78e15d726bb55ff8bf399bfe86bbe9ea9a1a77223',
          'v' => 27
        }
      )
    end

    it 'matches the Python SDK for settleOutcome' do
      fixture_exchange.settle_outcome(**settle_outcome_args)

      expect_parity(
        '0xc37763461981c07bd2815b23fc1a84b5b8faf32ce4f174c4752e8513d0c34cdb',
        {
          'r' => '0xd3c077290cdb96b798a285f7a7955f3acd05beecbdeb1d40bb06bcc5c33cf1df',
          's' => '0x56f3d1f1736f662753e79410e85291c9210819e726709b26cf4ad862b1f37cc9',
          'v' => 27
        }
      )
    end

    it 'matches the Python SDK for settleOutcome with expires_after' do
      fixture_exchange.expires_after = 1_700_000_060_000
      fixture_exchange.settle_outcome(**settle_outcome_args)

      expect(captured[:body]['expiresAfter']).to eq(1_700_000_060_000)
      expect_parity(
        '0xfbe74d8d3cb5740df98025b920faa2a084794efea3f2f6d4eaae5a7185efa1d6',
        {
          'r' => '0x186b4b5e23922d2d732a6b8df673301a442a7a7d52f1f15cdfd6e4148271a16b',
          's' => '0x68917f56f81785160cfba80f6b9db1d000115c18430f9b59a76497e19a9dccd9',
          'v' => 28
        },
        expires_after: 1_700_000_060_000
      )
    end

    it 'matches the Python SDK for registerQuestionFromTemplate' do
      fixture_exchange.register_question_from_template(
        venue: 'ab',
        template_id: 'abc',
        keyword_to_value: { 'expiry' => '20260801-1830' },
        deployer_fee_scale: '1',
        named_outcomes: [
          { template_id: 'abc-outcome', keyword_to_value: { 'choice' => 'A' } },
          { template_id: 'abc-outcome', keyword_to_value: { 'choice' => 'B' } },
          { template_id: 'abc-other', keyword_to_value: {} }
        ]
      )

      expect_parity(
        '0x889b7e71f3f06da88a74356b9b52444386c7510e36c385182b9ef3e6e349afa1',
        {
          'r' => '0xb38fbd449bd3d5099e867a58b71f4c3c0cfb5b0e37ce2df64e8cc0e9569a0862',
          's' => '0x78b246c0577de60e58d797c8374003cd251d985da97f2c287e060b629970cafb',
          'v' => 28
        }
      )
    end

    it 'matches the Python SDK for registerAndAssociateNamedOutcomeFromTemplate' do
      fixture_exchange.register_and_associate_named_outcome_from_template(
        venue: 'ab',
        question: 3,
        template_id: 'abc-outcome',
        keyword_to_value: { 'choice' => 'C' }
      )

      expect_parity(
        '0xc25d0d6850dc5de58e7bdde78b509f31d4bf747550b98bbeaada76a0f80d02e3',
        {
          'r' => '0xa21f568f1051d7a92b8c95748a0e7f2e60271762889f9530f486af7ef3a5c54e',
          's' => '0x5f696891a0961a358d091ad10061a347bcd6579fb13586586ae8180fc1d84c05',
          'v' => 28
        }
      )
    end

    it 'matches the Python SDK for setSubDeployers (mixed-case user, Symbol variant)' do
      fixture_exchange.set_outcome_sub_deployers(
        venue: 'ab',
        changes: [
          { variant: 'registerStandaloneOutcomeFromTemplate', user: '0x0000000000000000000000000000000000000ABC',
            allowed: true },
          { variant: :settleQuestion, user: '0x0000000000000000000000000000000000000abc', allowed: false }
        ]
      )

      expect_parity(
        '0xa7304fc7105de0a6cf0a20f07c48fc873b1847839ee1c52f2cbc60f0fab7ff15',
        {
          'r' => '0xb62c470807e24691144d3298367d6a84859ae09fc6f3dbbb0ee74cb6b3ca3623',
          's' => '0x779a0ce8a1b2050a18a2ec515b91d9241b4b220541471bd8c8b795924d5aa510',
          'v' => 28
        }
      )
    end
  end

  describe '#finalize_evm_contract' do
    let(:finalize_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends finalizeEvmContract with create variant input as a Hash' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'finalizeEvmContract' &&
            action['token'] == 200 &&
            action['input'] == { 'create' => { 'nonce' => 0 } } &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash) &&
            !body.key?('vaultAddress')
        end
        .to_return(status: 200, body: finalize_response.to_json)

      result = exchange.finalize_evm_contract(token: 200, input: { create: { nonce: 0 } })
      expect(result['status']).to eq('ok')
    end

    it 'passes through the firstStorageSlot string variant' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['input'] == 'firstStorageSlot'
        end
        .to_return(status: 200, body: finalize_response.to_json)

      result = exchange.finalize_evm_contract(token: 42, input: 'firstStorageSlot')
      expect(result['status']).to eq('ok')
    end

    it 'passes through the customStorageSlot string variant' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action']['input'] == 'customStorageSlot'
        end
        .to_return(status: 200, body: finalize_response.to_json)

      result = exchange.finalize_evm_contract(token: 99, input: 'customStorageSlot')
      expect(result['status']).to eq('ok')
    end

    it 'propagates expires_after when set on the exchange' do
      exchange.expires_after = 1_700_000_000_000
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['expiresAfter'] == 1_700_000_000_000
        end
        .to_return(status: 200, body: finalize_response.to_json)

      result = exchange.finalize_evm_contract(token: 1, input: 'firstStorageSlot')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#staking_link_disable_trading_user' do
    let(:disable_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:trading_user) { '0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD' }

    it 'sends stakingLinkDisableTradingUser with user-signed envelope and lowercased address' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'stakingLinkDisableTradingUser' &&
            action['signatureChainId'] == '0x66eee' &&
            action['hyperliquidChain'] == 'Testnet' &&
            action['tradingUser'] == trading_user.downcase &&
            action['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: disable_response.to_json)

      result = exchange.staking_link_disable_trading_user(trading_user: trading_user)
      expect(result['status']).to eq('ok')
    end

    it 'includes signature in request' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['signature'].is_a?(Hash) && body['signature']['r']&.start_with?('0x')
        end
        .to_return(status: 200, body: disable_response.to_json)

      result = exchange.staking_link_disable_trading_user(trading_user: trading_user)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#reserve_request_weight' do
    let(:reserve_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends reserveRequestWeight with the requested weight' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'reserveRequestWeight' &&
            action['weight'] == 10 &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash) &&
            !body.key?('vaultAddress')
        end
        .to_return(status: 200, body: reserve_response.to_json)

      result = exchange.reserve_request_weight(weight: 10)
      expect(result['status']).to eq('ok')
    end

    it 'propagates expires_after when set on the exchange' do
      exchange.expires_after = 1_700_000_000_000
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['expiresAfter'] == 1_700_000_000_000
        end
        .to_return(status: 200, body: reserve_response.to_json)

      result = exchange.reserve_request_weight(weight: 5)
      expect(result['status']).to eq('ok')
    end

    it 'includes the destination address when provided' do
      destination = '0x1234567890123456789012345678901234567890'
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          action = body['action']
          action['type'] == 'reserveRequestWeight' &&
            action['weight'] == 10 &&
            action['destination'] == destination
        end
        .to_return(status: 200, body: reserve_response.to_json)

      result = exchange.reserve_request_weight(weight: 10, destination: destination)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#c_signer_jail_self' do
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends CSignerAction with jailSelf: null' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action'] == { 'type' => 'CSignerAction', 'jailSelf' => nil } &&
            body['action'].key?('jailSelf') &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_signer_jail_self
      expect(result['status']).to eq('ok')
    end

    it 'signs as an L1 action without user-signed fields or vaultAddress' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          !body['action'].key?('signatureChainId') &&
            !body['action'].key?('hyperliquidChain') &&
            !body.key?('vaultAddress')
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_signer_jail_self
      expect(result['status']).to eq('ok')
    end

    it 'propagates expires_after when set on the exchange' do
      exchange.expires_after = 9_999_999_999_999
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['expiresAfter'] == 9_999_999_999_999 &&
            body.dig('action', 'type') == 'CSignerAction'
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_signer_jail_self
      expect(result['status']).to eq('ok')
    end
  end

  describe '#c_signer_unjail_self' do
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends CSignerAction with unjailSelf: null' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action'] == { 'type' => 'CSignerAction', 'unjailSelf' => nil } &&
            body['action'].key?('unjailSelf') &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_signer_unjail_self
      expect(result['status']).to eq('ok')
    end
  end

  describe '#validator_l1_stream' do
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends validatorL1Stream with riskFreeRate and no vaultAddress' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action'] == { 'type' => 'validatorL1Stream', 'riskFreeRate' => '0.05' } &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash) &&
            !body.key?('vaultAddress')
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.validator_l1_stream(risk_free_rate: '0.05')
      expect(result['status']).to eq('ok')
    end

    [[0.04, '0.04'], ['0.0500', '0.05'], [1, '1']].each do |input, expected|
      it "normalises risk_free_rate #{input.inspect} to #{expected.inspect}" do
        stub_request(:post, exchange_endpoint)
          .with { |req| JSON.parse(req.body).dig('action', 'riskFreeRate') == expected }
          .to_return(status: 200, body: ok_response.to_json)

        result = exchange.validator_l1_stream(risk_free_rate: input)
        expect(result['status']).to eq('ok')
      end
    end

    it 'propagates expires_after when set on the exchange' do
      exchange.expires_after = 9_999_999_999_999
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['expiresAfter'] == 9_999_999_999_999 &&
            body.dig('action', 'type') == 'validatorL1Stream'
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.validator_l1_stream(risk_free_rate: '0.04')
      expect(result['status']).to eq('ok')
    end
  end

  describe '#c_validator_register' do
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }
    let(:register_args) do
      {
        node_ip: '1.2.3.4',
        name: 'TestValidator',
        description: 'A test validator',
        delegations_disabled: true,
        commission_bps: '500',
        signer: '0xABCDEF1234567890ABCDEF1234567890ABCDEF12',
        unjailed: false,
        initial_wei: 1_000_000_000_000
      }
    end

    it 'sends the full register body with lowercased signer and integer commission' do
      expected = {
        'type' => 'CValidatorAction',
        'register' => {
          'profile' => {
            'node_ip' => { 'Ip' => '1.2.3.4' },
            'name' => 'TestValidator',
            'description' => 'A test validator',
            'delegations_disabled' => true,
            'commission_bps' => 500,
            'signer' => '0xabcdef1234567890abcdef1234567890abcdef12'
          },
          'unjailed' => false,
          'initial_wei' => 1_000_000_000_000
        }
      }
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action'] == expected &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash) &&
            !body.key?('vaultAddress')
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_validator_register(**register_args)
      expect(result['status']).to eq('ok')
    end

    it 'preserves the protocol key order' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          register = JSON.parse(req.body)['action']['register']
          register.keys == %w[profile unjailed initial_wei] &&
            register['profile'].keys == %w[node_ip name description delegations_disabled commission_bps signer]
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_validator_register(**register_args)
      expect(result['status']).to eq('ok')
    end

    it 'raises TypeError for a nil commission_bps without sending a request' do
      expect { exchange.c_validator_register(**register_args, commission_bps: nil) }.to raise_error(TypeError)
      expect(WebMock).not_to have_requested(:post, exchange_endpoint)
    end
  end

  describe '#c_validator_change_profile' do
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends every changeProfile key as null when only unjailed is given' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          change = body['action']['changeProfile']
          body['action']['type'] == 'CValidatorAction' &&
            change == { 'node_ip' => nil, 'name' => nil, 'description' => nil, 'unjailed' => true,
                        'disable_delegations' => nil, 'commission_bps' => nil, 'signer' => nil } &&
            change.keys == %w[node_ip name description unjailed disable_delegations commission_bps signer]
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_validator_change_profile(unjailed: true)
      expect(result['status']).to eq('ok')
    end

    it 'wraps node_ip, lowercases signer, and keeps disable_delegations false' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          change = JSON.parse(req.body)['action']['changeProfile']
          change == { 'node_ip' => { 'Ip' => '5.6.7.8' }, 'name' => 'Renamed', 'description' => 'Updated',
                      'unjailed' => false, 'disable_delegations' => false, 'commission_bps' => 250,
                      'signer' => '0xabcdef1234567890abcdef1234567890abcdef12' }
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_validator_change_profile(
        unjailed: false,
        node_ip: '5.6.7.8',
        name: 'Renamed',
        description: 'Updated',
        disable_delegations: false,
        commission_bps: 250,
        signer: '0xABCDEF1234567890ABCDEF1234567890ABCDEF12'
      )
      expect(result['status']).to eq('ok')
    end

    it 'omits vaultAddress and propagates expires_after' do
      exchange.expires_after = 9_999_999_999_999
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['expiresAfter'] == 9_999_999_999_999 &&
            !body.key?('vaultAddress') &&
            body.dig('action', 'type') == 'CValidatorAction'
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_validator_change_profile(unjailed: true)
      expect(result['status']).to eq('ok')
    end
  end

  describe '#c_validator_unregister' do
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    it 'sends CValidatorAction with unregister: null' do
      stub_request(:post, exchange_endpoint)
        .with do |req|
          body = JSON.parse(req.body)
          body['action'] == { 'type' => 'CValidatorAction', 'unregister' => nil } &&
            body['action'].key?('unregister') &&
            body['nonce'].is_a?(Integer) &&
            body['signature'].is_a?(Hash)
        end
        .to_return(status: 200, body: ok_response.to_json)

      result = exchange.c_validator_unregister
      expect(result['status']).to eq('ok')
    end
  end

  # Python SDK parity for validator-operator L1 actions. Fixtures captured 2026-10-01 from
  # hyperliquid-python-sdk 0.24.0 (2fdb18f95176) via
  # ~/agent-state/hyperliquid-sdk-fixtures/capture_validator_action_signatures.py. Do not edit
  # expected values without re-capturing.
  describe 'validator actions: Python SDK signature parity' do
    let(:fixture_private_key) { '0x1111111111111111111111111111111111111111111111111111111111111111' }
    let(:fixture_nonce) { 1_700_000_000_000 }
    let(:fixture_signer) do
      Hyperliquid::Signing::Signer.new(private_key: fixture_private_key, testnet: false)
    end
    let(:mainnet_client) { Hyperliquid::Client.new(base_url: Hyperliquid::Constants::MAINNET_API_URL) }
    let(:fixture_exchange) do
      described_class.new(client: mainnet_client, signer: fixture_signer,
                          info: Hyperliquid::Info.new(mainnet_client), testnet: false)
    end
    let(:testnet_fixture_exchange) do
      testnet_client = Hyperliquid::Client.new(base_url: Hyperliquid::Constants::TESTNET_API_URL)
      described_class.new(client: testnet_client,
                          signer: Hyperliquid::Signing::Signer.new(private_key: fixture_private_key, testnet: true),
                          info: Hyperliquid::Info.new(testnet_client), testnet: true)
    end
    let(:ok_response) { { 'status' => 'ok', 'response' => { 'type' => 'default' } } }

    # Stubs the exchange endpoint, pins the nonce, runs the block, returns the parsed body.
    def posted_body(exchange_under_test, base_url: Hyperliquid::Constants::MAINNET_API_URL)
      body = nil
      stub_request(:post, "#{base_url}/exchange")
        .with { |req| body = JSON.parse(req.body) }
        .to_return(status: 200, body: ok_response.to_json)
      allow(exchange_under_test).to receive(:timestamp_ms).and_return(fixture_nonce)
      yield
      body
    end

    it 'fixture signer address sanity check' do
      expect(fixture_signer.address).to eq('0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A')
    end

    it 'F1: c_signer_jail_self matches Python' do
      body = posted_body(fixture_exchange) { fixture_exchange.c_signer_jail_self }

      expect(Hyperliquid::Signing::Signer.compute_action_hash({ type: 'CSignerAction', jailSelf: nil }, fixture_nonce))
        .to eq('0x7e23c76d01bfde153fd823a7cae68ce30fa526715e47108348fc4b7b832e407c')
      expect(body['signature']).to eq(
        'r' => '0x38635f701cb33b50fbad584847661e0a07dc8d37e474e545f365832b4bc66eb1',
        's' => '0x21cac402b3d154ea4072f91512d5167448d39f4730def46b029c23b2357930ee',
        'v' => 28
      )
    end

    it 'F2: c_signer_unjail_self matches Python' do
      body = posted_body(fixture_exchange) { fixture_exchange.c_signer_unjail_self }

      expect(Hyperliquid::Signing::Signer.compute_action_hash({ type: 'CSignerAction', unjailSelf: nil },
                                                              fixture_nonce))
        .to eq('0xc613fed303750252362dada66b05b04833d4559ca0fc9454150489c569d0f077')
      expect(body['signature']).to eq(
        'r' => '0xb329b0565d78bf514952392a4657e16d1283c0570df6f784b556776cffb97999',
        's' => '0x5653180bdda309c4b5114708d2d4b041e6591655dcae74481212b070795bc122',
        'v' => 27
      )
    end

    it 'F3: c_signer_jail_self on testnet matches Python (same hash, testnet source)' do
      body = posted_body(testnet_fixture_exchange, base_url: Hyperliquid::Constants::TESTNET_API_URL) do
        testnet_fixture_exchange.c_signer_jail_self
      end

      expect(Hyperliquid::Signing::Signer.compute_action_hash({ type: 'CSignerAction', jailSelf: nil }, fixture_nonce))
        .to eq('0x7e23c76d01bfde153fd823a7cae68ce30fa526715e47108348fc4b7b832e407c')
      expect(body['signature']).to eq(
        'r' => '0x6fab3809fbf0e64be37c69f0bb95966a692a82309130cbf2068155d9d2239456',
        's' => '0x27940b36a7dd9ca5b206a40d8fcb22134b14bd8614deab5a86c208781102d374',
        'v' => 28
      )
    end

    it 'F4: c_signer_jail_self with expires_after matches Python' do
      fixture_exchange.expires_after = 1_700_000_060_000
      body = posted_body(fixture_exchange) { fixture_exchange.c_signer_jail_self }

      expect(Hyperliquid::Signing::Signer.compute_action_hash({ type: 'CSignerAction', jailSelf: nil }, fixture_nonce,
                                                              expires_after: 1_700_000_060_000))
        .to eq('0x81bbf71ae28a5450b2a52ac6fffe60f4293d8e2996b94f1084377fd9c624e63d')
      expect(body['expiresAfter']).to eq(1_700_000_060_000)
      expect(body['signature']).to eq(
        'r' => '0x265235480f198a868b3ca097917cc1a8a902096c7a225713e4c3966da8700f91',
        's' => '0x5aed84098873d2504cd1150dd4972e8a38cc7387d083c6e759cd670a55dc35c8',
        'v' => 28
      )
    end

    it 'F5: c_validator_register matches Python' do
      body = posted_body(fixture_exchange) do
        fixture_exchange.c_validator_register(
          node_ip: '1.2.3.4',
          name: 'TestValidator',
          description: 'A test validator',
          delegations_disabled: true,
          commission_bps: 500,
          signer: '0x0000000000000000000000000000000000000001',
          unjailed: false,
          initial_wei: 1_000_000_000_000
        )
      end
      action = {
        type: 'CValidatorAction',
        register: {
          profile: {
            node_ip: { Ip: '1.2.3.4' },
            name: 'TestValidator',
            description: 'A test validator',
            delegations_disabled: true,
            commission_bps: 500,
            signer: '0x0000000000000000000000000000000000000001'
          },
          unjailed: false,
          initial_wei: 1_000_000_000_000
        }
      }

      expect(Hyperliquid::Signing::Signer.compute_action_hash(action, fixture_nonce))
        .to eq('0x23490d4261f0a67161cd534501ceb5cddd4d864024135f8284dd8e19cf76ee20')
      expect(body['signature']).to eq(
        'r' => '0x2c988761b731b76b503f970ace714fef407aa84768718ea4f15f57753c77ffc4',
        's' => '0x3bb5850fb6ee1434ba20adf4167eab76b1c2bb63d10460ba9ecf492032aca935',
        'v' => 28
      )
    end

    it 'F6: c_validator_change_profile(unjailed: true) matches Python' do
      body = posted_body(fixture_exchange) { fixture_exchange.c_validator_change_profile(unjailed: true) }
      action = {
        type: 'CValidatorAction',
        changeProfile: {
          node_ip: nil, name: nil, description: nil, unjailed: true,
          disable_delegations: nil, commission_bps: nil, signer: nil
        }
      }

      expect(Hyperliquid::Signing::Signer.compute_action_hash(action, fixture_nonce))
        .to eq('0x9e82e281cd117741a7460587acfe417c1979675c1e4d7c160f354d1412a381f7')
      expect(body['signature']).to eq(
        'r' => '0xc27ad22c714d5d3d2163d724e2a594bc4104d502faa14c1440e91fa094327c78',
        's' => '0x582643edd1702f7dd797e0e161316d9e2a72c4edeb571d74305320e2f8664581',
        'v' => 28
      )
    end

    it 'F7: c_validator_change_profile with every field matches Python' do
      body = posted_body(fixture_exchange) do
        fixture_exchange.c_validator_change_profile(
          node_ip: '5.6.7.8',
          name: 'Renamed',
          description: 'Updated description',
          unjailed: false,
          disable_delegations: false,
          commission_bps: 250,
          signer: '0x0000000000000000000000000000000000000002'
        )
      end
      action = {
        type: 'CValidatorAction',
        changeProfile: {
          node_ip: { Ip: '5.6.7.8' },
          name: 'Renamed',
          description: 'Updated description',
          unjailed: false,
          disable_delegations: false,
          commission_bps: 250,
          signer: '0x0000000000000000000000000000000000000002'
        }
      }

      expect(Hyperliquid::Signing::Signer.compute_action_hash(action, fixture_nonce))
        .to eq('0x687692ddcfcdfbc7d6b39869cbcb2496f7e15d46b9b94d00a3a07674fdb78884')
      expect(body['signature']).to eq(
        'r' => '0x9daa6980f55bf354b3cd59b3bdff6e92c9b8214de92a1b3d354e78bcd2e71ebd',
        's' => '0x3ecc2898ac4282048782421e6280d23a9f542bfa801e04b8967ec36285538467',
        'v' => 28
      )
    end

    it 'F8: c_validator_unregister matches Python' do
      body = posted_body(fixture_exchange) { fixture_exchange.c_validator_unregister }

      expect(Hyperliquid::Signing::Signer.compute_action_hash({ type: 'CValidatorAction', unregister: nil },
                                                              fixture_nonce))
        .to eq('0xbf75857de4da4a5ed6204cb335f3296fb39cc2dbe99173ec405d1e8dde50d0b9')
      expect(body['signature']).to eq(
        'r' => '0x1903aac6497bcc35e8613971842c085665c04fe94d64cafb7b8293db39034de4',
        's' => '0x041b7ff234441bba63fa5eb994c2f78499c475e5cb40126607244942adc3b798',
        'v' => 27
      )
    end

    ['0.05', 0.05, '0.0500'].each do |rate|
      it "F9: validator_l1_stream(risk_free_rate: #{rate.inspect}) matches Python sign_l1_action" do
        body = posted_body(fixture_exchange) { fixture_exchange.validator_l1_stream(risk_free_rate: rate) }

        expect(Hyperliquid::Signing::Signer.compute_action_hash({ type: 'validatorL1Stream', riskFreeRate: '0.05' },
                                                                fixture_nonce))
          .to eq('0x519b23e287b6172a38a34bb9cea9c13d1cc80955e5e857b2856f26953411a0c5')
        expect(body['action']).to eq('type' => 'validatorL1Stream', 'riskFreeRate' => '0.05')
        expect(body['signature']).to eq(
          'r' => '0x3105c52c6f6d8d03ff7af1fb99129d2cf5d4a9d14524e1e025a74abcc8494ba3',
          's' => '0x025f23dddac180e66973b6cba6a1ca8be9e904b631ddb67a9137afec45364b7e',
          'v' => 28
        )
      end
    end
  end
end
