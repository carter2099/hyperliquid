#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 5: Update Leverage (BTC)
# Set 5x cross, 3x isolated, then reset to 1x cross. Each update must return
# status ok AND be read back from Info#active_asset_data (type + value).
# Requires a flat BTC book (cannot switch leverage type with an open position);
# a leftover position/order FAILS (fix with testnet_wallet_check.rb --fix).
# `ensure` resets BTC to 1x cross if the script changed it and the reset did
# not complete.

require_relative 'test_helpers'

TEST_NAME = 'Test 5 Update Leverage'
PERP_COIN = 'BTC'

# Sends update_leverage and reads it back. Returns true when both agree.
def set_leverage!(sdk, leverage, is_cross)
  want = { 'type' => is_cross ? 'cross' : 'isolated', 'value' => leverage }
  label = "#{leverage}x #{want['type']}"
  puts "Setting #{PERP_COIN} to #{label} leverage..."
  result = sdk.exchange.update_leverage(coin: PERP_COIN, leverage: leverage, is_cross: is_cross)
  dump_status(result)
  unless result.is_a?(Hash) && result['status'] == 'ok'
    fail!("update_leverage #{label}: expected status ok, got #{result.inspect}")
    return false
  end

  got = nil
  5.times do |i|
    got = sdk.info.active_asset_data(sdk.exchange.address, PERP_COIN)['leverage']
    break if got.is_a?(Hash) && got.slice('type', 'value') == want

    sleep 1 unless i == 4
  end
  if got.is_a?(Hash) && got.slice('type', 'value') == want
    puts green("#{label} leverage set and read back: #{got.inspect}")
    true
  else
    fail!("update_leverage #{label}: active_asset_data reports #{got.inspect}")
    false
  end
end

def run(sdk, state)
  state[:dirty] = true
  return unless set_leverage!(sdk, 5, true)

  puts
  wait_with_countdown(WAIT_SECONDS, 'Waiting before next leverage update...')

  return unless set_leverage!(sdk, 3, false)

  puts
  wait_with_countdown(WAIT_SECONDS, 'Waiting before resetting leverage...')

  state[:dirty] = false if set_leverage!(sdk, 1, true)
end

# Restores the 1x cross baseline. Reports, never raises.
def reset_leverage(sdk)
  puts "Cleanup: resetting #{PERP_COIN} to 1x cross..."
  result = sdk.exchange.update_leverage(coin: PERP_COIN, leverage: 1, is_cross: true)
  fail!("Cleanup: leverage reset failed: #{result.inspect}") unless result.is_a?(Hash) && result['status'] == 'ok'
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

sdk = build_sdk
separator('TEST 5: Update Leverage (BTC)')

require_flat!(sdk, PERP_COIN)
test_passed(TEST_NAME) if $test_failed

state = { dirty: false }
begin
  run(sdk, state)
ensure
  reset_leverage(sdk) if state[:dirty]
end

test_passed(TEST_NAME)
