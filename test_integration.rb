#!/usr/bin/env ruby
# frozen_string_literal: true

# Hyperliquid Ruby SDK - Testnet Integration Test
#
# This script tests the Exchange API against the live testnet:
#   1. Spot market roundtrip (buy PURR, sell PURR)
#   2. Spot limit order (place and cancel)
#   3. Perp market roundtrip (long BTC, close position)
#   4. Perp limit order (place short, cancel)
#
# Prerequisites:
#   - Testnet wallet with USDC balance
#   - Get testnet funds from: https://app.hyperliquid-testnet.xyz
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby test_integration.rb
#
# Note: This script executes real trades on testnet. No real funds are at risk.

require_relative 'lib/hyperliquid'
require 'json'

WAIT_SECONDS = 10
SPOT_SLIPPAGE = 0.40  # 40% for illiquid testnet spot markets
PERP_SLIPPAGE = 0.05  # 5% for perp markets

def separator(title)
  puts
  puts '=' * 60
  puts title
  puts '=' * 60
  puts
end

def wait_with_countdown(seconds, message)
  puts message
  seconds.downto(1) do |i|
    print "\r  #{i} seconds remaining...  "
    sleep 1
  end
  puts "\r  Done!                      "
  puts
end

def check_result(result, operation)
  status = result.dig('response', 'data', 'statuses', 0)

  if status.is_a?(Hash) && status['error']
    puts "FAILED: #{status['error']}"
    return false
  end

  if status.is_a?(Hash) && status['resting']
    puts "Order resting with OID: #{status['resting']['oid']}"
    return status['resting']['oid']
  end

  if status == 'success' || (status.is_a?(Hash) && status['filled'])
    puts "#{operation} successful!"
    return true
  end

  puts "Result: #{status.inspect}"
  true
end

# --- Main Script ---

private_key = ENV['HYPERLIQUID_PRIVATE_KEY']
unless private_key
  puts 'Error: Set HYPERLIQUID_PRIVATE_KEY environment variable'
  puts 'Usage: HYPERLIQUID_PRIVATE_KEY=0x... ruby test_integration.rb'
  exit 1
end

sdk = Hyperliquid.new(
  testnet: true,
  private_key: private_key
)

puts 'Hyperliquid Ruby SDK - Testnet Integration Test'
puts '=' * 60
puts "Wallet: #{sdk.exchange.address}"
puts 'Network: Testnet'
puts "Testnet UI: https://app.hyperliquid-testnet.xyz"

# ============================================================
# TEST 1: Spot Market Roundtrip (PURR/USDC)
# ============================================================
separator('TEST 1: Spot Market Roundtrip (PURR/USDC)')

spot_coin = 'PURR/USDC'
spot_size = 5  # PURR has 0 decimals

mids = sdk.info.all_mids
spot_price = mids[spot_coin]&.to_f

if spot_price&.positive?
  puts "#{spot_coin} mid: $#{spot_price}"
  puts "Size: #{spot_size} PURR (~$#{(spot_size * spot_price).round(2)})"
  puts "Slippage: #{(SPOT_SLIPPAGE * 100).to_i}%"
  puts

  # Buy
  puts 'Placing market BUY...'
  result = sdk.exchange.market_order(
    coin: spot_coin,
    is_buy: true,
    size: spot_size,
    slippage: SPOT_SLIPPAGE
  )
  check_result(result, 'Buy')

  wait_with_countdown(WAIT_SECONDS, 'Waiting before sell...')

  # Sell
  puts 'Placing market SELL...'
  result = sdk.exchange.market_order(
    coin: spot_coin,
    is_buy: false,
    size: spot_size,
    slippage: SPOT_SLIPPAGE
  )
  check_result(result, 'Sell')
else
  puts "SKIPPED: Could not get #{spot_coin} price"
end

# ============================================================
# TEST 2: Spot Limit Order (Place and Cancel)
# ============================================================
separator('TEST 2: Spot Limit Order (Place and Cancel)')

if spot_price&.positive?
  # Place limit buy well below market (won't fill)
  limit_price = (spot_price * 0.50).round(2)  # 50% below mid
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
  puts "SKIPPED: Could not get #{spot_coin} price"
end

# ============================================================
# TEST 3: Perp Market Roundtrip (BTC Long)
# ============================================================
separator('TEST 3: Perp Market Roundtrip (BTC Long)')

perp_coin = 'BTC'
btc_price = mids[perp_coin]&.to_f

if btc_price&.positive?
  # Get BTC metadata for size precision
  meta = sdk.info.meta
  btc_meta = meta['universe'].find { |a| a['name'] == perp_coin }
  sz_decimals = btc_meta['szDecimals']

  # Calculate size for ~$20 notional
  perp_size = (20.0 / btc_price).ceil(sz_decimals)

  puts "#{perp_coin} mid: $#{btc_price.round(2)}"
  puts "Size: #{perp_size} BTC (~$#{(perp_size * btc_price).round(2)})"
  puts "Slippage: #{(PERP_SLIPPAGE * 100).to_i}%"
  puts

  # Open long
  puts 'Opening LONG position (market buy)...'
  result = sdk.exchange.market_order(
    coin: perp_coin,
    is_buy: true,
    size: perp_size,
    slippage: PERP_SLIPPAGE
  )
  check_result(result, 'Long open')

  wait_with_countdown(WAIT_SECONDS, 'Position open. Waiting before close...')

  # Close long (sell to close)
  puts 'Closing LONG position (market sell)...'
  result = sdk.exchange.market_order(
    coin: perp_coin,
    is_buy: false,
    size: perp_size,
    slippage: PERP_SLIPPAGE
  )
  check_result(result, 'Long close')
