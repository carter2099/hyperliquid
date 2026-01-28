#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 5: Update Leverage (BTC)
# Set cross, isolated, then reset leverage.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 5: Update Leverage (BTC)')

perp_coin = 'BTC'
mids = sdk.info.all_mids
btc_price = mids[perp_coin]&.to_f

if btc_price&.positive?
  puts 'Setting BTC to 5x cross leverage...'
  result = sdk.exchange.update_leverage(coin: perp_coin, leverage: 5, is_cross: true)
  api_error?(result) || puts(green('5x cross leverage set'))
  puts

  wait_with_countdown(WAIT_SECONDS, 'Waiting before next leverage update...')

  puts 'Setting BTC to 3x isolated leverage...'
  result = sdk.exchange.update_leverage(coin: perp_coin, leverage: 3, is_cross: false)
  api_error?(result) || puts(green('3x isolated leverage set'))
  puts

  wait_with_countdown(WAIT_SECONDS, 'Waiting before resetting leverage...')

  puts 'Resetting BTC to 1x cross leverage...'
  result = sdk.exchange.update_leverage(coin: perp_coin, leverage: 1, is_cross: true)
  api_error?(result) || puts(green('1x cross leverage set'))
else
  puts red("SKIPPED: Could not get #{perp_coin} price")
end

test_passed('Test 5 Update Leverage')

