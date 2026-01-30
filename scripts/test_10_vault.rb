#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 10: Vault Status / Deposit / Withdraw
#
# Default:  Show vault status (equity, entry date, unlock date)
# Options:  ruby test_10_vault_transfer.rb deposit
#           ruby test_10_vault_transfer.rb withdraw

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 10: Vault Status / Deposit / Withdraw')

vault_addr = '0xa15099a30bbf2e68942d6f4c43d70d04faeab0a0'
action = ARGV[0] # nil, "deposit", or "withdraw"

puts "Vault: #{vault_addr}"
puts

vault = sdk.info.vault_details(vault_addr, sdk.exchange.address)
follower = vault['followerState']

if follower
  equity = follower['vaultEquity']
  entry_time = follower['vaultEntryTime']
  lockup_until = follower['lockupUntil']

  puts "Vault equity:  $#{equity}"
  puts "Entry date:    #{Time.at(entry_time / 1000.0).utc}" if entry_time
  puts "Unlock date:   #{Time.at(lockup_until / 1000.0).utc}" if lockup_until
else
  puts 'No position in this vault.'
end
puts

case action
when 'deposit'
  puts 'Depositing $10 to vault...'
  result = sdk.exchange.vault_transfer(
    vault_address: vault_addr,
    is_deposit: true,
    usd: 10
  )
  api_error?(result) || puts(green('Vault deposit successful!'))
when 'withdraw'
  equity_f = follower&.dig('vaultEquity')&.to_f || 0
  if equity_f > 1
    withdraw_amount = equity_f.floor
    puts "Withdrawing $#{withdraw_amount} from vault..."
    result = sdk.exchange.vault_transfer(
      vault_address: vault_addr,
      is_deposit: false,
      usd: withdraw_amount
    )
    api_error?(result) || puts(green('Vault withdrawal successful!'))
  else
    puts red("Insufficient vault equity to withdraw ($#{equity_f})")
  end
else
  puts 'Pass "deposit" or "withdraw" as an argument to perform a transfer.'
  puts '  ruby scripts/test_10_vault_transfer.rb deposit'
  puts '  ruby scripts/test_10_vault_transfer.rb withdraw'
end

test_passed('Test 10 Vault Status')
