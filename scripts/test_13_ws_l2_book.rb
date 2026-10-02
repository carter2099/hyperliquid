#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 13: WebSocket l2Book Subscription
#
# Subscribes to ETH perp l2Book on testnet and needs 3 updates within 30 s,
# each for coin ETH with at least one bid and one ask level carrying px/sz;
# a malformed update FAILS. Prints top-of-book, then cleanly disconnects.
#
# No private key required (read-only WebSocket).
#
# Usage:
#   ruby scripts/test_13_ws_l2_book.rb

require_relative 'test_helpers'

TEST_NAME = 'Test 13 WebSocket l2Book'
REQUIRED_UPDATES = 3
TIMEOUT = 30

# Returns nil when the update is well-formed, else a description of the problem.
def l2_problem(data)
  return "not a Hash: #{data.inspect}" unless data.is_a?(Hash)
  return "coin #{data['coin'].inspect} != \"ETH\"" unless data['coin'] == 'ETH'

  levels = data['levels']
  return "levels is not [bids, asks]: #{levels.inspect}" unless levels.is_a?(Array) && levels.length == 2

  %w[bids asks].zip(levels).each do |side, entries|
    return "no #{side}" unless entries.is_a?(Array) && !entries.empty?
    return "malformed #{side} level: #{entries.first.inspect}" unless entries.first.is_a?(Hash) && entries.first['px'] && entries.first['sz']
  end
  nil
end

sdk = build_public_sdk
separator('TEST 13: WebSocket l2Book Subscription')
puts "Subscribing to ETH l2Book (#{REQUIRED_UPDATES} updates, then disconnect)"
puts

updates = []
problems = []
mutex = Mutex.new
done = ConditionVariable.new

sdk.ws.on(:open) { puts 'WebSocket connected.' }
sdk.ws.on(:error) { |e| puts red("WebSocket error: #{e}") }

sdk.ws.subscribe({ type: 'l2Book', coin: 'ETH' }) do |data|
  mutex.synchronize do
    next if updates.length >= REQUIRED_UPDATES || problems.any?

    problem = l2_problem(data)
    if problem
      problems << problem
    else
      bids, asks = data['levels']
      puts "Update #{updates.length + 1}/#{REQUIRED_UPDATES}:"
      puts "  Best bid: #{bids.first['px']} (#{bids.first['sz']})"
      puts "  Best ask: #{asks.first['px']} (#{asks.first['sz']})"
      puts "  Bid levels: #{bids.length}, Ask levels: #{asks.length}"
      puts
      updates << data
    end
    done.signal
  end
end

mutex.synchronize do
  deadline = Time.now + TIMEOUT
  while updates.length < REQUIRED_UPDATES && problems.empty?
    remaining = deadline - Time.now
    break if remaining <= 0

    done.wait(mutex, remaining)
  end
end

sdk.ws.close

if problems.any?
  fail!("malformed l2Book update: #{problems.first}")
elsif updates.length < REQUIRED_UPDATES
  fail!("only received #{updates.length}/#{REQUIRED_UPDATES} updates within #{TIMEOUT}s")
end

test_passed(TEST_NAME)
