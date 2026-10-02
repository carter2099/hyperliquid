#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 9: Sub Account Lifecycle
#
# Reuses the "ruby-sdk-test" sub-account if it already exists (looked up via
# Info#sub_accounts2), otherwise creates it; then deposits $10 and withdraws $10
# (both must return status ok). If the deposit landed and the withdrawal never
# ran (error, exception, timeout), `ensure` withdraws the $10 and reports any
# cleanup error.
#
# Until the wallet has traded the $100k volume the exchange requires, creation
# is rejected with "Cannot create sub-accounts until enough volume traded"
# (same text the TS SDK asserts). That rejection is a wire check: the server
# only produces it after recovering the L1 signer to this wallet. Every run
# proves that with a random-key control: the same call signed by a throwaway
# key must get a signer-class rejection ("User or API Wallet ... does not
# exist") that differs from the wallet's text.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_09_sub_account_lifecycle.rb

require_relative 'test_helpers'

TEST_NAME = 'Test 9 Sub Account Lifecycle'
SUB_ACCOUNT_NAME = 'ruby-sdk-test'
EXPECTED_REJECTION = 'Cannot create sub-accounts until enough volume traded'

def response_text(result)
  result.is_a?(Hash) ? result['response'].to_s : result.inspect
end

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

def transfer(sdk, sub_account_address, is_deposit)
  sdk.exchange.sub_account_transfer(sub_account_user: sub_account_address, is_deposit: is_deposit, usd: 10)
end

def run(sdk, sub_account_address, state)
  wait_with_countdown(WAIT_SECONDS, 'Waiting before deposit...')

  puts 'Depositing $10 to sub-account...'
  state[:deposited] = true if ok?(transfer(sdk, sub_account_address, true), 'Deposit')
  return unless state[:deposited]

  puts
  wait_with_countdown(WAIT_SECONDS, 'Waiting before withdrawal...')

  puts 'Withdrawing $10 from sub-account...'
  result = transfer(sdk, sub_account_address, false)
  state[:deposited] = false
  ok?(result, 'Withdrawal')
end

# Withdraws the $10 this script deposited. Reports, never raises.
def withdraw_back(sdk, sub_account_address)
  puts 'Cleanup: withdrawing the $10 deposited by this script...'
  result = transfer(sdk, sub_account_address, false)
  fail!("Cleanup: withdrawal failed: #{result.inspect}") unless result.is_a?(Hash) && result['status'] == 'ok'
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

sdk = build_sdk
separator('TEST 9: Sub Account Lifecycle')

addr = sdk.exchange.address
existing = Array(sdk.info.sub_accounts2(addr)).find { |s| s['name'] == SUB_ACCOUNT_NAME }
if existing
  sub_account_address = existing['subAccountUser']
  puts "Reusing existing sub-account #{sub_account_address}"
else
  puts "Creating sub-account \"#{SUB_ACCOUNT_NAME}\"..."
  result = sdk.exchange.create_sub_account(name: SUB_ACCOUNT_NAME)
  if result.is_a?(Hash) && result['status'] == 'err' && result['response'].to_s.include?(EXPECTED_REJECTION)
    puts "  Rejected: #{result['response']}"
    puts '  Random-key control (same call, throwaway key)...'
    control = throwaway_sdk.exchange.create_sub_account(name: SUB_ACCOUNT_NAME)
    assert_signer_dependent('createSubAccount', response_text(result), response_text(control))
    puts green('  Wire check passed (L1 signature recovered to this wallet; $100k volume gate not met).') unless $test_failed
    test_passed(TEST_NAME)
  end
  test_passed(TEST_NAME) unless ok?(result, 'Sub-account creation')

  response = result['response']
  data = response.is_a?(Hash) ? response['data'] : nil
  sub_account_address = data.is_a?(Hash) ? data['subAccountUser'] : data
end
puts

unless sub_account_address.is_a?(String) && sub_account_address.match?(/\A0x\h{40}\z/)
  fail!("Could not extract a sub-account address: #{sub_account_address.inspect}")
  test_passed(TEST_NAME)
end

puts "Sub-account address: #{sub_account_address}"
puts

state = { deposited: false }
begin
  run(sdk, sub_account_address, state)
ensure
  withdraw_back(sdk, sub_account_address) if state[:deposited]
end

test_passed(TEST_NAME)
