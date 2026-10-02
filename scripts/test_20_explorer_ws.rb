#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 20: Explorer WebSocket subscription
#
# Connects to the testnet explorer WS, subscribes to explorerBlock, and collects 3 block
# events within 60 s. Every block must carry height/hash/numTxs/proposer/blockTime.
#   3 blocks          -> PASS
#   1-2 blocks        -> INCONCLUSIVE (the WS path works; testnet explorer was slow)
#   0 blocks          -> FAIL
#
# No private key required (read-only WebSocket).
#
# Usage:
#   ruby scripts/test_20_explorer_ws.rb

require_relative 'test_helpers'

NAME = 'Test 20 explorer WebSocket'
MAX_BLOCKS = 3
TIMEOUT_SECONDS = 60
REQUIRED_FIELDS = %w[height hash numTxs proposer blockTime].freeze

separator('TEST 20: Explorer WebSocket subscription')

sdk = build_public_sdk

puts '1. Testing explorer WebSocket connection and subscription...'

blocks_received = []
mutex = Mutex.new
start_time = Time.now

puts "   Subscribing to explorerBlock channel (expecting #{MAX_BLOCKS} blocks within #{TIMEOUT_SECONDS}s)..."

# Explorer messages arrive as arrays of blocks
sub_id = sdk.ws.subscribe_explorer_block do |block_array|
  (block_array.is_a?(Array) ? block_array : [block_array]).each do |block|
    count = mutex.synchronize do
      next nil if blocks_received.size >= MAX_BLOCKS

      blocks_received << block
      blocks_received.size
    end
    break unless count

    summary = block.is_a?(Hash) ? "height=#{block['height']} hash=#{block['hash']} numTxs=#{block['numTxs']}" : block.inspect
    puts "   Block ##{count}: #{summary} (#{(Time.now - start_time).round(1)}s elapsed)"
  end
end

puts "   Subscription ID: #{sub_id}"

puts '2. Waiting for block events...'
loop do
  break if mutex.synchronize { blocks_received.size } >= MAX_BLOCKS
  break if Time.now - start_time > TIMEOUT_SECONDS

  sleep 0.5
end

puts '3. Cleanup...'
sdk.ws.unsubscribe(sub_id)
sdk.ws.close
puts '   WebSocket connection closed'

puts '4. Verification...'
blocks = mutex.synchronize { blocks_received.dup }

if blocks.empty?
  fail!("No explorer blocks received within #{TIMEOUT_SECONDS}s (explorer WS connection or subscription broken)")
  test_passed(NAME)
end

blocks.each_with_index do |block, idx|
  unless block.is_a?(Hash)
    fail!("Block ##{idx + 1} is not a Hash: #{block.inspect}")
    next
  end
  missing = REQUIRED_FIELDS - block.keys
  fail!("Block ##{idx + 1} missing fields: #{missing.join(', ')}") unless missing.empty?
end

if blocks.size < MAX_BLOCKS
  finish_inconclusive(NAME, "received #{blocks.size}/#{MAX_BLOCKS} explorer blocks within #{TIMEOUT_SECONDS}s")
end

puts green("   Received #{MAX_BLOCKS} well-formed explorer blocks")
test_passed(NAME)
