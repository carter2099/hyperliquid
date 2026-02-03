#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 7: Market Close (PERP)
# Open a long position, then close it using market_close (auto-detect size).

require_relative 'test_helpers'

sdk = build_sdk
perp_coin = 'ETH'
separator("TEST 7: Market Close (#{perp_coin})")

mids = sdk.info.all_mids
perp_coin_price = mids[perp_coin]&.to_f

if perp_coin_price&.positive?
  meta = sdk.info.meta
  perp_coin_meta = meta['universe'].find { |a| a['name'] == perp_coin }
  sz_decimals = perp_coin_meta['szDecimals']

  perp_size = (20.0 / perp_coin_price).ceil(sz_decimals)

  puts "#{perp_coin} mid: $#{perp_coin_price.round(2)}"
  puts "Size: #{perp_size} #{perp_coin}"
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
    wait_with_countdown(WAIT_SECONDS, 'Position open. Waiting before market_close...')

    puts 'Closing position using market_close (auto-detect size)...'
    result = sdk.exchange.market_close(
      coin: perp_coin,
      slippage: PERP_SLIPPAGE + ORACLE_SLIPPAGE_INCREMENT  # Use higher slippage for close
    )
    check_result(result, 'Market close')
  else
    puts red('Skipping market_close - position was not opened')
  end
else
  puts red("SKIPPED: Could not get #{perp_coin} price")
end

test_passed('Test 7 Market Close')

