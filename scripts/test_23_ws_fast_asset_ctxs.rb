#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 23: WebSocket fastAssetCtxs Subscription (compressed channel)
#
# Subscribes to fastAssetCtxs on testnet. The server sends each frame's `data`
# as base64 + raw DEFLATE JSON; WS::Client decodes it before dispatch. Collects
# 3 frames: the first is a full snapshot (every listed coin), later frames carry
# only changed coins/fields. Then cleanly disconnects.
#
# No private key required (read-only WebSocket).
#
# Usage:
#   ruby scripts/test_23_ws_fast_asset_ctxs.rb

require_relative 'test_helpers'

NAME = 'Test 23 WebSocket fastAssetCtxs'

def valid_ctxs?(frame)
  frame.is_a?(Hash) && !frame.empty? && frame.all? do |coin, ctx|
    coin.is_a?(String) && ctx.is_a?(Hash) && !ctx.empty? &&
      (ctx.keys - %w[markPx midPx]).empty? &&
      ctx.values.all? { |v| v.nil? || v.match?(/\A[0-9]+(\.[0-9]+)?\z/) }
  end
end

separator('TEST 23: WebSocket fastAssetCtxs Subscription')

sdk = build_public_sdk
puts 'Subscribing to fastAssetCtxs (3 frames, then disconnect)'
puts

frames = []
mutex = Mutex.new
done = ConditionVariable.new

sdk.ws.on(:open) { puts 'WebSocket connected.' }
sdk.ws.on(:error) { |e| puts red("WebSocket error: #{e}") }

sdk.ws.subscribe({ type: 'fastAssetCtxs' }) do |data|
  mutex.synchronize do
    next if frames.length >= 3

    label = frames.empty? ? 'snapshot' : 'update'
    sample = data.is_a?(Hash) ? data.first(2).to_h : data
    puts "Frame #{frames.length + 1}/3 (#{label}): #{data.is_a?(Hash) ? data.size : '?'} coin(s), sample #{sample}"
    frames << data
    done.signal if frames.length >= 3
  end
end

mutex.synchronize do
  deadline = Time.now + 30
  while frames.length < 3
    remaining = deadline - Time.now
    break if remaining <= 0

    done.wait(mutex, remaining)
  end
end

sdk.ws.close

fail!("received #{frames.length}/3 frames within 30s") if frames.length < 3
fail!('a frame was not a coin => {markPx, midPx} Hash') unless frames.all? { |f| valid_ctxs?(f) }
snapshot = frames.first.is_a?(Hash) ? frames.first : {}
fail!("snapshot too small (#{snapshot.size} coins)") if snapshot.size < 100
fail!('snapshot missing BTC markPx') unless snapshot.dig('BTC', 'markPx')

test_passed(NAME)
