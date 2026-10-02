#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 1: Spot Market Roundtrip (PURR/USDC)
# Buy PURR at market, then sell the filled size back. Every leg must come back
# `filled` with a positive size; an IOC leg may fill only partly against the thin
# testnet book, so the unsold remainder (tracked from the fills) is sold again, up
# to SELL_ATTEMPTS sells in total. A remainder left after that is INCONCLUSIVE
# (book depth, not an SDK defect). If the script bought but did not finish selling
# (error, exception, timeout), `ensure` sells the remainder back with the attempts
# left and reports any cleanup error.

require_relative 'test_helpers'

TEST_NAME = 'Test 1 Spot Market Roundtrip'
SPOT_COIN = 'PURR/USDC'
SPOT_SIZE = 5
SELL_ATTEMPTS = 3

def first_status(result)
  response = result.is_a?(Hash) ? result['response'] : nil
  data = response.is_a?(Hash) ? response['data'] : nil
  data.is_a?(Hash) ? data.dig('statuses', 0) : nil
end

# Returns the filled size (Float > 0) or nil after recording the failure. An IOC
# market order may fill only part of the requested size; any positive fill passes.
def filled_size!(result, label)
  check_result(result, label)
  status = first_status(result)
  filled = status['filled'] if status.is_a?(Hash)
  size = filled['totalSz'].to_f if filled.is_a?(Hash)
  return size if size&.positive?

  fail!("#{label}: expected a filled status, got #{result.inspect}")
  nil
end

# Sells state[:unsold] at market until nothing is left or SELL_ATTEMPTS sells
# (counted across the run and the cleanup) have been placed. Stops at the first
# response that is not a positive fill (recorded as a failure).
def sell_down(sdk, state, label)
  while state[:unsold].positive? && state[:sells] < SELL_ATTEMPTS
    wait_with_countdown(WAIT_SECONDS, "Waiting before #{label.downcase}...")
    state[:sells] += 1
    size = state[:unsold]
    puts "#{label} #{state[:sells]}/#{SELL_ATTEMPTS}: market SELL of #{size} PURR..."
    result = sdk.exchange.market_order(coin: SPOT_COIN, is_buy: false, size: size, slippage: SPOT_SLIPPAGE)
    sold = filled_size!(result, "#{label} #{state[:sells]}")
    return unless sold

    state[:unsold] = (size - sold).round(8)
    puts "Sold #{sold} PURR, #{state[:unsold]} left"
  end
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

  sell_down(sdk, state, 'Sell')
end

# Sells back what this script bought and has not sold yet, with the sell attempts
# the run left over. Reports, never raises.
def sell_back(sdk, state)
  return unless state[:unsold].positive? && state[:sells] < SELL_ATTEMPTS

  puts "Cleanup: selling back #{state[:unsold]} PURR bought by this script..."
  sell_down(sdk, state, 'Cleanup sell')
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

sdk = build_sdk
separator('TEST 1: Spot Market Roundtrip (PURR/USDC)')

state = { unsold: 0.0, sells: 0 }
begin
  run(sdk, state)
ensure
  sell_back(sdk, state)
end

if state[:unsold].positive?
  finish_inconclusive(TEST_NAME, "testnet book depth: #{state[:unsold]} PURR left after #{state[:sells]} sells")
end
test_passed(TEST_NAME)
