#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 6: Modify Order (BTC)
# Place a resting limit buy, modify its price, read the modified order back
# from open_orders (new limitPx; the original oid gone if the oid changed),
# then cancel it and confirm it left open_orders.
# `ensure` cancels this script's own orders if any are still open.

require 'bigdecimal'
require_relative 'test_helpers'

TEST_NAME = 'Test 6 Modify Order'
PERP_COIN = 'BTC'

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

# Exact decimal comparison of a wire price string against the requested price.
def same_price?(wire_px, expected_px)
  BigDecimal(wire_px.to_s) == BigDecimal(expected_px.to_s)
end

# Polls open_orders for this coin's order at limit_px (oid must equal new_oid when the
# modify response reported one). Returns the order Hash or nil.
def await_modified(sdk, limit_px, new_oid, attempts: 5)
  attempts.times do |i|
    order = sdk.info.open_orders(sdk.exchange.address).find do |o|
      o['coin'] == PERP_COIN && same_price?(o['limitPx'], limit_px) && (new_oid.nil? || o['oid'] == new_oid)
    end
    return order if order

    sleep 1 unless i == attempts - 1
  end
  nil
end

def modify!(sdk, own_oids, oid, size, limit_px)
  result = sdk.exchange.modify_order(oid: oid, coin: PERP_COIN, is_buy: true, size: size, limit_px: limit_px)
  dump_status(result)
  status = first_status(result)
  unless result.is_a?(Hash) && result['status'] == 'ok' && !(status.is_a?(Hash) && status['error'])
    fail!("Modify: expected status ok without error, got #{result.inspect}")
    return nil
  end

  new_oid = status.is_a?(Hash) ? status.dig('resting', 'oid') : nil
  own_oids << new_oid if new_oid
  modified = await_modified(sdk, limit_px, new_oid)
  unless modified
    fail!("Modify: no open #{PERP_COIN} order at $#{limit_px} (oid #{new_oid.inspect}) in open_orders")
    return nil
  end

  modified_oid = modified['oid']
  own_oids << modified_oid
  if modified_oid != oid && !await_open(sdk, oid, present: false)
    fail!("Modify: original oid #{oid} is still open next to modified oid #{modified_oid}")
  end
  puts green("Modify confirmed: open order #{modified_oid} at $#{modified['limitPx']}")
  modified_oid
end

def run(sdk, own_oids)
  btc_price = sdk.info.all_mids[PERP_COIN]&.to_f
  return fail!("Could not get #{PERP_COIN} mid price") unless btc_price&.positive?

  sz_decimals = sdk.info.meta['universe'].find { |a| a['name'] == PERP_COIN }['szDecimals']
  original_price = (btc_price * 0.50).round(0).to_i
  modified_price = (btc_price * 0.51).round(0).to_i
  perp_size = (20.0 / btc_price).ceil(sz_decimals)

  puts "#{PERP_COIN} mid: $#{btc_price.round(2)}"
  puts "Original limit: $#{original_price} (50% below mid)"
  puts "Modified limit: $#{modified_price} (49% below mid)"
  puts "Size: #{perp_size} BTC"
  puts

  puts 'Placing limit BUY order...'
  oid = place_resting!(sdk, own_oids, 'Limit buy',
                       coin: PERP_COIN, is_buy: true, size: perp_size, limit_px: original_price,
                       order_type: { limit: { tif: 'Gtc' } })
  return unless oid

  wait_with_countdown(WAIT_SECONDS, 'Order resting. Waiting before modify...')

  puts "Modifying order #{oid} (price: $#{original_price} -> $#{modified_price})..."
  new_oid = modify!(sdk, own_oids, oid, perp_size, modified_price)
  return unless new_oid

  puts
  wait_with_countdown(WAIT_SECONDS, 'Waiting before cancel...')

  puts "Canceling modified order #{new_oid}..."
  cancel_confirmed!(sdk, PERP_COIN, new_oid)
end

sdk = build_sdk
separator('TEST 6: Modify Order (BTC)')

own_oids = []
begin
  run(sdk, own_oids)
ensure
  cancel_own_orders(sdk, PERP_COIN, own_oids)
end

test_passed(TEST_NAME)
