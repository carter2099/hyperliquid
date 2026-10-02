#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 11: Builder Fee (Approve + Order with Builder)
# Approve a builder fee, then place an order with builder param, then cancel.
#
# The builder is a third-party address (the TS SDK's test builder). Builders must
# keep >= 100 USDC perp account value and standard abstraction to be approvable,
# so an Info preflight decides whether approval failures are hard failures
# (eligible builder) or warnings (builder drifted ineligible).

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 11: Builder Fee (Approve + Order with Builder)')

builder_address = '0xe019d6167E7e324aEd003d94098496b6d986aB05' # TS SDK test builder; must keep >=100 USDC perp value + standard abstraction
max_fee_rate = '0.01%'
perp_coin = 'BTC'

# Step 1: Preflight builder eligibility, then approve builder fee
b_state = sdk.info.user_state(builder_address)
b_value = b_state.dig('marginSummary', 'accountValue').to_f
b_mode = sdk.info.user_abstraction(builder_address)
eligible = b_value >= 100 && %w[disabled default].include?(b_mode)
puts "Builder #{builder_address}: accountValue=#{b_value} abstraction=#{b_mode.inspect} " \
     "(#{eligible ? 'eligible' : 'INELIGIBLE'})"
puts

puts "Approving builder fee for #{builder_address} (max #{max_fee_rate})..."
result = sdk.exchange.approve_builder_fee(builder: builder_address, max_fee_rate: max_fee_rate)
if eligible
  dump_status(result)
  api_error?(result) || puts(green('Builder fee approved'))
else
  puts red("WARNING: builder ineligible (accountValue=#{b_value}, abstraction=#{b_mode}); " \
           "approval result: #{result.inspect}")
end
puts

wait_with_countdown(WAIT_SECONDS, 'Waiting before placing order with builder...')

# Step 2: Verify approval via Info API
puts 'Checking builder fee approval...'
approval = sdk.info.max_builder_fee(sdk.exchange.address, builder_address).to_i
puts "Max builder fee: #{approval.inspect}"
if eligible && approval < 10
  $test_failed = true
  puts red("FAILED: max builder fee #{approval} < 10 after approving an eligible builder")
end
puts

# Step 3: Place order with builder param
if approval >= 10
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

    oid = nil
    if eligible
      oid = check_result(result, 'Limit short with builder')
    else
      status = result.is_a?(Hash) ? result.dig('response', 'data', 'statuses', 0) : nil
      if result.is_a?(Hash) && result['status'] == 'err'
        puts red("WARNING: order with ineligible builder rejected: #{result['response']}")
      elsif status.is_a?(Hash) && status['error']
        puts red("WARNING: order with ineligible builder rejected: #{status['error']}")
      else
        oid = check_result(result, 'Limit short with builder')
      end
    end

    if oid.is_a?(Integer)
      wait_with_countdown(WAIT_SECONDS, 'Order resting. Waiting before cancel...')

      puts "Canceling order #{oid}..."
      result = sdk.exchange.cancel(coin: perp_coin, oid: oid)
      check_result(result, 'Cancel')
    end
  else
    puts red("SKIPPED: Could not get #{perp_coin} price")
  end
else
  puts red('SKIPPED order step: builder fee not approved (ineligible builder)')
end

test_passed('Test 11 Builder Fee')
