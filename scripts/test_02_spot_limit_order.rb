#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 2: Spot Limit Order (Place and Cancel)
# Place a limit buy well below market, then cancel it.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 2: Spot Limit Order (Place and Cancel)')

spot_coin = 'PURR/USDC'
spot_size = 5

mids = sdk.info.all_mids
spot_price = mids[spot_coin]&.to_f

if spot_price&.positive?
  limit_price = (spot_price * 0.50).round(2)
  puts "#{spot_coin} mid: $#{spot_price}"
  puts "Limit price: $#{limit_price} (50% below mid - won't fill)"
  puts "Size: #{spot_size} PURR"
  puts

  puts 'Placing limit BUY order...'
  result = sdk.exchange.order(
    coin: spot_coin,
    is_buy: true,
    size: spot_size,
    limit_px: limit_price,
    order_type: { limit: { tif: 'Gtc' } },
    reduce_only: false
  )
  oid = check_result(result, 'Limit order')

  if oid.is_a?(Integer)
    wait_with_countdown(WAIT_SECONDS, 'Order resting. Waiting before cancel...')

    puts "Canceling order #{oid}..."
    result = sdk.exchange.cancel(coin: spot_coin, oid: oid)
    check_result(result, 'Cancel')
  end
else
  puts red("SKIPPED: Could not get #{spot_coin} price")
end

test_passed('Test 2 Spot Limit Order')

