#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 12: Staking Status / Delegate / Undelegate
#
# Default:  Show staking summary and delegations
# Options:  ruby test_12_staking.rb delegate
#           ruby test_12_staking.rb undelegate

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 12: Staking Status / Delegate / Undelegate')

validator = '0x946bf3135c7d15e4462b510f74b6e304aabb5b21'
action = ARGV[0] # nil, "delegate", or "undelegate"
delegate_amount = 10_000_000 # 0.1 HYPE (wei = float * 1e8)

puts "Validator: #{validator}"
puts

# Show staking summary
summary = sdk.info.delegator_summary(sdk.exchange.address)
puts "Staking summary:"
puts "  Delegated:      #{summary['delegated']}" if summary['delegated']
puts "  Undelegatable:  #{summary['undelegatable']}" if summary['undelegatable']
puts "  Total pending:  #{summary['totalPending']}" if summary['totalPending']
puts "  N delegations:  #{summary['nDelegations']}" if summary['nDelegations']
puts

# Show delegations for this validator
delegations = sdk.info.delegations(sdk.exchange.address)
validator_delegation = delegations&.find { |d| d['validator']&.downcase == validator.downcase }

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
  puts 'Pass "delegate" or "undelegate" as an argument to perform an action.'
  puts '  ruby scripts/test_12_staking.rb delegate'
  puts '  ruby scripts/test_12_staking.rb undelegate'
end

test_passed('Test 12 Staking')
