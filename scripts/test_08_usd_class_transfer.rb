#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 8: USD Class Transfer (Perp <-> Spot)
# Transfer $10 from perp to spot, then back.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 8: USD Class Transfer (Perp <-> Spot)')

# Unified-account wallets cannot use usdClassTransfer — perp and spot balances
# are merged, so the action is disabled at the exchange layer. Detect this up
# front and skip rather than hitting a predictable "Action disabled" failure.
abstraction = sdk.info.user_abstraction(sdk.exchange.address)
if abstraction == 'unifiedAccount'
  puts "SKIPPED: Wallet has unified account active (abstraction=#{abstraction.inspect})."
  puts '  usdClassTransfer is disabled by the exchange when perp/spot balances are unified.'
  test_passed('Test 8 USD Class Transfer')
  exit 0
end

puts 'Transferring $10 from perp to spot...'
result = sdk.exchange.usd_class_transfer(amount: '10', to_perp: false)
dump_status(result)
api_error?(result) || puts(green('Transfer to spot successful!'))
puts

wait_with_countdown(WAIT_SECONDS, 'Waiting before transferring back...')

puts 'Transferring $10 from spot to perp...'
result = sdk.exchange.usd_class_transfer(amount: '10', to_perp: true)
dump_status(result)
api_error?(result) || puts(green('Transfer to perp successful!'))

test_passed('Test 8 USD Class Transfer')
