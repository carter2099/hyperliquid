#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 21: WebSocket Channel Parity
#
# Subscribes to every snapshot-delivering main-API channel added for TS/Python
# parity on testnet, and checks that each callback receives a message carrying
# its own routing fields (user / dex / coin) and nothing else. Also checks the
# local exclusivity guard: a second user on orderUpdates raises WebSocketError.
#
# No private key required (read-only WebSocket, public addresses).
#
# Usage:
#   ruby scripts/test_21_ws_channel_parity.rb

require_relative 'test_helpers'

NAME = 'Test 21 WebSocket channel parity'

# Any address works: snapshot channels deliver even for an empty account.
ADDR = '0xdfc24b077bc1425ad1dea75bcb6f8158e10df303'
TIMEOUT = 30

# [label, subscription, routing predicate on the callback's data]
CHECKS = [
  ['webData3', { type: 'webData3', user: ADDR }, ->(d) { d['userState']['user'] == ADDR }],
  ['userNonFundingLedgerUpdates', { type: 'userNonFundingLedgerUpdates', user: ADDR }, ->(d) { d['user'] == ADDR }],
  ['userTwapSliceFills', { type: 'userTwapSliceFills', user: ADDR }, ->(d) { d['user'] == ADDR }],
  ['userTwapHistory', { type: 'userTwapHistory', user: ADDR }, ->(d) { d['user'] == ADDR }],
  ['userHistoricalOrders', { type: 'userHistoricalOrders', user: ADDR }, ->(d) { d['user'] == ADDR }],
  ['allDexsClearinghouseState', { type: 'allDexsClearinghouseState', user: ADDR }, ->(d) { d['user'] == ADDR }],
  ['clearinghouseState (main dex)', { type: 'clearinghouseState', user: ADDR },
   ->(d) { d['user'] == ADDR && d['dex'] == '' }],
  ['clearinghouseState (xyz)', { type: 'clearinghouseState', user: ADDR, dex: 'xyz' }, ->(d) { d['dex'] == 'xyz' }],
  ['openOrders (main dex)', { type: 'openOrders', user: ADDR }, ->(d) { d['dex'] == '' }],
  ['twapStates (xyz)', { type: 'twapStates', user: ADDR, dex: 'xyz' }, ->(d) { d['dex'] == 'xyz' }],
  ['spotState', { type: 'spotState', user: ADDR }, ->(d) { d['user'] == ADDR }],
  ['activeAssetData BTC', { type: 'activeAssetData', user: ADDR, coin: 'BTC' },
   ->(d) { d['coin'] == 'BTC' && d['user'] == ADDR }],
  ['activeAssetCtx BTC', { type: 'activeAssetCtx', coin: 'BTC' }, ->(d) { d['coin'] == 'BTC' }],
  ['activeAssetCtx PURR/USDC', { type: 'activeAssetCtx', coin: 'PURR/USDC' }, ->(d) { d['coin'] == 'PURR/USDC' }],
  ['assetCtxs (main dex)', { type: 'assetCtxs' }, ->(d) { d['dex'] == '' }],
  ['assetCtxs (xyz)', { type: 'assetCtxs', dex: 'xyz' }, ->(d) { d['dex'] == 'xyz' }],
  ['allDexsAssetCtxs', { type: 'allDexsAssetCtxs' }, ->(d) { d['ctxs'].is_a?(Array) }],
  ['spotAssetCtxs', { type: 'spotAssetCtxs' }, ->(d) { d.is_a?(Array) }]
].freeze

def routing_summary(data)
  return "Array(#{data.length})" if data.is_a?(Array)
  return data.class.to_s unless data.is_a?(Hash)

  fields = %w[user dex coin].select { |k| data.key?(k) }.map { |k| "#{k}=#{data[k].inspect}" }
  fields << "userState.user=#{data['userState']['user'].inspect}" if data['userState'].is_a?(Hash)
  fields.empty? ? "keys=#{data.keys.first(4).join(',')}" : fields.join(' ')
end

separator('TEST 21: WebSocket Channel Parity')

sdk = build_public_sdk
puts "Subscribing to #{CHECKS.length} channels for #{ADDR}"
puts

received = {}
cross_deliveries = []
mutex = Mutex.new
done = ConditionVariable.new

sdk.ws.on(:open) { puts 'WebSocket connected.' }
sdk.ws.on(:error) { |e| puts red("WebSocket error: #{e}") }

CHECKS.each do |label, subscription, predicate|
  sdk.ws.subscribe(subscription) do |data|
    ok = begin
      predicate.call(data)
    rescue StandardError
      false
    end
    mutex.synchronize do
      if ok
        received[label] ||= routing_summary(data)
      else
        cross_deliveries << "#{label}: #{routing_summary(data)}"
      end
      done.signal if received.size >= CHECKS.length
    end
  end
end

# Local guard check (no network): orderUpdates messages carry no user, so a
# second user on the same client must be rejected.
guard_ok = false
sdk.ws.subscribe({ type: 'orderUpdates', user: ADDR }) { |_d| nil }
begin
  sdk.ws.subscribe({ type: 'orderUpdates', user: '0x0000000000000000000000000000000000000001' }) { |_d| nil }
rescue Hyperliquid::WebSocketError => e
  guard_ok = true
  puts "Exclusivity guard: #{e.message}"
  puts
end

mutex.synchronize do
  deadline = Time.now + TIMEOUT
  while received.size < CHECKS.length
    remaining = deadline - Time.now
    break if remaining <= 0

    done.wait(mutex, remaining)
  end
end

sdk.ws.close

CHECKS.each do |label, _subscription, _predicate|
  if received[label]
    puts green("✓ #{label} (#{received[label]})")
  else
    fail!("✗ #{label} (no matching message within #{TIMEOUT}s)")
  end
end
if guard_ok
  puts green('✓ orderUpdates exclusivity guard')
else
  fail!('✗ second-user orderUpdates subscription did not raise WebSocketError')
end
cross_deliveries.each { |c| fail!("cross-delivery #{c}") }

test_passed(NAME)