else
  puts "SKIPPED: Could not get #{perp_coin} price"
end

# ============================================================
# TEST 4: Perp Limit Order (Short, then Cancel)
# ============================================================
separator('TEST 4: Perp Limit Order (Short, then Cancel)')

if btc_price&.positive?
  # Place limit sell well above market (won't fill)
  limit_price = (btc_price * 1.50).round(0).to_i  # 50% above mid, whole number tick
  perp_size = (20.0 / btc_price).ceil(sz_decimals)

  puts "#{perp_coin} mid: $#{btc_price.round(2)}"
  puts "Limit price: $#{limit_price} (50% above mid - won't fill)"
  puts "Size: #{perp_size} BTC"
  puts

  puts 'Placing limit SELL order (short)...'
  result = sdk.exchange.order(
    coin: perp_coin,
    is_buy: false,
    size: perp_size,
    limit_px: limit_price,
    order_type: { limit: { tif: 'Gtc' } },
    reduce_only: false
  )
  oid = check_result(result, 'Limit short')

  if oid.is_a?(Integer)
    wait_with_countdown(WAIT_SECONDS, 'Order resting. Waiting before cancel...')

    puts "Canceling order #{oid}..."
    result = sdk.exchange.cancel(coin: perp_coin, oid: oid)
    check_result(result, 'Cancel')
  end
else
  puts "SKIPPED: Could not get #{perp_coin} price"
end

# ============================================================
# TEST 5: Update Leverage (BTC)
# ============================================================
separator('TEST 5: Update Leverage (BTC)')

if btc_price&.positive?
  puts 'Setting BTC to 5x cross leverage...'
  result = sdk.exchange.update_leverage(coin: perp_coin, leverage: 5, is_cross: true)
  puts "Result: #{result.inspect}"
  puts

  wait_with_countdown(WAIT_SECONDS, 'Waiting before next leverage update...')

  puts 'Setting BTC to 3x isolated leverage...'
  result = sdk.exchange.update_leverage(coin: perp_coin, leverage: 3, is_cross: false)
  puts "Result: #{result.inspect}"
  puts

  wait_with_countdown(WAIT_SECONDS, 'Waiting before resetting leverage...')

  puts 'Resetting BTC to 1x cross leverage...'
  result = sdk.exchange.update_leverage(coin: perp_coin, leverage: 1, is_cross: true)
  puts "Result: #{result.inspect}"
else
  puts "SKIPPED: Could not get #{perp_coin} price"
end

# ============================================================
# TEST 6: Modify Order (BTC)
# ============================================================
separator('TEST 6: Modify Order (BTC)')

if btc_price&.positive?
  # Place limit buy well below market (won't fill)
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
    puts "Modify result: #{result.inspect}"
    puts

    # Extract new oid from modify result if available
    new_status = result.dig('response', 'data', 'statuses', 0)
    new_oid = if new_status.is_a?(Hash) && new_status['resting']
                new_status['resting']['oid']
              else
                oid
              end

    wait_with_countdown(WAIT_SECONDS, 'Waiting before cancel...')

    puts "Canceling modified order #{new_oid}..."
    result = sdk.exchange.cancel(coin: perp_coin, oid: new_oid)
    check_result(result, 'Cancel')
  end
else
  puts "SKIPPED: Could not get #{perp_coin} price"
end

# ============================================================
# TEST 7: Market Close (BTC)
# ============================================================
separator('TEST 7: Market Close (BTC)')

if btc_price&.positive?
  perp_size = (20.0 / btc_price).ceil(sz_decimals)

  puts "#{perp_coin} mid: $#{btc_price.round(2)}"
  puts "Size: #{perp_size} BTC"
  puts

  # Open a small long position
  puts 'Opening LONG position (market buy)...'
  result = sdk.exchange.market_order(
    coin: perp_coin,
    is_buy: true,
    size: perp_size,
    slippage: PERP_SLIPPAGE
  )
  check_result(result, 'Long open')

  wait_with_countdown(WAIT_SECONDS, 'Position open. Waiting before market_close...')

  # Close using market_close (auto-detect size)
  puts 'Closing position using market_close (auto-detect size)...'
  result = sdk.exchange.market_close(
    coin: perp_coin,
    slippage: PERP_SLIPPAGE
  )
  check_result(result, 'Market close')
else
  puts "SKIPPED: Could not get #{perp_coin} price"
end

# ============================================================
# Summary
# ============================================================
separator('INTEGRATION TEST COMPLETE')
puts 'All tests executed. Check your testnet wallet for trade history:'
puts 'https://app.hyperliquid-testnet.xyz'
puts
