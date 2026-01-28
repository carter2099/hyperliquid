#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 8: USD Class Transfer (Perp <-> Spot)
# Transfer $10 from perp to spot, then back.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 8: USD Class Transfer (Perp <-> Spot)')

puts 'Transferring $10 from perp to spot...'
result = sdk.exchange.usd_class_transfer(amount: '10', to_perp: false)
api_error?(result) || puts(green('Transfer to spot successful!'))
puts

wait_with_countdown(WAIT_SECONDS, 'Waiting before transferring back...')

puts 'Transferring $10 from spot to perp...'
result = sdk.exchange.usd_class_transfer(amount: '10', to_perp: true)
api_error?(result) || puts(green('Transfer to perp successful!'))

test_passed('Test 8 USD Class Transfer')
