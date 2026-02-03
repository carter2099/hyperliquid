#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 3: Perp Market Roundtrip (Long)
# Open a long perp position, then close it.

require_relative 'test_helpers'

sdk = build_sdk
perp_coin = 'ETH'
separator("TEST 3: Perp Market Roundtrip (#{perp_coin} Long)")

mids = sdk.info.all_mids
perp_coin_price = mids[perp_coin]&.to_f

if perp_coin_price&.positive?
  meta = sdk.info.meta
  perp_coin_meta = meta['universe'].find { |a| a['name'] == perp_coin }
  sz_decimals = perp_coin_meta['szDecimals']

  perp_size = (20.0 / perp_coin_price).ceil(sz_decimals)

  puts "#{perp_coin} mid: $#{perp_coin_price.round(2)}"
  puts "Size: #{perp_size} #{perp_coin} (~$#{(perp_size * perp_coin_price).round(2)})"
  puts "Slippage: #{(PERP_SLIPPAGE * 100).to_i}% (with retry up to #{((PERP_SLIPPAGE + ORACLE_SLIPPAGE_INCREMENT * (ORACLE_RETRY_ATTEMPTS - 1)) * 100).to_i}%)"
  puts

  puts 'Opening LONG position (market buy)...'
  result = market_order_with_retry(
    sdk,
    coin: perp_coin,
    is_buy: true,
    size: perp_size,
    base_slippage: PERP_SLIPPAGE
  )
  open_success = check_result(result, 'Long open')

  if open_success
    wait_with_countdown(WAIT_SECONDS, 'Position open. Waiting before close...')

    puts 'Closing LONG position (market sell)...'
    result = market_order_with_retry(
      sdk,
      coin: perp_coin,
      is_buy: false,
      size: perp_size,
      base_slippage: PERP_SLIPPAGE
    )
    check_result(result, 'Long close')
  else
    puts red('Skipping close - position was not opened')
  end
else
  puts red("SKIPPED: Could not get #{perp_coin} price")
end

test_passed('Test 3 Perp Market Roundtrip')

