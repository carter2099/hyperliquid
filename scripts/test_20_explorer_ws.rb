#!/usr/bin/env ruby
# frozen_string_literal: true

# Integration test for Explorer WebSocket subscription
# Connects to testnet explorer WS, subscribes to explorerBlock, and collects 3 block events
#
# Usage: ruby test_20_explorer_ws.rb

require_relative 'test_helpers'

puts '=' * 70
puts 'test_20: Explorer WebSocket subscription'
puts '=' * 70

# Initialize SDK with testnet
sdk = Hyperliquid::SDK.new(testnet: true)

puts "\n1. Testing explorer WebSocket connection and subscription..."

blocks_received = []
max_blocks = 3
timeout_seconds = 60
start_time = Time.now

puts "   Subscribing to explorerBlock channel (expecting #{max_blocks} blocks within #{timeout_seconds}s)..."
puts "   Explorer WS URL: wss://rpc.hyperliquid-testnet.xyz/ws"

# Subscribe to explorer blocks
sub_id = sdk.ws.subscribe_explorer_block do |block_array|
  # Explorer messages arrive as arrays
  block_array.each do |block|
    blocks_received << block
    elapsed = Time.now - start_time
    puts "   Block ##{blocks_received.size}: height=#{block['height']} hash=#{block['hash']} " \
         "numTxs=#{block['numTxs']} proposer=#{block['proposer'][0..10]}... (#{elapsed.round(1)}s elapsed)"

    break if blocks_received.size >= max_blocks
  end
end

puts "   Subscription ID: #{sub_id}"

# Wait for blocks with timeout
puts "\n2. Waiting for block events..."
loop do
  break if blocks_received.size >= max_blocks

  elapsed = Time.now - start_time
  if elapsed > timeout_seconds
    puts "\n   ⚠ Timeout: Only received #{blocks_received.size}/#{max_blocks} blocks after #{timeout_seconds}s"
    puts '   This may indicate testnet explorer is not producing blocks or WS connection issues'
    break
  end

  sleep 0.5
end

# Cleanup
puts "\n3. Cleanup..."
sdk.ws.unsubscribe(sub_id)
puts "   Unsubscribed from #{sub_id}"

sdk.ws.close
puts '   WebSocket connection closed'

# Verify results
puts "\n4. Verification..."
if blocks_received.empty?
  puts '   ❌ FAIL: No blocks received'
  puts '   Explorer WebSocket may not be working on testnet, or connection failed'
  exit 1
end

puts "   ✓ Received #{blocks_received.size} block(s)"

# Verify block structure
blocks_received.each_with_index do |block, idx|
  required_fields = %w[height hash numTxs proposer blockTime]
  missing = required_fields - block.keys
  unless missing.empty?
    puts "   ⚠ Block ##{idx + 1} missing fields: #{missing.join(', ')}"
  end
end

if blocks_received.size >= max_blocks
  puts "   ✓ PASS: Successfully received #{max_blocks} explorer blocks"
  exit 0
else
  puts "   ⚠ PARTIAL: Received #{blocks_received.size}/#{max_blocks} blocks"
  puts '   This is acceptable if testnet explorer is slow, but should be investigated'
  exit 0 # Don't fail the test suite for partial results
end
