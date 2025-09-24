# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Info do
  let(:base_url) { Hyperliquid::Constants::TESTNET_API_URL }
  let(:info_endpoint) { "#{base_url}/info" }
  let(:client) { Hyperliquid::Client.new(base_url: base_url) }
  let(:info) { described_class.new(client) }

  describe '#all_mids' do
    it 'requests all market mid prices' do
      expected_response = { 'BTC' => '50000', 'ETH' => '3000' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'allMids' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.all_mids
      expect(result).to eq(expected_response)
    end
  end

  describe '#open_orders' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's open orders" do
      expected_response = [
        { 'coin' => 'BTC', 'sz' => '0.1', 'px' => '50000', 'side' => 'A' }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'openOrders', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.open_orders(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_fills' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's fill history" do
      expected_response = [
        { 'coin' => 'BTC', 'sz' => '0.05', 'px' => '49000', 'side' => 'A', 'time' => 1_234_567_890 }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userFills', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_fills(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#order_status' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }
    let(:order_id) { 12_345 }

    it 'requests order status' do
      expected_response = { 'status' => 'filled', 'sz' => '0.1', 'px' => '50000' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'orderStatus', user: user_address, oid: order_id }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.order_status(user_address, order_id)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_state' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's trading state" do
      expected_response = {
        'assetPositions' => [
          { 'position' => { 'coin' => 'BTC', 'sz' => '0.1' } }
        ],
        'marginSummary' => { 'accountValue' => '10000' }
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'clearinghouseState', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_state(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#meta' do
    it 'requests asset metadata' do
      expected_response = {
        'universe' => [
          { 'name' => 'BTC', 'szDecimals' => 4 }
        ]
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'meta' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.meta
      expect(result).to eq(expected_response)
    end
  end

  describe '#meta_and_asset_ctxs' do
    it 'requests extended asset metadata' do
      expected_response = {
        'universe' => [{ 'name' => 'BTC', 'szDecimals' => 4 }],
        'assetCtxs' => [{ 'funding' => '0.001', 'openInterest' => '1000000' }]
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'metaAndAssetCtxs' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.meta_and_asset_ctxs
      expect(result).to eq(expected_response)
    end
  end

  describe '#l2_book' do
    let(:coin) { 'BTC' }

    it 'requests L2 order book' do
      expected_response = {
        'coin' => 'BTC',
        'levels' => [
          [{ 'px' => '50000', 'sz' => '1.5' }], # asks
          [{ 'px' => '49000', 'sz' => '2.0' }]  # bids
        ],
        'time' => 1_234_567_890
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'l2Book', coin: coin }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.l2_book(coin)
      expect(result).to eq(expected_response)
    end
  end

  describe '#candles_snapshot' do
    let(:coin) { 'BTC' }
    let(:interval) { '1h' }
    let(:start_time) { 1_609_459_200_000 } # 2021-01-01 00:00:00 UTC in milliseconds
    let(:end_time) { 1_609_462_800_000 }   # 2021-01-01 01:00:00 UTC in milliseconds

    it 'requests candlestick data' do
      expected_response = [
        {
          't' => 1_609_459_200_000,
          'T' => 1_609_462_800_000,
          's' => 'BTC',
          'i' => '1h',
          'o' => '50000',
          'c' => '51000',
          'h' => '51500',
          'l' => '49500',
          'v' => '100',
          'n' => 1000
        }
      ]

      stub_request(:post, info_endpoint)
        .with(body: {
          type: 'candleSnapshot',
          req: {
            coin: coin,
            interval: interval,
            startTime: start_time,
            endTime: end_time
          }
        }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.candles_snapshot(coin, interval, start_time, end_time)
      expect(result).to eq(expected_response)
    end
  end

  # Spot-specific endpoints
  describe '#spot_meta' do
    it 'requests spot metadata' do
      expected_response = {
        'tokens' => [
          { 'name' => 'USDC', 'szDecimals' => 8, 'weiDecimals' => 8, 'index' => 0 }
        ],
        'universe' => [
          { 'name' => 'PURR/USDC', 'tokens' => [1, 0], 'index' => 0, 'isCanonical' => true }
        ]
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'spotMeta' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.spot_meta
      expect(result).to eq(expected_response)
    end
  end

  describe '#spot_meta_and_asset_ctxs' do
    it 'requests spot metadata and asset contexts' do
      expected_response = [
        {
          'tokens' => [
            { 'name' => 'USDC', 'szDecimals' => 8, 'weiDecimals' => 8, 'index' => 0 }
          ],
          'universe' => [
            { 'name' => 'PURR/USDC', 'tokens' => [1, 0], 'index' => 0, 'isCanonical' => true }
          ]
        },
        [
          { 'dayNtlVlm' => '8906.0', 'markPx' => '0.14', 'midPx' => '0.209265', 'prevDayPx' => '0.20432' }
        ]
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'spotMetaAndAssetCtxs' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.spot_meta_and_asset_ctxs
      expect(result).to eq(expected_response)
    end
  end

  describe '#spot_balances' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's spot balances" do
      expected_response = {
        'balances' => [
          { 'coin' => 'USDC', 'token' => 0, 'hold' => '0.0', 'total' => '14.625485', 'entryNtl' => '0.0' },
          { 'coin' => 'PURR', 'token' => 1, 'hold' => '0', 'total' => '2000', 'entryNtl' => '1234.56' }
        ]
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'spotClearinghouseState', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.spot_balances(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#spot_deploy_state' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it 'requests spot deploy auction state' do
      expected_response = {
        'states' => [
          {
            'token' => 150,
            'spec' => { 'name' => 'HYPE', 'szDecimals' => 2, 'weiDecimals' => 8 },
            'fullName' => 'Hyperliquid',
            'spots' => [107]
          }
        ],
        'gasAuction' => { 'startTimeSeconds' => 1_733_929_200, 'durationSeconds' => 111_600, 'startGas' => '181305.90046' }
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'spotDeployState', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.spot_deploy_state(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#spot_pair_deploy_auction_status' do
    it 'requests spot pair deploy auction status' do
      expected_response = {
        'startTimeSeconds' => 1_755_468_000,
        'durationSeconds' => 111_600,
        'startGas' => '500.0',
        'currentGas' => '500.0',
        'endGas' => nil
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'spotPairDeployAuctionStatus' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.spot_pair_deploy_auction_status
      expect(result).to eq(expected_response)
    end
  end

  describe '#token_details' do
    let(:token_id) { '0x00000000000000000000000000000000' }

    it 'requests token details by token id' do
      expected_response = {
        'name' => 'TEST',
        'maxSupply' => '1852229076.12716007',
        'totalSupply' => '851681534.05516005',
        'circulatingSupply' => '851681534.05516005',
        'szDecimals' => 0,
        'weiDecimals' => 5,
        'midPx' => '3.2049'
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'tokenDetails', tokenId: token_id }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.token_details(token_id)
      expect(result).to eq(expected_response)
    end
  end
end
