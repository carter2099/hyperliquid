#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 12: Staking Status / Delegate / Undelegate
#
# Default (automated): read-only staking report (delegator_summary shape +
# delegations), then a zero-cost wire check — undelegate an impossible
# 10^15 wei (10^7 HYPE) and pass only on the structured EXPECTED_REJECTION.
# The server only produces that text after recovering the user-signed
# signature to this wallet (an unknown signer gets "Must deposit before
# performing actions"), so it proves tokenDelegate signing end-to-end.
#
# Options (manual only — delegations have a 1-day lockup, never from a runner):
#   ruby scripts/test_12_staking.rb delegate     # delegate 0.1 HYPE
#   ruby scripts/test_12_staking.rb undelegate   # undelegate 0.1 HYPE

require_relative 'test_helpers'

SUMMARY_KEYS = %w[delegated undelegated totalPendingWithdrawal nPendingWithdrawals].freeze
# pinned 2026-10-02 (integration-tests Run C) from observed testnet response:
#   "Insufficient balance to undelegate"
# with wei 10**15 (RTCP fallback: wei 10**18 was parse-class "Invalid input number").
# random-key control (throwaway key, same call): "Must deposit before performing actions. User: 0x..."
EXPECTED_REJECTION = 'Insufficient balance to undelegate'
WIRE_CHECK_WEI = 10**15

sdk = build_sdk
separator('TEST 12: Staking Status / Delegate / Undelegate')

validator = '0x946bf3135c7d15e4462b510f74b6e304aabb5b21'
action = ARGV[0] # nil, "delegate", or "undelegate"
delegate_amount = 10_000_000 # 0.1 HYPE (wei = float * 1e8)

puts "Validator: #{validator}"
puts

# Show staking summary
summary = sdk.info.delegator_summary(sdk.exchange.address)
if summary.is_a?(Hash) && SUMMARY_KEYS.all? { |k| summary.key?(k) }
  puts 'Staking summary:'
  puts "  Delegated:                #{summary['delegated']}"
  puts "  Undelegated:              #{summary['undelegated']}"
  puts "  Total pending withdrawal: #{summary['totalPendingWithdrawal']}"
  puts "  N pending withdrawals:    #{summary['nPendingWithdrawals']}"
else
  $test_failed = true
  puts red("FAILED: delegator_summary missing keys #{SUMMARY_KEYS}: #{summary.inspect}")
end
puts

# Show delegations for this validator
delegations = sdk.info.delegations(sdk.exchange.address)
unless delegations.is_a?(Array)
  $test_failed = true
  puts red("FAILED: delegations is not an Array: #{delegations.inspect}")
  delegations = []
end
validator_delegation = delegations.find { |d| d['validator']&.downcase == validator.downcase }

if validator_delegation
  puts "Delegation to #{validator}:"
  puts "  Amount:    #{validator_delegation['amount']}"
  lockup = validator_delegation['lockedUntilTimestamp']
  puts "  Locked until: #{Time.at(lockup / 1000.0).utc}" if lockup
else
  puts "No active delegation to #{validator}."
end
puts

case action
when 'delegate'
  puts "Delegating 0.1 HYPE to #{validator}..."
  result = sdk.exchange.token_delegate(
    validator: validator,
    wei: delegate_amount,
    is_undelegate: false
  )
  dump_status(result)
  api_error?(result) || puts(green('Delegation successful!'))
when 'undelegate'
  puts "Undelegating 0.1 HYPE from #{validator}..."
  result = sdk.exchange.token_delegate(
    validator: validator,
    wei: delegate_amount,
    is_undelegate: true
  )
  dump_status(result)
  api_error?(result) || puts(green('Undelegation successful!'))
else
  puts "Wire check: undelegating an impossible #{WIRE_CHECK_WEI} wei (expecting structured rejection)..."
  result = sdk.exchange.token_delegate(
    validator: validator,
    wei: WIRE_CHECK_WEI,
    is_undelegate: true
  )
  if result.is_a?(Hash) && result['status'] == 'err' &&
     result['response'].to_s.include?(EXPECTED_REJECTION)
    puts "  Rejected: #{result['response']}"
    puts green('  Wire check passed (signature recovered to this wallet; balance-class rejection).')
  else
    $test_failed = true
    puts red("Expected err including #{EXPECTED_REJECTION.inspect}, got: #{result.inspect}")
  end
  puts
  puts 'Pass "delegate" or "undelegate" as an argument to perform a real (locking) action.'
end

test_passed('Test 12 Staking')
