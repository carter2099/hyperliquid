#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 6: Modify Order (BTC)
# Place a limit buy, modify its price, then cancel.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 6: Modify Order (BTC)')

perp_coin = 'BTC'
mids = sdk.info.all_mids
btc_price = mids[perp_coin]&.to_f

if btc_price&.positive?
  meta = sdk.info.meta
  btc_meta = meta['universe'].find { |a| a['name'] == perp_coin }
  sz_decimals = btc_meta['szDecimals']

  original_price = (btc_price * 0.50).round(0).to_i
  modified_price = (btc_price * 0.51).round(0).to_i
  perp_size = (20.0 / btc_price).ceil(sz_decimals)

  puts "#{perp_coin} mid: $#{btc_price.round(2)}"
  puts "Original limit: $#{original_price} (50% below mid)"
  puts "Modified limit: $#{modified_price} (49% below mid)"
  puts "Size: #{perp_size} BTC"
  puts

  puts 'Placing limit BUY order...'
  result = sdk.exchange.order(
    coin: perp_coin,
    is_buy: true,
    size: perp_size,
    limit_px: original_price,
    order_type: { limit: { tif: 'Gtc' } }
  )
  oid = check_result(result, 'Limit buy')

  if oid.is_a?(Integer)
    wait_with_countdown(WAIT_SECONDS, 'Order resting. Waiting before modify...')

    puts "Modifying order #{oid} (price: $#{original_price} -> $#{modified_price})..."
    result = sdk.exchange.modify_order(
      oid: oid,
      coin: perp_coin,
      is_buy: true,
      size: perp_size,
      limit_px: modified_price
    )
    new_oid = check_result(result, 'Modify')
    new_oid = oid unless new_oid.is_a?(Integer)
    puts

    wait_with_countdown(WAIT_SECONDS, 'Waiting before cancel...')

    puts "Canceling modified order #{new_oid}..."
    result = sdk.exchange.cancel(coin: perp_coin, oid: new_oid)
    check_result(result, 'Cancel')
  end
else
  puts red("SKIPPED: Could not get #{perp_coin} price")
end

test_passed('Test 6 Modify Order')

