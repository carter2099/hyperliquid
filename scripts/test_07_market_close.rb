#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 7: Market Close (BTC)
# Open a long position, then close it using market_close (auto-detect size).

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 7: Market Close (BTC)')

perp_coin = 'BTC'
mids = sdk.info.all_mids
btc_price = mids[perp_coin]&.to_f

if btc_price&.positive?
  meta = sdk.info.meta
  btc_meta = meta['universe'].find { |a| a['name'] == perp_coin }
  sz_decimals = btc_meta['szDecimals']

  perp_size = (20.0 / btc_price).ceil(sz_decimals)

  puts "#{perp_coin} mid: $#{btc_price.round(2)}"
  puts "Size: #{perp_size} BTC"
  puts

  puts 'Opening LONG position (market buy)...'
  result = sdk.exchange.market_order(
    coin: perp_coin,
    is_buy: true,
    size: perp_size,
    slippage: PERP_SLIPPAGE
  )
  check_result(result, 'Long open')

  wait_with_countdown(WAIT_SECONDS, 'Position open. Waiting before market_close...')

  puts 'Closing position using market_close (auto-detect size)...'
  result = sdk.exchange.market_close(
    coin: perp_coin,
    slippage: PERP_SLIPPAGE
  )
  check_result(result, 'Market close')
else
  puts red("SKIPPED: Could not get #{perp_coin} price")
end

test_passed('Test 7 Market Close')

