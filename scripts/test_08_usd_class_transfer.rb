#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 8: USD Class Transfer (Perp <-> Spot)
# Transfer $10 from perp to spot, then back (standard abstraction; needs perp
# withdrawable >= $10). Both transfers must return status ok. If the script
# moved $10 to spot and the transfer back never ran (error, exception,
# timeout), `ensure` transfers it back and reports any cleanup error.
#
# If the wallet is unifiedAccount, sends the transfer and reports GUARDED only
# on the exact "Action disabled when unified account is active" rejection
# (signature-proving wire check).
# Wallet preconditions: ruby scripts/testnet_wallet_check.rb [--fix]

require_relative 'test_helpers'

TEST_NAME = 'Test 8 USD Class Transfer'
UNIFIED_REJECTION = 'Action disabled when unified account is active'

def ok?(result, label)
  dump_status(result)
  if result.is_a?(Hash) && result['status'] == 'ok'
    puts green("#{label} successful!")
    true
  else
    fail!("#{label}: expected status ok, got #{result.inspect}")
    false
  end
end

def run(sdk, state)
  puts 'Transferring $10 from perp to spot...'
  result = sdk.exchange.usd_class_transfer(amount: '10', to_perp: false)
  state[:in_spot] = true if ok?(result, 'Transfer to spot')
  return unless state[:in_spot]

  puts
  wait_with_countdown(WAIT_SECONDS, 'Waiting before transferring back...')

  puts 'Transferring $10 from spot to perp...'
  result = sdk.exchange.usd_class_transfer(amount: '10', to_perp: true)
  state[:in_spot] = false
  ok?(result, 'Transfer to perp')
end

# Moves the $10 back to perp. Reports, never raises.
def transfer_back(sdk)
  puts 'Cleanup: transferring the $10 back from spot to perp...'
  result = sdk.exchange.usd_class_transfer(amount: '10', to_perp: true)
  fail!("Cleanup: transfer back failed: #{result.inspect}") unless result.is_a?(Hash) && result['status'] == 'ok'
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

sdk = build_sdk
separator('TEST 8: USD Class Transfer (Perp <-> Spot)')

addr = sdk.exchange.address
state = { in_spot: false }

if sdk.info.user_abstraction(addr) == 'unifiedAccount'
  # Wire check: the server can only say "unified account is active" after
  # recovering the signer to *our* unified account, so this proves the
  # user-signed signature end-to-end. Remediate with testnet_wallet_check.rb --fix.
  puts 'Wallet is unifiedAccount — expecting structured rejection...'
  result = sdk.exchange.usd_class_transfer(amount: '10', to_perp: false)
  if result.is_a?(Hash) && result['status'] == 'err' && result['response'].to_s.include?(UNIFIED_REJECTION)
    finish_guarded(TEST_NAME, "unified wallet; usdClassTransfer rejected with #{result['response'].inspect} " \
                              '(signature recovered to this wallet). Full round-trip needs standard mode: ' \
                              'ruby scripts/testnet_wallet_check.rb --fix')
  end

  # Not the pinned rejection: it must be a real transfer, which is undone right away.
  if ok?(result, 'Transfer to spot')
    puts red('NOTE: unified wallet accepted usdClassTransfer; update the failures table.')
    transfer_back(sdk)
  end
  test_passed(TEST_NAME)
end

withdrawable = sdk.info.user_state(addr)['withdrawable'].to_f
if withdrawable < 10
  fail!("perp withdrawable $#{format('%.2f', withdrawable)} < $10. Run testnet_wallet_check.rb --fix")
  test_passed(TEST_NAME)
end

begin
  run(sdk, state)
ensure
  transfer_back(sdk) if state[:in_spot]
end

test_passed(TEST_NAME)
