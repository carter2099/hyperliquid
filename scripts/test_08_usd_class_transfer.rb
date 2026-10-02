#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 8: USD Class Transfer (Perp <-> Spot)
# Transfer $10 from perp to spot, then back (standard abstraction; needs perp
# withdrawable >= $10). If the wallet is unifiedAccount, sends the transfer and
# passes only on the exact "Action disabled when unified account is active"
# rejection (signature-proving wire check).
# Wallet preconditions: ruby scripts/testnet_wallet_check.rb [--fix]

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 8: USD Class Transfer (Perp <-> Spot)')

addr = sdk.exchange.address
abstraction = sdk.info.user_abstraction(addr)
if abstraction == 'unifiedAccount'
  # Wire check: the server can only say "unified account is active" after
  # recovering the signer to *our* unified account, so this proves the
  # user-signed signature end-to-end. Remediate with testnet_wallet_check.rb --fix.
  puts "Wallet is unifiedAccount — expecting structured rejection..."
  result = sdk.exchange.usd_class_transfer(amount: '10', to_perp: false)
  if result.is_a?(Hash) && result['status'] == 'err' &&
     result['response'].to_s.include?('Action disabled when unified account is active')
    puts red("WARNING: #{result['response']}")
    puts '  Wire check passed (signature recovered to this unified account).'
    puts '  Full round-trip needs standard mode: ruby scripts/testnet_wallet_check.rb --fix'
    test_passed('Test 8 USD Class Transfer')
    exit 0
  end
  # Server accepted it: semantics changed — undo and fall through to a pass with a note.
  unless api_error?(result)
    sdk.exchange.usd_class_transfer(amount: '10', to_perp: true)
    puts red('NOTE: unified wallet accepted usdClassTransfer; update the failures table.')
  end
  test_passed('Test 8 USD Class Transfer')
  exit($test_failed ? 1 : 0)
end

withdrawable = sdk.info.user_state(addr)['withdrawable'].to_f
if withdrawable < 10
  $test_failed = true
  puts red("FAILED: perp withdrawable $#{format('%.2f', withdrawable)} < $10. Run testnet_wallet_check.rb --fix")
  test_passed('Test 8 USD Class Transfer')
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
