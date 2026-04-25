# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Hyperliquid::Info do
  let(:base_url) { Hyperliquid::Constants::TESTNET_API_URL }
  let(:info_endpoint) { "#{base_url}/info" }
  let(:client) { Hyperliquid::Client.new(base_url: base_url) }
  let(:info) { described_class.new(client) }

  # ============================
  # Info
  # ============================

  describe '#all_mids' do
    it 'requests all market mid prices' do
      expected_response = { 'BTC' => '50000', 'ETH' => '3000' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'allMids' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.all_mids
      expect(result).to eq(expected_response)
    end

    it 'supports optional dex parameter for HIP-3 perp dexs' do
      expected_response = { 'xyz:GOLD' => '2500', 'xyz:SILVER' => '30' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'allMids', dex: 'xyz' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.all_mids(dex: 'xyz')
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

    it 'supports optional dex parameter' do
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'openOrders', user: user_address, dex: 'builder-dex' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.open_orders(user_address, dex: 'builder-dex')
      expect(result).to eq(expected_response)
    end
  end

  describe '#frontend_open_orders' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's frontend open orders" do
      expected_response = [
        { 'coin' => 'BTC', 'isTrigger' => false, 'isPositionTpsl' => false }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'frontendOpenOrders', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.frontend_open_orders(user_address)
      expect(result).to eq(expected_response)
    end

    it 'supports optional dex parameter' do
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'frontendOpenOrders', user: user_address, dex: 'builder-dex' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.frontend_open_orders(user_address, dex: 'builder-dex')
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

  describe '#user_fills_by_time' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }
    let(:start_time) { 1_700_000_000_000 }

    it "requests user's fills by time without end_time" do
      expected_response = [
        { 'coin' => 'ETH', 'px' => '3000', 'sz' => '0.5', 'time' => start_time }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userFillsByTime', user: user_address, startTime: start_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_fills_by_time(user_address, start_time)
      expect(result).to eq(expected_response)
    end

    it "requests user's fills by time with end_time" do
      end_time = start_time + 86_400_000
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userFillsByTime', user: user_address, startTime: start_time, endTime: end_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_fills_by_time(user_address, start_time, end_time)
      expect(result).to eq(expected_response)
    end

    it 'supports aggregate_by_time parameter' do
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userFillsByTime', user: user_address, startTime: start_time,
                      aggregateByTime: true }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_fills_by_time(user_address, start_time, aggregate_by_time: true)
      expect(result).to eq(expected_response)
    end

    it 'supports reversed parameter' do
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userFillsByTime', user: user_address, startTime: start_time,
                      reversed: true }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_fills_by_time(user_address, start_time, reversed: true)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_rate_limit' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's rate limit" do
      expected_response = { 'nRequestsUsed' => 100, 'nRequestsCap' => 10_000 }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userRateLimit', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_rate_limit(user_address)
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

  describe '#order_status_by_cloid' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }
    let(:cloid) { 'client-order-id-123' }

    it 'requests order status by cloid' do
      expected_response = { 'status' => 'cancelled', 'order' => { 'cloid' => cloid } }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'orderStatus', user: user_address, cloid: cloid }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.order_status_by_cloid(user_address, cloid)
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

  describe '#recent_trades' do
    let(:coin) { 'BTC' }

    it 'requests recent trades for a coin' do
      expected_response = [
        {
          'coin' => 'BTC',
          'side' => 'B',
          'px' => '50000',
          'sz' => '0.5',
          'time' => 1_700_000_000_000,
          'hash' => '0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
          'tid' => 12_345,
          'users' => %w[
            0x1111111111111111111111111111111111111111
            0x2222222222222222222222222222222222222222
          ]
        }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'recentTrades', coin: coin }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.recent_trades(coin)
      expect(result).to eq(expected_response)
    end
  end

  describe '#block_details' do
    let(:height) { 12_345 }

    it 'requests block details by height' do
      expected_response = {
        'type' => 'blockDetails',
        'blockDetails' => {
          'blockTime' => 1_700_000_000_000,
          'hash' => '0xabcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
          'height' => height,
          'numTxs' => 2,
          'proposer' => '0x3333333333333333333333333333333333333333',
          'txs' => []
        }
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'blockDetails', height: height }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.block_details(height)
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

  describe '#max_builder_fee' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }
    let(:builder_address) { '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd' }

    it 'checks builder fee approval' do
      expected_response = { 'approved' => true }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'maxBuilderFee', user: user_address, builder: builder_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.max_builder_fee(user_address, builder_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#approved_builders' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it 'requests approved builder addresses for a user' do
      expected_response = %w[
        0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'approvedBuilders', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.approved_builders(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#historical_orders' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's historical orders without time range" do
      expected_response = [
        { 'oid' => 123, 'coin' => 'BTC', 'side' => 'A' }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'historicalOrders', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.historical_orders(user_address)
      expect(result).to eq(expected_response)
    end

    it "requests user's historical orders with time range" do
      start_time = 1_700_000_000_000
      end_time = start_time + 86_400_000
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'historicalOrders', user: user_address, startTime: start_time, endTime: end_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.historical_orders(user_address, start_time, end_time)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_twap_slice_fills' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's TWAP slice fills without time range" do
      expected_response = [
        { 'sliceId' => 1, 'coin' => 'ETH', 'sz' => '1.0' }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userTwapSliceFills', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_twap_slice_fills(user_address)
      expect(result).to eq(expected_response)
    end

    it "requests user's TWAP slice fills with time range" do
      start_time = 1_700_000_000_000
      end_time = start_time + 86_400_000
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userTwapSliceFills', user: user_address, startTime: start_time,
                      endTime: end_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_twap_slice_fills(user_address, start_time, end_time)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_twap_slice_fills_by_time' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }
    let(:start_time) { 1_700_000_000_000 }

    it "requests user's TWAP slice fills with start_time only" do
      expected_response = [
        { 'sliceId' => 1, 'coin' => 'ETH', 'sz' => '1.0' }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userTwapSliceFillsByTime', user: user_address,
                      startTime: start_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_twap_slice_fills_by_time(user_address, start_time)
      expect(result).to eq(expected_response)
    end

    it 'supports end_time and aggregate_by_time kwarg' do
      end_time = start_time + 86_400_000
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userTwapSliceFillsByTime', user: user_address,
                      startTime: start_time, endTime: end_time,
                      aggregateByTime: true }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_twap_slice_fills_by_time(user_address, start_time, end_time,
                                                  aggregate_by_time: true)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_subaccounts' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's subaccounts" do
      expected_response = ['0x1111111111111111111111111111111111111111']

      stub_request(:post, info_endpoint)
        .with(body: { type: 'subaccounts', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_subaccounts(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#sub_accounts2' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests a user's V2 sub-accounts" do
      expected_response = [
        {
          'name' => 'sub1',
          'subAccountUser' => '0x2222222222222222222222222222222222222222',
          'master' => user_address,
          'dexToClearinghouseState' => [
            ['', { 'marginSummary' => { 'accountValue' => '100' } }]
          ],
          'spotState' => { 'balances' => [] }
        }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'subAccounts2', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.sub_accounts2(user_address)
      expect(result).to eq(expected_response)
    end

    it 'returns nil for users with no sub-accounts' do
      stub_request(:post, info_endpoint)
        .with(body: { type: 'subAccounts2', user: user_address }.to_json)
        .to_return(status: 200, body: 'null')

      result = info.sub_accounts2(user_address)
      expect(result).to be_nil
    end
  end

  describe '#vault_details' do
    let(:vault_address) { '0x1111111111111111111111111111111111111111' }

    it 'requests vault details without user' do
      expected_response = { 'vaultAddress' => vault_address, 'totalDeposits' => '1000.0' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'vaultDetails', vaultAddress: vault_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.vault_details(vault_address)
      expect(result).to eq(expected_response)
    end

    it 'requests vault details with user' do
      user_address = '0x1234567890123456789012345678901234567890'
      expected_response = { 'vaultAddress' => vault_address, 'user' => user_address }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'vaultDetails', vaultAddress: vault_address, user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.vault_details(vault_address, user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_vault_equities' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's vault deposits" do
      expected_response = [
        { 'vaultAddress' => '0x1111111111111111111111111111111111111111', 'equity' => '123.45' }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userVaultEquities', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_vault_equities(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#vault_summaries' do
    it 'requests vaults less than 2 hours old' do
      expected_response = [
        {
          'name' => 'Test Vault',
          'vaultAddress' => '0x2222222222222222222222222222222222222222',
          'leader' => '0x3333333333333333333333333333333333333333',
          'tvl' => '10000.00',
          'isClosed' => false,
          'relationship' => { 'type' => 'normal' },
          'createTimeMillis' => 1_700_000_000_000
        }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'vaultSummaries' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.vault_summaries
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_role' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's role" do
      expected_response = { 'role' => 'tradingUser' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userRole', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_role(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#portfolio' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's portfolio" do
      expected_response = [
        ['day', { 'vlm' => '0.0', 'pnlHistory' => [] }]
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'portfolio', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.portfolio(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#referral' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's referral info" do
      expected_response = { 'referredBy' => { 'referrer' => user_address } }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'referral', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.referral(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_fees' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's fees" do
      expected_response = { 'userAddRate' => '0.0001', 'userCrossRate' => '0.0003' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userFees', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_fees(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#delegations' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's staking delegations" do
      expected_response = [
        { 'validator' => '0x5ac99df645f3414876c816caa18b2d234024b487', 'amount' => '100.0' }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'delegations', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.delegations(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#delegator_summary' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's staking summary" do
      expected_response = { 'delegated' => '100.0', 'undelegated' => '0.0' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'delegatorSummary', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.delegator_summary(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#delegator_history' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's staking history" do
      expected_response = [
        { 'time' => 1_736_726_400_073, 'delta' => { 'delegate' => { 'amount' => '10.0' } } }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'delegatorHistory', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.delegator_history(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#delegator_rewards' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's staking rewards" do
      expected_response = [
        { 'time' => 1_736_726_400_073, 'source' => 'delegation', 'totalAmount' => '0.123' }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'delegatorRewards', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.delegator_rewards(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#extra_agents' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's authorized agent addresses" do
      expected_response = [
        { 'address' => '0xabcdefabcdefabcdefabcdefabcdefabcdefabcd', 'name' => 'agent1' }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'extraAgents', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.extra_agents(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_to_multi_sig_signers' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it 'requests multi-sig signer mappings' do
      expected_response = {
        'signers' => %w[0xaaaa 0xbbbb],
        'threshold' => 2
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userToMultiSigSigners', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_to_multi_sig_signers(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_dex_abstraction' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's dex abstraction config" do
      expected_response = { 'enabled' => true }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userDexAbstraction', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_dex_abstraction(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_abstraction' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests user's abstraction state" do
      expected_response = 'unifiedAccount'

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userAbstraction', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_abstraction(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#pre_transfer_check' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }
    let(:source_address) { '0x2222222222222222222222222222222222222222' }

    it 'requests pre-transfer user existence check' do
      expected_response = {
        'fee' => '1.0',
        'isSanctioned' => false,
        'userExists' => true,
        'userHasSentTx' => true
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'preTransferCheck', user: user_address, source: source_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.pre_transfer_check(user_address, source_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#vip?' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "returns a user's VIP status" do
      stub_request(:post, info_endpoint)
        .with(body: { type: 'isVip', user: user_address }.to_json)
        .to_return(status: 200, body: 'true')

      result = info.vip?(user_address)
      expect(result).to be(true)
    end

    it 'returns nil for unknown users' do
      stub_request(:post, info_endpoint)
        .with(body: { type: 'isVip', user: user_address }.to_json)
        .to_return(status: 200, body: 'null')

      result = info.vip?(user_address)
      expect(result).to be_nil
    end
  end

  describe '#liquidatable' do
    it 'requests the liquidatable users list' do
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'liquidatable' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.liquidatable
      expect(result).to eq(expected_response)
    end
  end

  describe '#validator_summaries' do
    it 'requests validator performance summaries' do
      expected_response = [
        {
          'validator' => '0x1111111111111111111111111111111111111111',
          'signer' => '0x2222222222222222222222222222222222222222',
          'name' => 'Test Validator',
          'description' => 'A test validator',
          'nRecentBlocks' => 100,
          'stake' => 1_000_000,
          'isJailed' => false,
          'unjailableAfter' => nil,
          'isActive' => true,
          'commission' => '0.05',
          'stats' => [
            ['day', { 'uptimeFraction' => '0.99', 'predictedApr' => '0.08', 'nSamples' => 144 }],
            ['week', { 'uptimeFraction' => '0.98', 'predictedApr' => '0.08', 'nSamples' => 1008 }],
            ['month', { 'uptimeFraction' => '0.97', 'predictedApr' => '0.08', 'nSamples' => 4320 }]
          ]
        }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'validatorSummaries' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.validator_summaries
      expect(result).to eq(expected_response)
    end
  end

  describe '#exchange_status' do
    it 'requests exchange system status information' do
      expected_response = { 'time' => 1_700_000_000_000, 'specialStatuses' => nil }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'exchangeStatus' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.exchange_status
      expect(result).to eq(expected_response)
    end
  end

  describe '#max_market_order_ntls' do
    it 'requests maximum market order notionals per asset' do
      expected_response = [[1_000_000, 'BTC'], [500_000, 'ETH']]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'maxMarketOrderNtls' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.max_market_order_ntls
      expect(result).to eq(expected_response)
    end
  end

  describe '#validator_l1_votes' do
    it 'requests L1 governance votes cast by validators' do
      expected_response = [
        {
          'expireTime' => 1_700_000_000_000,
          'action' => { 'D' => 'some-proposal-id' },
          'votes' => %w[
            0x1111111111111111111111111111111111111111
            0x2222222222222222222222222222222222222222
          ]
        },
        {
          'expireTime' => 1_700_000_060_000,
          'action' => { 'C' => %w[option-a option-b] },
          'votes' => ['0x3333333333333333333333333333333333333333']
        }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'validatorL1Votes' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.validator_l1_votes
      expect(result).to eq(expected_response)
    end
  end

  describe '#gossip_root_ips' do
    it 'requests gossip root IPs' do
      expected_response = ['10.0.0.1', '192.168.1.100', '203.0.113.42']

      stub_request(:post, info_endpoint)
        .with(body: { type: 'gossipRootIps' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.gossip_root_ips
      expect(result).to eq(expected_response)
    end
  end

  describe '#legal_check' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests a user's legal verification status" do
      expected_response = {
        'ipAllowed' => true,
        'acceptedTerms' => true,
        'userAllowed' => true
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'legalCheck', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.legal_check(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#margin_table' do
    it 'requests the margin table for the given id' do
      expected_response = {
        'description' => 'Default',
        'marginTiers' => [
          { 'lowerBound' => '0', 'maxLeverage' => 50 },
          { 'lowerBound' => '100000', 'maxLeverage' => 25 }
        ]
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'marginTable', id: 1 }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.margin_table(1)
      expect(result).to eq(expected_response)
    end
  end

  describe '#leading_vaults' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it 'requests the vaults a user is leading' do
      expected_response = [
        { 'address' => '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'name' => 'Vault A' },
        { 'address' => '0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'name' => 'Vault B' }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'leadingVaults', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.leading_vaults(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#twap_history' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it "requests a user's TWAP order history" do
      expected_response = [
        {
          'time' => 1_700_000_000,
          'state' => {
            'coin' => 'BTC',
            'user' => user_address,
            'side' => 'B',
            'sz' => '0.1',
            'executedSz' => '0.1',
            'executedNtl' => '5000',
            'minutes' => 30,
            'reduceOnly' => false,
            'randomize' => false,
            'timestamp' => 1_700_000_000_000
          },
          'status' => { 'status' => 'finished' },
          'twapId' => 42
        },
        {
          'time' => 1_700_000_100,
          'state' => {
            'coin' => 'ETH',
            'user' => user_address,
            'side' => 'A',
            'sz' => '1.0',
            'executedSz' => '0.2',
            'executedNtl' => '400',
            'minutes' => 15,
            'reduceOnly' => true,
            'randomize' => true,
            'timestamp' => 1_700_000_100_000
          },
          'status' => { 'status' => 'error', 'description' => 'oracle bounce' }
        }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'twapHistory', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.twap_history(user_address)
      expect(result).to eq(expected_response)
    end
  end

  describe '#web_data2' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }

    it 'requests comprehensive user and market data' do
      expected_response = {
        'clearinghouseState' => { 'marginSummary' => { 'accountValue' => '100' } },
        'leadingVaults' => [],
        'totalVaultEquity' => '0',
        'openOrders' => [],
        'agentAddress' => nil,
        'agentValidUntil' => nil,
        'cumLedger' => '0',
        'meta' => { 'universe' => [] },
        'assetCtxs' => [],
        'serverTime' => 1_700_000_000_000,
        'isVault' => false,
        'user' => user_address,
        'twapStates' => [],
        'spotAssetCtxs' => []
      }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'webData2', user: user_address }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.web_data2(user_address)
      expect(result).to eq(expected_response)
    end
  end

  # ============================
  # Info: Perpetuals
  # ============================

  describe '#perp_dexs' do
    it 'requests all perp dexs' do
      expected_response = [nil, { 'name' => 'test', 'full_name' => 'test dex' }]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'perpDexs' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.perp_dexs
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

    it 'supports optional dex parameter' do
      expected_response = { 'universe' => [] }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'meta', dex: 'builder-dex' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.meta(dex: 'builder-dex')
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

  describe '#all_perp_metas' do
    it 'requests trading metadata for all perp dexs' do
      expected_response = [
        { 'universe' => [{ 'name' => 'BTC', 'szDecimals' => 4 }] },
        { 'universe' => [{ 'name' => 'FOO', 'szDecimals' => 2 }] }
      ]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'allPerpMetas' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.all_perp_metas
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

    it 'supports optional dex parameter' do
      expected_response = { 'time' => 1_708_622_398_623 }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'clearinghouseState', user: user_address, dex: 'builder-dex' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_state(user_address, dex: 'builder-dex')
      expect(result).to eq(expected_response)
    end
  end

  describe '#predicted_fundings' do
    it 'requests predicted funding rates' do
      expected_response = [['AVAX', [['HlPerp', { 'fundingRate' => '0.0000125' }]]]]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'predictedFundings' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.predicted_fundings
      expect(result).to eq(expected_response)
    end
  end

  describe '#perps_at_open_interest_cap' do
    it 'requests perps at open interest caps' do
      expected_response = %w[BADGER CANTO]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'perpsAtOpenInterestCap' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.perps_at_open_interest_cap
      expect(result).to eq(expected_response)
    end
  end

  describe '#perp_deploy_auction_status' do
    it 'requests perp deploy auction status' do
      expected_response = { 'startTimeSeconds' => 1_747_656_000, 'durationSeconds' => 111_600, 'startGas' => '500.0' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'perpDeployAuctionStatus' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.perp_deploy_auction_status
      expect(result).to eq(expected_response)
    end
  end

  describe '#active_asset_data' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }
    let(:coin) { 'APT' }

    it "requests user's active asset data" do
      expected_response = { 'user' => user_address, 'coin' => coin, 'leverage' => { 'type' => 'cross', 'value' => 3 } }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'activeAssetData', user: user_address, coin: coin }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.active_asset_data(user_address, coin)
      expect(result).to eq(expected_response)
    end
  end

  describe '#perp_dex_limits' do
    it 'requests builder-deployed perp market limits for a dex' do
      expected_response = { 'totalOiCap' => '10000000.0' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'perpDexLimits', dex: 'builder-dex' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.perp_dex_limits('builder-dex')
      expect(result).to eq(expected_response)
    end
  end

  describe '#perp_dex_status' do
    it 'requests perp DEX status for a builder-deployed dex' do
      expected_response = { 'totalNetDeposit' => '12345.67' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'perpDexStatus', dex: 'builder-dex' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.perp_dex_status('builder-dex')
      expect(result).to eq(expected_response)
    end

    it 'accepts an empty string for the first perp dex' do
      expected_response = { 'totalNetDeposit' => '0.0' }

      stub_request(:post, info_endpoint)
        .with(body: { type: 'perpDexStatus', dex: '' }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.perp_dex_status('')
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_funding' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }
    let(:start_time) { 1_681_222_254_710 }

    it "requests user's funding history without end_time" do
      expected_response = [{ 'delta' => { 'coin' => 'ETH', 'type' => 'funding' } }]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userFunding', user: user_address, startTime: start_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_funding(user_address, start_time)
      expect(result).to eq(expected_response)
    end

    it "requests user's funding history with end_time" do
      end_time = start_time + 86_400_000
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userFunding', user: user_address, startTime: start_time, endTime: end_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_funding(user_address, start_time, end_time)
      expect(result).to eq(expected_response)
    end
  end

  describe '#user_non_funding_ledger_updates' do
    let(:user_address) { '0x1234567890123456789012345678901234567890' }
    let(:start_time) { 1_681_222_254_710 }

    it "requests user's non-funding ledger updates without end_time" do
      expected_response = [{ 'delta' => { 'type' => 'deposit', 'usdc' => '100.0' } }]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'userNonFundingLedgerUpdates', user: user_address, startTime: start_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_non_funding_ledger_updates(user_address, start_time)
      expect(result).to eq(expected_response)
    end

    it "requests user's non-funding ledger updates with end_time" do
      end_time = start_time + 86_400_000
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(
          body: {
            type: 'userNonFundingLedgerUpdates',
            user: user_address,
            startTime: start_time,
            endTime: end_time
          }.to_json
        )
        .to_return(status: 200, body: expected_response.to_json)

      result = info.user_non_funding_ledger_updates(user_address, start_time, end_time)
      expect(result).to eq(expected_response)
    end
  end

  describe '#funding_history' do
    let(:coin) { 'ETH' }
    let(:start_time) { 1_683_849_600_076 }

    it 'requests historical funding rates without end_time' do
      expected_response = [{ 'coin' => coin, 'fundingRate' => '0.0001', 'time' => start_time }]

      stub_request(:post, info_endpoint)
        .with(body: { type: 'fundingHistory', coin: coin, startTime: start_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.funding_history(coin, start_time)
      expect(result).to eq(expected_response)
    end

    it 'requests historical funding rates with end_time' do
      end_time = start_time + 3_600_000
      expected_response = []

      stub_request(:post, info_endpoint)
        .with(body: { type: 'fundingHistory', coin: coin, startTime: start_time, endTime: end_time }.to_json)
        .to_return(status: 200, body: expected_response.to_json)

      result = info.funding_history(coin, start_time, end_time)
      expect(result).to eq(expected_response)
    end
  end

  # ============================
  # Info: Spot
  # ============================

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
        'gasAuction' => { 'startTimeSeconds' => 1_733_929_200, 'durationSeconds' => 111_600,
                          'startGas' => '181305.90046' }
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
