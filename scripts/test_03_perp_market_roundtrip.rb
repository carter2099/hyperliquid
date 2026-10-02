#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 3: Perp Market Roundtrip (Long)
# Requires a flat ETH book (no position/orders). Open a long at market (must
# fill and show in user_state), close it with an opposite market order of the
# filled size, and confirm the position is flat. Every leg must come back
# `filled` with a positive size; an IOC close that fills only partly against the
# thin testnet book is retried with reduce-only market_close of the remainder
# (tracked from the fills), up to CLOSE_ATTEMPTS closes in total. A remainder
# left after that is INCONCLUSIVE (book depth, not an SDK defect). `ensure`
# closes the position this script opened if it is still open, with the attempts left.

require_relative 'test_helpers'

TEST_NAME = 'Test 3 Perp Market Roundtrip'
PERP_COIN = 'ETH'
CLOSE_ATTEMPTS = 3
RETRY_CLOSE_SLIPPAGE = PERP_SLIPPAGE + 0.20

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

def record_close(state, closed)
  state[:open] = (state[:open] - closed).round(8)
  puts "Closed #{closed} #{PERP_COIN}, #{state[:open]} left"
end

# Closes state[:open] (the long this script still holds, tracked from the fills)
# with reduce-only market_close orders until nothing is left or CLOSE_ATTEMPTS
# closes (counted across the run and the cleanup) have been placed. Stops at the
# first response that is not a positive fill (recorded as a failure).
def close_down(sdk, state, label)
  while state[:open].positive? && state[:closes] < CLOSE_ATTEMPTS
    wait_with_countdown(WAIT_SECONDS, "Waiting before #{label.downcase}...")
    state[:closes] += 1
    size = state[:open]
    puts "#{label} #{state[:closes]}/#{CLOSE_ATTEMPTS}: market_close of #{size} #{PERP_COIN}..."
    result = sdk.exchange.market_close(coin: PERP_COIN, size: size, slippage: RETRY_CLOSE_SLIPPAGE)
    closed = filled_size!(result, "#{label} #{state[:closes]}")
    return unless closed

    record_close(state, closed)
  end
end

# The wallet was flat on PERP_COIN at start (require_flat!), so any position is this
# script's own: close it with the close attempts the run left over. Reports, never raises.
def close_own_position(sdk, state)
  return unless state[:closes] < CLOSE_ATTEMPTS

  held = position_size(sdk)
  return if held.zero?

  puts "Cleanup: closing the #{PERP_COIN} position this script opened (szi=#{held})..."
  state[:open] = held
  close_down(sdk, state, 'Cleanup close')
  return unless state[:open].zero?

  left = await_position(sdk, &:zero?)
  fail!("Cleanup: #{PERP_COIN} position still open (szi=#{left})") unless left.zero?
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

# Opens a long of about $20 and returns the filled size, or nil after recording the failure.
def open_long(sdk, state)
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

  state[:open] = filled

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

def run(sdk, state)
  return unless open_long(sdk, state)

  wait_with_countdown(WAIT_SECONDS, 'Position open. Waiting before close...')

  state[:closes] += 1
  size = state[:open]
  puts "Closing LONG position (market sell #{size})..."
  result = market_order_with_retry(sdk, coin: PERP_COIN, is_buy: false, size: size, base_slippage: PERP_SLIPPAGE)
  closed = filled_size!(result, 'Long close')
  return unless closed

  record_close(state, closed)
  close_down(sdk, state, 'Close retry')
  assert_flat(sdk, 'Long close') if state[:open].zero?
end

sdk = build_sdk
separator("TEST 3: Perp Market Roundtrip (#{PERP_COIN} Long)")

require_flat!(sdk, PERP_COIN)
test_passed(TEST_NAME) if $test_failed

state = { open: 0.0, closes: 0 }
begin
  run(sdk, state)
ensure
  close_own_position(sdk, state)
end

if state[:open].positive?
  finish_inconclusive(TEST_NAME, "testnet book depth: #{state[:open]} #{PERP_COIN} left after #{state[:closes]} closes")
end
test_passed(TEST_NAME)
