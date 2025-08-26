#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/hyperliquid'

# Example usage of the Hyperliquid Ruby SDK

# Create a new SDK instance (defaults to mainnet)
sdk = Hyperliquid.new

puts 'Hyperliquid Ruby SDK v0.1 - Info API Examples'
puts '=' * 50

# Example 1: Get all market mid prices
begin
  puts "\n1. Getting all market mid prices..."
  mids = sdk.info.all_mids
  puts "Found #{mids.length} markets" if mids.is_a?(Hash)
rescue Hyperliquid::Error => e
  puts "Error getting market mids: #{e.message}"
end

# Example 2: Get metadata for all assets
begin
  puts "\n2. Getting asset metadata..."
  meta = sdk.info.meta
  puts 'Got metadata for universe' if meta.is_a?(Hash)
rescue Hyperliquid::Error => e
  puts "Error getting metadata: #{e.message}"
end

# Example 3: Use testnet
puts "\n3. Using testnet..."
testnet_sdk = Hyperliquid.new(testnet: true)
puts "Testnet SDK created, base URL: #{testnet_sdk.base_url}"

# Example 4: User-specific endpoints (requires valid wallet address)
wallet_address = "0x#{'0' * 40}" # Example placeholder address

begin
  puts "\n4. Getting open orders for wallet #{wallet_address[0..10]}..."
  orders = sdk.info.open_orders(wallet_address)
  puts "Open orders: #{orders}"
rescue Hyperliquid::Error => e
  puts "Error getting open orders: #{e.message}"
end

puts "\nSDK examples completed!"
puts "\nAvailable Info methods:"
puts '- all_mids() - Get all market mid prices'
puts "- open_orders(user) - Get user's open orders"
puts "- user_fills(user) - Get user's fill history"
puts '- order_status(user, oid) - Get order status'
puts "- user_state(user) - Get user's trading state"
puts '- meta() - Get asset metadata'
puts '- meta_and_asset_ctxs() - Get extended asset metadata'
puts '- l2_book(coin) - Get L2 order book'
puts '- candles_snapshot(coin, interval, start_time, end_time) - Get candlestick data'
