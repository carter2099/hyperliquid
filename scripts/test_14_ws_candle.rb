#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 14: WebSocket candle Subscription
#
# Subscribes to ETH 1m candles on testnet, prints 3 updates
# with OHLCV data, then cleanly disconnects.
#
# No private key required (read-only WebSocket).
#
# Usage:
#   ruby scripts/test_14_ws_candle.rb

require_relative '../lib/hyperliquid'

def green(text)
  "\e[32m#{text}\e[0m"
end

def red(text)
  "\e[31m#{text}\e[0m"
end

puts
puts '=' * 60
puts 'TEST 14: WebSocket candle Subscription'
puts '=' * 60
puts
puts 'Network: Testnet'
puts 'Subscribing to ETH 1m candles (3 updates, then disconnect)'
puts

sdk = Hyperliquid.new(testnet: true)
updates = []
mutex = Mutex.new
done = ConditionVariable.new

sdk.ws.on(:open) { puts 'WebSocket connected.' }
sdk.ws.on(:error) { |e| puts red("WebSocket error: #{e}") }

sdk.ws.subscribe({ type: 'candle', coin: 'ETH', interval: '1m' }) do |data|
  mutex.synchronize do
    next if updates.length >= 3

    update_num = updates.length + 1
    puts "Update #{update_num}/3:"
    puts "  Symbol:   #{data['s']}"
    puts "  Interval: #{data['i']}"
    puts "  Open:     #{data['o']}"
    puts "  High:     #{data['h']}"
    puts "  Low:      #{data['l']}"
    puts "  Close:    #{data['c']}"
    puts "  Volume:   #{data['v']}"
    puts

    updates << data
    done.signal if updates.length >= 3
  end
end

# Wait for 3 updates or timeout after 90 seconds (candles can be slow)
success = false
mutex.synchronize do
  deadline = Time.now + 90
  while updates.length < 3 && Time.now < deadline
    remaining = deadline - Time.now
    break if remaining <= 0

    done.wait(mutex, remaining)
  end
  success = updates.length >= 3
end

sdk.ws.close

if success
  puts green('Test 14 WebSocket candle passed!')
else
  puts red("Test 14 FAILED: only received #{updates.length}/3 updates within 90s")
  exit 1
end
