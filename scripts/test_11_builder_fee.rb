#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 11: Builder Fee (Approve + Order with Builder)
# Approve a builder fee, then place an order with builder param, then cancel.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 11: Builder Fee (Approve + Order with Builder)')

builder_address = '0x250F311Ae04D3CEA03443C76340069eD26C47D7D'
max_fee_rate = '0.01%'
perp_coin = 'BTC'

# Step 1: Approve builder fee
puts "Approving builder fee for #{builder_address} (max #{max_fee_rate})..."
result = sdk.exchange.approve_builder_fee(builder: builder_address, max_fee_rate: max_fee_rate)
dump_status(result)
api_error?(result) || puts(green('Builder fee approved'))
puts

wait_with_countdown(WAIT_SECONDS, 'Waiting before placing order with builder...')

# Step 2: Verify approval via Info API
puts 'Checking builder fee approval...'
approval = sdk.info.max_builder_fee(sdk.exchange.address, builder_address)
puts "Max builder fee: #{approval.inspect}"
puts

# Step 3: Place order with builder param
mids = sdk.info.all_mids
btc_price = mids[perp_coin]&.to_f

if btc_price&.positive?
  meta = sdk.info.meta
  btc_meta = meta['universe'].find { |a| a['name'] == perp_coin }
  sz_decimals = btc_meta['szDecimals']

  limit_price = (btc_price * 1.50).round(0).to_i
  perp_size = (20.0 / btc_price).ceil(sz_decimals)

  puts "#{perp_coin} mid: $#{btc_price.round(2)}"
  puts "Limit price: $#{limit_price} (50% above mid - won't fill)"
  puts "Size: #{perp_size} BTC"
  puts "Builder: #{builder_address} (fee: 10 = 1bp)"
  puts

  puts 'Placing limit SELL order with builder fee...'
  result = sdk.exchange.order(
    coin: perp_coin,
    is_buy: false,
    size: perp_size,
    limit_px: limit_price,
    order_type: { limit: { tif: 'Gtc' } },
    builder: { b: builder_address, f: 10 }
  )
  oid = check_result(result, 'Limit short with builder')

  if oid.is_a?(Integer)
    wait_with_countdown(WAIT_SECONDS, 'Order resting. Waiting before cancel...')

    puts "Canceling order #{oid}..."
    result = sdk.exchange.cancel(coin: perp_coin, oid: oid)
    check_result(result, 'Cancel')
  end
else
  puts red("SKIPPED: Could not get #{perp_coin} price")
end

test_passed('Test 11 Builder Fee')
