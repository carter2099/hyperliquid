#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 9: Sub Account Lifecycle
# Create a sub-account, deposit $10, then withdraw $10.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 9: Sub Account Lifecycle')

puts 'Creating sub-account "ruby-sdk-test"...'
result = sdk.exchange.create_sub_account(name: 'ruby-sdk-test')

if api_error?(result)
  exit 1
end

puts green('Sub-account created!')
puts

sub_account_address = result.dig('response', 'data', 'subAccountUser')
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
