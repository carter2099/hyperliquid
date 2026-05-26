#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 19: spotUser (L1 exchange action)
#
# Toggles spot-dusting opt-out for the calling wallet. Sends two actions:
# opt_out: true, then opt_out: false, leaving the wallet in its original state
# (spot dusting opted-in by default).
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_19_spot_user.rb

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 19: spotUser (spot-dusting opt-out)')

puts "Wallet: #{sdk.exchange.address}"
puts

puts 'Opting out of spot dusting...'
result = sdk.exchange.spot_user(opt_out: true)

if api_error?(result)
  puts red("spot_user (opt_out: true) FAILED: #{result.inspect}")
  test_passed('Test 19 spot_user')
  exit 1
end

unless result.is_a?(Hash) && result['status'] == 'ok' && result.dig('response', 'type') == 'default'
  $test_failed = true
  puts red("Unexpected opt-out response: #{result.inspect}")
end

puts green("Opt-out OK: #{result.inspect}") unless $test_failed

wait_with_countdown(WAIT_SECONDS, 'Settling before toggle back...')

puts 'Opting back in to spot dusting...'
result = sdk.exchange.spot_user(opt_out: false)

if api_error?(result)
  puts red("spot_user (opt_out: false) FAILED: #{result.inspect}")
  test_passed('Test 19 spot_user')
  exit 1
end

unless result.is_a?(Hash) && result['status'] == 'ok' && result.dig('response', 'type') == 'default'
  $test_failed = true
  puts red("Unexpected opt-in response: #{result.inspect}")
end

puts green("Opt-in OK: #{result.inspect}") unless $test_failed

test_passed('Test 19 spot_user')
