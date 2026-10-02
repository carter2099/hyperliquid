#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 2: Spot Limit Order (Place and Cancel)
# Place a limit buy well below market (must come back `resting` and appear in
# open_orders), then cancel it (must return `success` and leave open_orders).
# `ensure` cancels this script's own order if it is still open.

require_relative 'test_helpers'

TEST_NAME = 'Test 2 Spot Limit Order'
SPOT_COIN = 'PURR/USDC'
SPOT_SIZE = 5

def first_status(result)
  response = result.is_a?(Hash) ? result['response'] : nil
  data = response.is_a?(Hash) ? response['data'] : nil
  data.is_a?(Hash) ? data.dig('statuses', 0) : nil
end

def open_oids(sdk)
  sdk.info.open_orders(sdk.exchange.address).map { |o| o['oid'] }
end

# Polls open_orders (read-after-write lag) until the oid's presence matches.
def await_open(sdk, oid, present:, attempts: 5)
  attempts.times do |i|
    return true if open_oids(sdk).include?(oid) == present

    sleep 1 unless i == attempts - 1
  end
  false
end

# Places an order that must rest; records its oid in own_oids. Returns the oid or nil.
def place_resting!(sdk, own_oids, label, **order)
  result = sdk.exchange.order(**order)
  oid = check_result(result, label)
  unless oid.is_a?(Integer)
    fail!("#{label}: expected a resting order, got #{result.inspect}") if oid
    return nil
  end
  own_oids << oid
  return oid if await_open(sdk, oid, present: true)

  fail!("#{label}: oid #{oid} reported resting but is not in open_orders")
  nil
end

def cancel_confirmed!(sdk, coin, oid)
  result = sdk.exchange.cancel(coin: coin, oid: oid)
  dump_status(result)
  return fail!("Cancel #{oid}: expected status \"success\", got #{result.inspect}") unless first_status(result) == 'success'

  if await_open(sdk, oid, present: false)
    puts green("Cancel confirmed: #{oid} is no longer in open_orders")
  else
    fail!("Cancel #{oid}: reported success but the order is still in open_orders")
  end
end

# Cancels this script's own orders that are still open. Reports, never raises.
def cancel_own_orders(sdk, coin, own_oids)
  return if own_oids.empty?

  (open_oids(sdk) & own_oids).each do |oid|
    puts "Cleanup: cancelling own order #{oid}..."
    result = sdk.exchange.cancel(coin: coin, oid: oid)
    fail!("Cleanup: cancel #{oid} failed: #{result.inspect}") unless first_status(result) == 'success'
  end
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

def run(sdk, own_oids)
  spot_price = sdk.info.all_mids[SPOT_COIN]&.to_f
  return fail!("Could not get #{SPOT_COIN} mid price") unless spot_price&.positive?

  limit_price = (spot_price * 0.50).round(2)
  puts "#{SPOT_COIN} mid: $#{spot_price}"
  puts "Limit price: $#{limit_price} (50% below mid - won't fill)"
  puts "Size: #{SPOT_SIZE} PURR"
  puts

  puts 'Placing limit BUY order...'
  oid = place_resting!(sdk, own_oids, 'Limit order',
                       coin: SPOT_COIN, is_buy: true, size: SPOT_SIZE, limit_px: limit_price,
                       order_type: { limit: { tif: 'Gtc' } }, reduce_only: false)
  return unless oid

  wait_with_countdown(WAIT_SECONDS, 'Order resting. Waiting before cancel...')

  puts "Canceling order #{oid}..."
  cancel_confirmed!(sdk, SPOT_COIN, oid)
end

sdk = build_sdk
separator('TEST 2: Spot Limit Order (Place and Cancel)')

own_oids = []
begin
  run(sdk, own_oids)
ensure
  cancel_own_orders(sdk, SPOT_COIN, own_oids)
end

test_passed(TEST_NAME)
