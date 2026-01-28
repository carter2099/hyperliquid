#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 1: Spot Market Roundtrip (PURR/USDC)
# Buy and sell PURR at market price.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 1: Spot Market Roundtrip (PURR/USDC)')

spot_coin = 'PURR/USDC'
spot_size = 5

mids = sdk.info.all_mids
spot_price = mids[spot_coin]&.to_f

if spot_price&.positive?
  puts "#{spot_coin} mid: $#{spot_price}"
  puts "Size: #{spot_size} PURR (~$#{(spot_size * spot_price).round(2)})"
  puts "Slippage: #{(SPOT_SLIPPAGE * 100).to_i}%"
  puts

  puts 'Placing market BUY...'
  result = sdk.exchange.market_order(
    coin: spot_coin,
    is_buy: true,
    size: spot_size,
    slippage: SPOT_SLIPPAGE
  )
  check_result(result, 'Buy')

  wait_with_countdown(WAIT_SECONDS, 'Waiting before sell...')

  puts 'Placing market SELL...'
  result = sdk.exchange.market_order(
    coin: spot_coin,
    is_buy: false,
    size: spot_size,
    slippage: SPOT_SLIPPAGE
  )
  check_result(result, 'Sell')
else
  puts red("SKIPPED: Could not get #{spot_coin} price")
end

test_passed('Test 1 Spot Market Roundtrip')

