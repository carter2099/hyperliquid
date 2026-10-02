#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 1: Spot Market Roundtrip (PURR/USDC)
# Buy PURR at market, then sell exactly the filled size back. Both legs must
# come back `filled`. If the script bought but did not sell (error, exception,
# timeout), `ensure` sells the bought size back and reports any cleanup error.

require_relative 'test_helpers'

TEST_NAME = 'Test 1 Spot Market Roundtrip'
SPOT_COIN = 'PURR/USDC'
SPOT_SIZE = 5

def first_status(result)
  response = result.is_a?(Hash) ? result['response'] : nil
  data = response.is_a?(Hash) ? response['data'] : nil
  data.is_a?(Hash) ? data.dig('statuses', 0) : nil
end

# Returns the filled size (Float) or nil after recording the failure.
def filled_size!(result, label)
  check_result(result, label)
  status = first_status(result)
  return status['filled']['totalSz'].to_f if status.is_a?(Hash) && status['filled'].is_a?(Hash)

  fail!("#{label}: expected a filled status, got #{result.inspect}")
  nil
end

def run(sdk, state)
  spot_price = sdk.info.all_mids[SPOT_COIN]&.to_f
  return fail!("Could not get #{SPOT_COIN} mid price") unless spot_price&.positive?

  puts "#{SPOT_COIN} mid: $#{spot_price}"
  puts "Size: #{SPOT_SIZE} PURR (~$#{(SPOT_SIZE * spot_price).round(2)})"
  puts "Slippage: #{(SPOT_SLIPPAGE * 100).to_i}%"
  puts

  puts 'Placing market BUY...'
  result = sdk.exchange.market_order(coin: SPOT_COIN, is_buy: true, size: SPOT_SIZE, slippage: SPOT_SLIPPAGE)
  bought = filled_size!(result, 'Buy')
  return unless bought

  state[:unsold] = bought
  puts "Bought #{bought} PURR"

  wait_with_countdown(WAIT_SECONDS, 'Waiting before sell...')

  puts "Placing market SELL of #{bought}..."
  result = sdk.exchange.market_order(coin: SPOT_COIN, is_buy: false, size: bought, slippage: SPOT_SLIPPAGE)
  state[:unsold] = nil
  sold = filled_size!(result, 'Sell')
  fail!("Sell filled #{sold}, expected #{bought}") if sold && sold != bought
end

# Sells back what this script bought if the sell leg never ran. Reports, never raises.
def sell_back(sdk, size)
  puts "Cleanup: selling back #{size} PURR bought by this script..."
  result = sdk.exchange.market_order(coin: SPOT_COIN, is_buy: false, size: size, slippage: SPOT_SLIPPAGE)
  status = first_status(result)
  fail!("Cleanup: sell-back failed: #{result.inspect}") unless status.is_a?(Hash) && status['filled']
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

sdk = build_sdk
separator('TEST 1: Spot Market Roundtrip (PURR/USDC)')

state = { unsold: nil }
begin
  run(sdk, state)
ensure
  sell_back(sdk, state[:unsold]) if state[:unsold]
end

test_passed(TEST_NAME)
