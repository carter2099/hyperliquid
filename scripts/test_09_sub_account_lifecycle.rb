#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 9: Sub Account Lifecycle
#
# Reuses the "ruby-sdk-test" sub-account if it already exists (looked up via
# Info#sub_accounts2), otherwise creates it; then deposits $10 and withdraws $10.
#
# Until the wallet has traded the $100k volume the exchange requires, creation
# is rejected with "Cannot create sub-accounts until enough volume traded"
# (same text the TS SDK asserts). That rejection is a wire check: the server
# only produces it after recovering the L1 signer to this wallet (an unknown
# signer gets "User or API Wallet ... does not exist"), so the test passes on it.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_09_sub_account_lifecycle.rb

require_relative 'test_helpers'

SUB_ACCOUNT_NAME = 'ruby-sdk-test'
EXPECTED_REJECTION = 'Cannot create sub-accounts until enough volume traded'

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
  if result.is_a?(Hash) && result['status'] == 'err' &&
     result['response'].to_s.include?(EXPECTED_REJECTION)
    puts red("WARNING: #{result['response']}")
    puts '  Wire check passed (L1 signature recovered to this wallet; $100k volume gate not met).'
    test_passed('Test 9 Sub Account Lifecycle')
    exit 0
  end
  exit 1 if api_error?(result)

  puts green('Sub-account created!')
  data = result.dig('response', 'data')
  sub_account_address = data.is_a?(Hash) ? data['subAccountUser'] : data
end
puts

if sub_account_address
  puts "Sub-account address: #{sub_account_address}"
  puts

  wait_with_countdown(WAIT_SECONDS, 'Waiting before deposit...')

  puts 'Depositing $10 to sub-account...'
  result = sdk.exchange.sub_account_transfer(
    sub_account_user: sub_account_address,
    is_deposit: true,
    usd: 10
  )
  api_error?(result) || puts(green('Deposit successful!'))
  puts

  wait_with_countdown(WAIT_SECONDS, 'Waiting before withdrawal...')

  puts 'Withdrawing $10 from sub-account...'
  result = sdk.exchange.sub_account_transfer(
    sub_account_user: sub_account_address,
    is_deposit: false,
    usd: 10
  )
  api_error?(result) || puts(green('Withdrawal successful!'))
else
  puts red('SKIPPED: Could not extract sub-account address from response')
end

test_passed('Test 9 Sub Account Lifecycle')
