#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 4: Perp Limit Order (Short, then Cancel)
# Place a limit sell well above market, then cancel it.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 4: Perp Limit Order (Short, then Cancel)')

perp_coin = 'BTC'
mids = sdk.info.all_mids
btc_price = mids[perp_coin]&.to_f

if btc_price&.positive?
  meta = sdk.info.meta
  btc_meta = meta['universe'].find { |a| a['name'] == perp_coin }
  sz_decimals = btc_meta['szDecimals']

  limit_price = (btc_price * 1.50).round(0).to_i
  perp_size = (20.0 / btc_price).ceil(sz_decimals)

  puts "#{perp_coin} mid: $#{btc_price.round(2)}"
  puts "Limit price: $#{limit_price} (50% above mid - won't fill)"
  puts "Size: #{perp_size} BTC"
  puts

  puts 'Placing limit SELL order (short)...'
  result = sdk.exchange.order(
    coin: perp_coin,
    is_buy: false,
    size: perp_size,
    limit_px: limit_price,
    order_type: { limit: { tif: 'Gtc' } },
    reduce_only: false
  )
  oid = check_result(result, 'Limit short')

  if oid.is_a?(Integer)
    wait_with_countdown(WAIT_SECONDS, 'Order resting. Waiting before cancel...')

    puts "Canceling order #{oid}..."
    result = sdk.exchange.cancel(coin: perp_coin, oid: oid)
    check_result(result, 'Cancel')
  end
else
  puts red("SKIPPED: Could not get #{perp_coin} price")
end

test_passed('Test 4 Perp Limit Order')

