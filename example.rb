#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/hyperliquid'

# Example usage of the Hyperliquid Ruby SDK

puts 'Hyperliquid Ruby SDK v0.4.0 - API Examples'
puts '=' * 50

# =============================================================================
# INFO API (Read-only, no authentication required)
# =============================================================================

# Create a new SDK instance (defaults to mainnet)
sdk = Hyperliquid.new

puts "\n--- INFO API EXAMPLES ---\n"

# Example 1: Get all market mid prices
begin
  puts '1. Getting all market mid prices...'
  mids = sdk.info.all_mids
  puts "   Found #{mids.length} markets" if mids.is_a?(Hash)
  puts "   BTC mid: #{mids['BTC']}" if mids['BTC']
rescue Hyperliquid::Error => e
  puts "   Error: #{e.message}"
end

# Example 2: Get metadata for all perpetual assets
begin
  puts "\n2. Getting perpetual asset metadata..."
  meta = sdk.info.meta
  universe = meta['universe'] || []
  puts "   Found #{universe.length} perpetual assets"
  puts "   First asset: #{universe.first['name']}" if universe.any?
rescue Hyperliquid::Error => e
  puts "   Error: #{e.message}"
end

# Example 3: Get L2 order book
begin
  puts "\n3. Getting L2 order book for BTC..."
  book = sdk.info.l2_book('BTC')
  levels = book['levels'] || []
  puts "   Bid levels: #{levels[0]&.length || 0}, Ask levels: #{levels[1]&.length || 0}"
rescue Hyperliquid::Error => e
  puts "   Error: #{e.message}"
end

# Example 4: Get spot metadata
begin
  puts "\n4. Getting spot asset metadata..."
  spot_meta = sdk.info.spot_meta
  tokens = spot_meta['tokens'] || []
  puts "   Found #{tokens.length} spot tokens"
rescue Hyperliquid::Error => e
  puts "   Error: #{e.message}"
end

# Example 5: Use testnet
puts "\n5. Creating testnet SDK..."
testnet_sdk = Hyperliquid.new(testnet: true)
puts "   Testnet base URL: #{testnet_sdk.base_url}"

# Example 6: User-specific endpoints (requires valid wallet address)
wallet_address = "0x#{'0' * 40}" # Placeholder address

begin
  puts "\n6. Getting user state for #{wallet_address[0..13]}..."
  state = sdk.info.user_state(wallet_address)
  puts "   Account value: #{state.dig('marginSummary', 'accountValue') || 'N/A'}"
rescue Hyperliquid::Error => e
  puts "   Error: #{e.message}"
end

# =============================================================================
# EXCHANGE API (Authenticated, requires private key)
# =============================================================================

puts "\n--- EXCHANGE API EXAMPLES ---\n"
puts "(These examples are commented out to prevent accidental execution)\n"

# To use the Exchange API, create an SDK with your private key:
#
#   sdk = Hyperliquid.new(
#     testnet: true,  # Use testnet for testing!
#     private_key: ENV['HYPERLIQUID_PRIVATE_KEY']
#   )
#
# Your wallet address:
#   puts sdk.exchange.address
#
# Place a limit order:
#   result = sdk.exchange.order(
#     coin: 'BTC',
#     is_buy: true,
#     size: 0.001,
#     limit_px: 50000.0,
#     order_type: { limit: { tif: 'Gtc' } },
#     reduce_only: false
#   )
#
# Place a market order (uses slippage):
#   result = sdk.exchange.market_order(
#     coin: 'BTC',
#     is_buy: true,
#     size: 0.001,
#     slippage: 0.01  # 1% slippage
#   )
#
# Place a stop loss order:
#   result = sdk.exchange.order(
#     coin: 'BTC',
#     is_buy: false,
#     size: 0.001,
#     limit_px: 48000.0,
#     order_type: {
#       trigger: {
#         trigger_px: 49000.0,
#         is_market: false,
#         tpsl: 'sl'
#       }
#     },
#     reduce_only: true
#   )
#
# Cancel an order by OID:
#   result = sdk.exchange.cancel(coin: 'BTC', oid: 123456789)
#
# Cancel an order by client order ID:
#   result = sdk.exchange.cancel_by_cloid(coin: 'BTC', cloid: '0x...')
#
# Bulk cancel multiple orders:
#   result = sdk.exchange.bulk_cancel([
#     { coin: 'BTC', oid: 123 },
#     { coin: 'ETH', oid: 456 }
#   ])
#
# Use client order IDs for tracking:
#   cloid = Hyperliquid::Cloid.random
#   result = sdk.exchange.order(
#     coin: 'BTC',
#     is_buy: true,
#     size: 0.001,
#     limit_px: 50000.0,
#     cloid: cloid
#   )
#   puts "Order placed with cloid: #{cloid}"
#
# Trade on behalf of a vault:
#   result = sdk.exchange.order(
#     coin: 'BTC',
#     is_buy: true,
#     size: 0.001,
#     limit_px: 50000.0,
#     vault_address: '0x...'
#   )

puts 'See commented code above for Exchange API usage patterns.'
puts "\nSDK examples completed!"
