#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 7: Market Close (PERP)
# Requires a flat ETH book (no position/orders). Open a long at market (must
# fill and show in user_state), close it with market_close (auto-detected
# size; must fill), and confirm the position is flat. `ensure` closes the
# position this script opened if it is still open.

require_relative 'test_helpers'

TEST_NAME = 'Test 7 Market Close'
PERP_COIN = 'ETH'

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

def position_size(sdk)
  szi = get_position(sdk, PERP_COIN)&.dig('position', 'szi')
  szi.to_f
end

# Polls user_state (read-after-write lag) until the position size satisfies the block.
def await_position(sdk, attempts: 5)
  size = nil
  attempts.times do |i|
    size = position_size(sdk)
    return size if yield(size)

    sleep 1 unless i == attempts - 1
  end
  size
end

# The wallet was flat on PERP_COIN at start (require_flat!), so any position is this
# script's own: close it. Reports, never raises.
def close_own_position(sdk)
  return if position_size(sdk).zero?

  puts "Cleanup: closing the #{PERP_COIN} position this script opened..."
  result = sdk.exchange.market_close(coin: PERP_COIN, slippage: PERP_SLIPPAGE + 0.20)
  dump_status(result)
  left = await_position(sdk, &:zero?)
  fail!("Cleanup: #{PERP_COIN} position still open (szi=#{left}): #{result.inspect}") unless left.zero?
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

# Opens a long of about $20 and returns the filled size, or nil after recording the failure.
def open_long(sdk)
  price = sdk.info.all_mids[PERP_COIN]&.to_f
  unless price&.positive?
    fail!("Could not get #{PERP_COIN} mid price")
    return nil
  end

  sz_decimals = sdk.info.meta['universe'].find { |a| a['name'] == PERP_COIN }['szDecimals']
  perp_size = (20.0 / price).ceil(sz_decimals)
  max_slippage = PERP_SLIPPAGE + (ORACLE_SLIPPAGE_INCREMENT * (ORACLE_RETRY_ATTEMPTS - 1))

  puts "#{PERP_COIN} mid: $#{price.round(2)}"
  puts "Size: #{perp_size} #{PERP_COIN} (~$#{(perp_size * price).round(2)})"
  puts "Slippage: #{(PERP_SLIPPAGE * 100).to_i}% (with retry up to #{(max_slippage * 100).to_i}%)"
  puts

  puts 'Opening LONG position (market buy)...'
  result = market_order_with_retry(sdk, coin: PERP_COIN, is_buy: true, size: perp_size, base_slippage: PERP_SLIPPAGE)
  filled = filled_size!(result, 'Long open')
  return unless filled

  held = await_position(sdk, &:positive?)
  unless held.positive?
    fail!("Long open filled #{filled} but user_state shows szi=#{held}")
    return nil
  end

  puts green("Position open: szi=#{held}")
  filled
end

def assert_flat(sdk, label)
  left = await_position(sdk, &:zero?)
  if left.zero?
    puts green("#{label} confirmed: #{PERP_COIN} position is flat")
  else
    fail!("#{label}: #{PERP_COIN} position still open after close (szi=#{left})")
  end
end

def run(sdk)
  return unless open_long(sdk)

  wait_with_countdown(WAIT_SECONDS, 'Position open. Waiting before market_close...')

  puts 'Closing position using market_close (auto-detect size)...'
  result = sdk.exchange.market_close(
    coin: PERP_COIN,
    slippage: PERP_SLIPPAGE + ORACLE_SLIPPAGE_INCREMENT # Use higher slippage for close
  )
  return unless filled_size!(result, 'Market close')

  assert_flat(sdk, 'Market close')
end

sdk = build_sdk
separator("TEST 7: Market Close (#{PERP_COIN})")

require_flat!(sdk, PERP_COIN)
test_passed(TEST_NAME) if $test_failed

begin
  run(sdk)
ensure
  close_own_position(sdk)
end

test_passed(TEST_NAME)
