# frozen_string_literal: true

require 'spec_helper'

# Byte-level golden for every L1 Exchange method the Python SDK also implements. Fixture written by
# tools/parity/capture_l1_wire_golden.py (run via tools/parity/regenerate.sh; `rake parity:check` diffs it).
# The posted action is re-serialised from an order-preserving parse and compared as a string, so a key-order
# change (different msgpack bytes, different signature) fails here even when every field value is right.
# Python's sub_account_transfer / vault_usd_transfer take micro-USD; the Ruby methods take USD (scaled by 1e6).
RSpec.describe Hyperliquid::Exchange, 'L1 wire golden (Python SDK parity)' do
  fixture = JSON.parse(File.read(File.expand_path('../fixtures/parity/l1_wire_golden.json', __dir__)))

  vault = '0x1719884EB866cb12b2287399b15f7db5e7d775ea'
  sub_account = '0x1d9470d4b963f552e6f671a81619d395877bf409'
  builder = '0xAbCdEf0123456789aBcDeF0123456789AbCdEf01'
  cloid_a = Hyperliquid::Cloid.from_str('0x0000000000000000000000000000abcd')
  cloid_b = Hyperliquid::Cloid.from_str('0x00000000000000000000000000001234')
  purr = 'PURR:0xc4bf3f870c0e9465323c0b6ed28096c2'
  alo = { limit: { tif: 'Alo' } }
  ioc = { limit: { tif: 'Ioc' } }

  # name => ->(exchange, vault_address_from_fixture) { Ruby call equivalent to the Python capture }
  calls = {
    'order_limit_gtc_mainnet' => ->(ex, _) { ex.order(coin: 'ETH', is_buy: true, size: 0.0147, limit_px: 1670.1) },
    'order_limit_gtc_testnet' => ->(ex, _) { ex.order(coin: 'ETH', is_buy: true, size: 0.0147, limit_px: 1670.1) },
    'order_limit_alo_reduce_only' => lambda { |ex, _|
      ex.order(coin: 'BTC', is_buy: false, size: 0.001, limit_px: 95_000.5, order_type: alo, reduce_only: true)
    },
    'order_limit_ioc_spot' => lambda { |ex, _|
      ex.order(coin: 'PURR/USDC', is_buy: true, size: 100, limit_px: 0.12345, order_type: ioc)
    },
    'order_trigger_tp_market' => lambda { |ex, _|
      ex.order(coin: 'ETH', is_buy: false, size: 0.5, limit_px: 3500, reduce_only: true,
               order_type: { trigger: { trigger_px: 3600, is_market: true, tpsl: 'tp' } })
    },
    'order_trigger_sl_limit' => lambda { |ex, _|
      ex.order(coin: 'SOL', is_buy: false, size: 1.25, limit_px: 150.1, reduce_only: true,
               order_type: { trigger: { trigger_px: 150.25, is_market: false, tpsl: 'sl' } })
    },
    'order_with_cloid' => ->(ex, _) { ex.order(coin: 'ETH', is_buy: true, size: 0.1, limit_px: 2000, cloid: cloid_a) },
    'order_with_builder' => lambda { |ex, _|
      ex.order(coin: 'ETH', is_buy: true, size: 0.1, limit_px: 2000, builder: { b: builder, f: 10 })
    },
    'order_vault_mainnet' => lambda { |ex, v|
      ex.order(coin: 'DOGE', is_buy: true, size: 100, limit_px: 0.12, vault_address: v)
    },
    'order_expires_testnet' => ->(ex, _) { ex.order(coin: 'ETH', is_buy: true, size: 0.1, limit_px: 2000) },
    'order_vault_expires_testnet' => lambda { |ex, v|
      ex.order(coin: 'BTC', is_buy: true, size: 0.002, limit_px: 90_000, order_type: alo, vault_address: v)
    },
    'bulk_orders_normal_tpsl' => lambda { |ex, _|
      ex.bulk_orders(
        orders: [
          { coin: 'ETH', is_buy: true, size: 0.2, limit_px: 3000, cloid: cloid_a },
          { coin: 'ETH', is_buy: false, size: 0.2, limit_px: 2900, reduce_only: true,
            order_type: { trigger: { trigger_px: 2950, is_market: true, tpsl: 'sl' } } }
        ],
        grouping: 'normalTpsl'
      )
    },
    'bulk_orders_builder_mainnet' => lambda { |ex, _|
      ex.bulk_orders(
        orders: [
          { coin: 'BTC', is_buy: true, size: 0.01, limit_px: 95_000, order_type: ioc },
          { coin: '@1', is_buy: false, size: 12.5, limit_px: 0.0015 }
        ],
        builder: { b: builder, f: 25 }
      )
    },
    'market_open_perp_buy' => ->(ex, _) { ex.market_order(coin: 'ETH', is_buy: true, size: 0.1) },
    'market_open_perp_sell' => ->(ex, _) { ex.market_order(coin: 'BTC', is_buy: false, size: 0.01, slippage: 0.01) },
    'market_open_spot_buy' => ->(ex, _) { ex.market_order(coin: '@1', is_buy: true, size: 100) },
    'market_close_short' => ->(ex, _) { ex.market_close(coin: 'ETH') },
    'cancel' => ->(ex, _) { ex.cancel(coin: 'ETH', oid: 123_456_789) },
    'cancel_vault_mainnet' => ->(ex, v) { ex.cancel(coin: 'BTC', oid: 42, vault_address: v) },
    'cancel_by_cloid' => ->(ex, _) { ex.cancel_by_cloid(coin: 'ETH', cloid: cloid_a) },
    'bulk_cancel_mainnet' => lambda { |ex, _|
      ex.bulk_cancel(cancels: [{ coin: 'ETH', oid: 1 }, { coin: 'PURR/USDC', oid: 2 }])
    },
    'bulk_cancel_by_cloid' => lambda { |ex, _|
      ex.bulk_cancel_by_cloid(cancels: [{ coin: 'ETH', cloid: cloid_a }, { coin: 'SOL', cloid: cloid_b }])
    },
    'modify_order_oid' => lambda { |ex, _|
      ex.modify_order(oid: 123, coin: 'ETH', is_buy: true, size: 0.1, limit_px: 2000.5)
    },
    'modify_order_cloid_mainnet' => lambda { |ex, _|
      ex.modify_order(oid: cloid_a, coin: 'ETH', is_buy: false, size: 0.3, limit_px: 3100, order_type: alo,
                      reduce_only: true, cloid: cloid_b)
    },
    'bulk_modify_orders' => lambda { |ex, _|
      ex.batch_modify(
        modifies: [
          { oid: 1, coin: 'BTC', is_buy: true, size: 0.001, limit_px: 90_000 },
          { oid: cloid_b, coin: 'ETH', is_buy: false, size: 0.5, limit_px: 3500, reduce_only: true, cloid: cloid_b,
            order_type: { trigger: { trigger_px: 3400, is_market: true, tpsl: 'tp' } } }
        ]
      )
    },
    'update_leverage_cross' => ->(ex, _) { ex.update_leverage(coin: 'ETH', leverage: 10) },
    'update_leverage_isolated_mainnet' => ->(ex, _) { ex.update_leverage(coin: 'BTC', leverage: 5, is_cross: false) },
    'update_isolated_margin' => ->(ex, _) { ex.update_isolated_margin(coin: 'ETH', amount: 12.5) },
    'update_isolated_margin_negative_mainnet' => ->(ex, _) { ex.update_isolated_margin(coin: 'SOL', amount: -3.25) },
    'schedule_cancel_unset' => ->(ex, _) { ex.schedule_cancel },
    'schedule_cancel_time_mainnet' => ->(ex, _) { ex.schedule_cancel(time: 1_700_000_100_000) },
    'schedule_cancel_vault_expires' => ->(ex, v) { ex.schedule_cancel(time: 1_700_000_100_000, vault_address: v) },
    'create_sub_account' => ->(ex, _) { ex.create_sub_account(name: 'parity-sub') },
    'create_sub_account_expires' => ->(ex, _) { ex.create_sub_account(name: 'parity-sub') },
    'sub_account_transfer' => lambda { |ex, _|
      ex.sub_account_transfer(sub_account_user: sub_account, is_deposit: true, usd: 1)
    },
    'sub_account_transfer_expires' => lambda { |ex, _|
      ex.sub_account_transfer(sub_account_user: sub_account, is_deposit: false, usd: 2.5)
    },
    'sub_account_spot_transfer' => lambda { |ex, _|
      ex.sub_account_spot_transfer(sub_account_user: sub_account, is_deposit: true, token: purr, amount: 12.5)
    },
    'sub_account_spot_transfer_expires' => lambda { |ex, _|
      ex.sub_account_spot_transfer(sub_account_user: sub_account, is_deposit: false, token: purr, amount: 3)
    },
    'vault_usd_transfer' => ->(ex, _) { ex.vault_transfer(vault_address: vault, is_deposit: true, usd: 5) },
    'vault_usd_transfer_expires' => ->(ex, _) { ex.vault_transfer(vault_address: vault, is_deposit: false, usd: 1) },
    'set_referrer' => ->(ex, _) { ex.set_referrer(code: 'PARITY') },
    'set_referrer_expires' => ->(ex, _) { ex.set_referrer(code: 'PARITY') },
    'use_big_blocks_enable' => ->(ex, _) { ex.use_big_blocks(enable: true) },
    'use_big_blocks_disable_expires_mainnet' => ->(ex, _) { ex.use_big_blocks(enable: false) },
    'noop' => ->(ex, _) { ex.noop(nonce: 1_700_000_000_123) },
    'noop_vault_mainnet' => ->(ex, v) { ex.noop(nonce: 1_700_000_000_123, vault_address: v) },
    'agent_enable_dex_abstraction' => ->(ex, _) { ex.agent_enable_dex_abstraction },
    'agent_set_abstraction' => ->(ex, _) { ex.agent_set_abstraction(abstraction: 'u') },
    'gossip_priority_bid' => ->(ex, _) { ex.gossip_priority_bid(slot_id: 7, ip: '1.2.3.4', max_gas: 1_000_000) }
  }

  rows = fixture['rows'].to_h { |row| [row['name'], row] }

  (rows.keys | calls.keys).each do |name|
    it "#{name} posts the Python SDK action bytes and signature" do
      row = rows.fetch(name) { raise "Ruby call #{name} has no captured row; rerun tools/parity/regenerate.sh" }
      call = calls.fetch(name) { raise "fixture row #{name} has no Ruby call mapping in this spec" }
      base_url = row['mainnet'] ? Hyperliquid::Constants::MAINNET_API_URL : Hyperliquid::Constants::TESTNET_API_URL
      client = Hyperliquid::Client.new(base_url: base_url)
      exchange = described_class.new(
        client: client,
        signer: Hyperliquid::Signing::Signer.new(private_key: fixture['private_key'], testnet: !row['mainnet']),
        info: Hyperliquid::Info.new(client),
        testnet: !row['mainnet'],
        expires_after: row['expires_after']
      )
      allow(exchange).to receive(:timestamp_ms).and_return(row['nonce'])
      stub_request(:post, "#{base_url}/info").to_return do |req|
        { status: 200, body: JSON.generate(fixture['info_responses'].fetch(JSON.parse(req.body)['type'])) }
      end
      posted = nil
      stub_request(:post, "#{base_url}/exchange").to_return do |req|
        posted = req.body
        { status: 200, body: '{"status":"ok"}' }
      end

      call.call(exchange, row['vault_address'])

      body = JSON.parse(posted)
      expect(JSON.generate(body['action'])).to eq(row['action_json'])
      expect(%w[nonce vaultAddress expiresAfter signature].to_h { |key| [key, body[key]] }).to eq(
        'nonce' => row['nonce'],
        'vaultAddress' => row['vault_address'],
        'expiresAfter' => row['expires_after'],
        'signature' => { 'r' => row['r'], 's' => row['s'], 'v' => row['v'] }
      )
    end
  end
end
