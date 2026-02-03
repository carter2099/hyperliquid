#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 13: WebSocket l2Book Subscription
#
# Subscribes to ETH perp l2Book on testnet, prints 3 updates
# with top-of-book (best bid/ask), then cleanly disconnects.
#
# No private key required (read-only WebSocket).
#
# Usage:
#   ruby scripts/test_13_ws_l2_book.rb

require_relative '../lib/hyperliquid'

def green(text)
  "\e[32m#{text}\e[0m"
end

def red(text)
  "\e[31m#{text}\e[0m"
end

puts
puts '=' * 60
puts 'TEST 13: WebSocket l2Book Subscription'
puts '=' * 60
puts
puts 'Network: Testnet'
puts 'Subscribing to ETH l2Book (3 updates, then disconnect)'
puts

sdk = Hyperliquid.new(testnet: true)
updates = []
mutex = Mutex.new
done = ConditionVariable.new

sdk.ws.on(:open) { puts 'WebSocket connected.' }
sdk.ws.on(:error) { |e| puts red("WebSocket error: #{e}") }

sdk.ws.subscribe({ type: 'l2Book', coin: 'ETH' }) do |data|
  mutex.synchronize do
    next if updates.length >= 3

    levels = data['levels']
    bids = levels&.dig(0) || []
    asks = levels&.dig(1) || []
    best_bid = bids.first
    best_ask = asks.first

    update_num = updates.length + 1
    puts "Update #{update_num}/3:"
    puts "  Best bid: #{best_bid ? "#{best_bid['px']} (#{best_bid['sz']})" : 'n/a'}"
    puts "  Best ask: #{best_ask ? "#{best_ask['px']} (#{best_ask['sz']})" : 'n/a'}"
    puts "  Bid levels: #{bids.length}, Ask levels: #{asks.length}"
    puts

    updates << data
    done.signal if updates.length >= 3
  end
end

# Wait for 3 updates or timeout after 30 seconds
success = false
mutex.synchronize do
  deadline = Time.now + 30
  while updates.length < 3 && Time.now < deadline
    remaining = deadline - Time.now
    break if remaining <= 0

    done.wait(mutex, remaining)
  end
  success = updates.length >= 3
end

sdk.ws.close

if success
  puts green('Test 13 WebSocket l2Book passed!')
else
  puts red("Test 13 FAILED: only received #{updates.length}/3 updates within 30s")
  exit 1
end
