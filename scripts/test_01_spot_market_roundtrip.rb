#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 1: Spot Market Roundtrip (PURR/USDC)
# Buy PURR at market, then sell back every whole PURR the wallet can sell. The
# spot taker fee on the buy is paid in PURR, so the wallet holds a little less than
# the bought size; the sell size is therefore read from the spot balance
# (floor(total - hold) to PURR's szDecimals), not from the buy fill. Leftovers of
# earlier runs are sold too, so every run returns the wallet to sub-unit dust.
# Every leg must come back `filled` with a positive size; an IOC leg may fill only
# partly against the thin testnet book, so the balance is re-read and the rest is
# sold again, up to SELL_ATTEMPTS sells in total. Sellable PURR left after that is
# INCONCLUSIVE (book depth, not an SDK defect). If the run did not finish selling
# (error, exception, timeout), `ensure` sells the rest the same way with the
# attempts left and reports any cleanup error.

require 'bigdecimal'
require_relative 'test_helpers'

TEST_NAME = 'Test 1 Spot Market Roundtrip'
SPOT_COIN = 'PURR/USDC'
BASE_TOKEN = 'PURR'
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

def base_sz_decimals(sdk)
  token = (sdk.info.spot_meta['tokens'] || []).find { |t| t['name'] == BASE_TOKEN }
  raise "#{BASE_TOKEN} not found in spotMeta tokens" unless token

  Integer(token['szDecimals'])
end

# Reads the wallet's PURR spot balance, prints it, and returns the sellable size:
# total - hold, floored to the token's szDecimals (orders take whole size steps).
def sellable_size(sdk, sz_decimals, label)
  balances = sdk.info.spot_balances(sdk.exchange.address)['balances'] || []
  entry = balances.find { |b| b['coin'] == BASE_TOKEN } || {}
  total = BigDecimal(entry['total'] || '0')
  hold = BigDecimal(entry['hold'] || '0')
  sellable = (total - hold).floor(sz_decimals).to_f
  sellable = 0.0 unless sellable.positive?
  puts "#{label}: #{BASE_TOKEN} balance total=#{total.to_s('F')} hold=#{hold.to_s('F')} sellable=#{sellable}"
  sellable
end

# Sells the wallet's sellable PURR at market, re-reading the balance before each
# sell, until nothing sellable is left or SELL_ATTEMPTS sells (counted across the
# run and the cleanup) have been placed. Never places a sell for a zero size. Stops
# at the first response that is not a positive fill (recorded as a failure).
def sell_down(sdk, state, label)
  loop do
    state[:sellable] = sellable_size(sdk, state[:sz_decimals], "Balance before #{label.downcase}")
    return unless state[:sellable].positive? && state[:sells] < SELL_ATTEMPTS

    wait_with_countdown(WAIT_SECONDS, "Waiting before #{label.downcase}...")
    state[:sells] += 1
    size = state[:sellable]
    puts "#{label} #{state[:sells]}/#{SELL_ATTEMPTS}: market SELL of #{size} #{BASE_TOKEN}..."
    result = sdk.exchange.market_order(coin: SPOT_COIN, is_buy: false, size: size, slippage: SPOT_SLIPPAGE)
    return unless filled_size!(result, "#{label} #{state[:sells]}")
  end
end

def run(sdk, state)
  spot_price = sdk.info.all_mids[SPOT_COIN]&.to_f
  return fail!("Could not get #{SPOT_COIN} mid price") unless spot_price&.positive?

  state[:sz_decimals] = base_sz_decimals(sdk)
  puts "#{SPOT_COIN} mid: $#{spot_price}"
  puts "Size: #{SPOT_SIZE} #{BASE_TOKEN} (~$#{(SPOT_SIZE * spot_price).round(2)})"
  puts "Slippage: #{(SPOT_SLIPPAGE * 100).to_i}%"
  puts "#{BASE_TOKEN} szDecimals: #{state[:sz_decimals]}"
  sellable_size(sdk, state[:sz_decimals], 'Balance before buy')
  puts

  puts 'Placing market BUY...'
  result = sdk.exchange.market_order(coin: SPOT_COIN, is_buy: true, size: SPOT_SIZE, slippage: SPOT_SLIPPAGE)
  bought = filled_size!(result, 'Buy')
  return unless bought

  puts "Bought #{bought} #{BASE_TOKEN} (the taker fee is paid in #{BASE_TOKEN})"
  sell_down(sdk, state, 'Sell')
end

# Sells whatever sellable PURR is left (bought or older leftovers) with the sell
# attempts the run left over; skipped once the last balance read showed nothing
# sellable. Reports, never raises.
def sell_back(sdk, state)
  return if state[:sellable]&.zero? || state[:sells] >= SELL_ATTEMPTS

  puts 'Cleanup: selling back sellable PURR...'
  state[:sz_decimals] ||= base_sz_decimals(sdk)
  sell_down(sdk, state, 'Cleanup sell')
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

sdk = build_sdk
separator('TEST 1: Spot Market Roundtrip (PURR/USDC)')

state = { sellable: nil, sells: 0, sz_decimals: nil }
begin
  run(sdk, state)
ensure
  sell_back(sdk, state)
end

if state[:sellable].to_f.positive?
  finish_inconclusive(TEST_NAME, "testnet book depth: #{state[:sellable]} #{BASE_TOKEN} sellable after #{state[:sells]} sells")
end
test_passed(TEST_NAME)
