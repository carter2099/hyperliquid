#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 14: WebSocket candle Subscription
#
# Opens three concurrent candle subscriptions on testnet — ETH/1m, ETH/15m
# (same coin, different interval) and BTC/1m (different coin) — and checks
# that every message carries all candle keys and is routed to the matching
# coin/interval callback. Passes once ETH/1m has delivered 2 updates and
# ETH/15m at least 1 within 120 s (BTC/1m count is informational).
#
# Candle pushes are trade-driven (no snapshot on subscribe). On timeout the
# script asks Info#recent_trades('ETH') whether ETH trades landed during the
# window: trades occurred but too few candle updates -> FAIL; no testnet ETH
# trade flow -> INCONCLUSIVE (exit 0, marked line).
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

REQUIRED_ETH_1M = 2
TIMEOUT = 120
SUBS = [%w[ETH 1m], %w[ETH 15m], %w[BTC 1m]].freeze
CANDLE_KEYS = %w[t T s i o c h l v n].freeze

puts
puts '=' * 60
puts 'TEST 14: WebSocket candle Subscription'
puts '=' * 60
puts
puts 'Network: Testnet'
puts "Subscribing to #{SUBS.map { |c, i| "#{c}/#{i}" }.join(', ')} candles"
puts "(need #{REQUIRED_ETH_1M} ETH/1m + 1 ETH/15m updates within #{TIMEOUT}s)"
puts

sdk = Hyperliquid.new(testnet: true)
received = Hash.new { |h, k| h[k] = [] }
routing_errors = []
mutex = Mutex.new
done = ConditionVariable.new
opened_at_ms = nil

sdk.ws.on(:open) do
  mutex.synchronize { opened_at_ms ||= (Time.now.to_f * 1000).to_i }
  puts 'WebSocket connected.'
end
sdk.ws.on(:error) { |e| puts red("WebSocket error: #{e}") }

SUBS.each do |coin, interval|
  sdk.ws.subscribe({ type: 'candle', coin: coin, interval: interval }) do |data|
    mutex.synchronize do
      key = "#{coin}/#{interval}"
      missing = CANDLE_KEYS.reject { |k| data.is_a?(Hash) && data.key?(k) }
      if missing.any? || data['s'] != coin || data['i'] != interval
        s = data.is_a?(Hash) ? data['s'] : nil
        i = data.is_a?(Hash) ? data['i'] : nil
        routing_errors << "#{key} got s=#{s.inspect} i=#{i.inspect} missing=#{missing}"
      else
        received[key] << data
        puts "#{key} update #{received[key].length}: o=#{data['o']} c=#{data['c']} v=#{data['v']} n=#{data['n']}"
      end
      done.signal
    end
  end
end

satisfied = -> { received['ETH/1m'].length >= REQUIRED_ETH_1M && received['ETH/15m'].length >= 1 }
deadline = Time.now + TIMEOUT
mutex.synchronize do
  done.wait(mutex, [deadline - Time.now, 0.1].max) while !satisfied.call && routing_errors.empty? && Time.now < deadline
end
sleep 2 # drain: ETH/15m arrives with the same trade as ETH/1m
sdk.ws.close

counts = SUBS.map { |c, i| "#{c}/#{i}=#{received["#{c}/#{i}"].length}" }.join(' ')
puts
puts "Updates received: #{counts}"

if routing_errors.any?
  routing_errors.each { |e| puts red("Routing error: #{e}") }
  puts red('Test 14 FAILED: candle message routed to the wrong subscription or missing keys')
  exit 1
end

if satisfied.call
  puts green('Test 14 WebSocket candle passed!')
  exit 0
end

if received['ETH/1m'].length >= 1 && received['ETH/15m'].empty?
  puts red('Test 14 FAILED: same-coin second interval not routed (ETH/1m updated, ETH/15m did not)')
  exit 1
end

if opened_at_ms.nil?
  puts red('Test 14 FAILED: WebSocket never opened')
  exit 1
end

window_start = opened_at_ms + 1000
window_end = (deadline.to_f * 1000).to_i
blocks = sdk.info.recent_trades('ETH').map { |t| t['time'] }
            .select { |t| t >= window_start && t <= window_end - 1000 }.uniq.size
eth_updates = received['ETH/1m'].length

if eth_updates < [blocks, REQUIRED_ETH_1M].min
  puts red("Test 14 FAILED: #{blocks} ETH trade blocks on testnet during the window " \
           "but only #{eth_updates} candle updates")
  exit 1
end

puts "\e[33mINCONCLUSIVE: only #{blocks} ETH trade block(s) on testnet in #{TIMEOUT}s — no trade flow to observe\e[0m"
exit 0
