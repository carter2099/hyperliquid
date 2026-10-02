#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 10: Vault Status / Deposit / Withdraw
#
# Default:  read the HLP vault via Info#vault_details (with this wallet as user)
#           and assert its shape: name, vaultAddress == the queried vault,
#           leader address, isClosed boolean, portfolio Array, and a
#           followerState that is nil or describes this wallet with numeric
#           vaultEquity. Then show equity, entry date, unlock date.
# Options:  ruby scripts/test_10_vault.rb deposit    # deposit $10 (manual only)
#           ruby scripts/test_10_vault.rb withdraw   # withdraw whole dollars of equity (manual only)

require_relative 'test_helpers'

TEST_NAME = 'Test 10 Vault Status'
VAULT_ADDR = '0xa15099a30bbf2e68942d6f4c43d70d04faeab0a0'
ADDRESS = /\A0x\h{40}\z/

def numeric?(value)
  Float(value, exception: false) ? true : false
end

# Returns the followerState (Hash or nil) after recording every shape violation.
def assert_vault_shape(vault, user)
  unless vault.is_a?(Hash)
    fail!("vault_details is not a Hash: #{vault.inspect}")
    return nil
  end

  fail!("name is not a non-empty String: #{vault['name'].inspect}") unless vault['name'].is_a?(String) && !vault['name'].empty?
  fail!("vaultAddress #{vault['vaultAddress'].inspect} != #{VAULT_ADDR}") unless vault['vaultAddress'].to_s.downcase == VAULT_ADDR
  fail!("leader is not an address: #{vault['leader'].inspect}") unless vault['leader'].to_s.match?(ADDRESS)
  fail!("isClosed is not a boolean: #{vault['isClosed'].inspect}") unless [true, false].include?(vault['isClosed'])
  fail!("portfolio is not an Array: #{vault['portfolio'].class}") unless vault['portfolio'].is_a?(Array)

  follower = vault['followerState']
  return nil if follower.nil?
  unless follower.is_a?(Hash)
    fail!("followerState is not a Hash: #{follower.inspect}")
    return nil
  end

  fail!("followerState.user #{follower['user'].inspect} != #{user}") unless follower['user'].to_s.downcase == user.downcase
  fail!("followerState.vaultEquity not numeric: #{follower['vaultEquity'].inspect}") unless numeric?(follower['vaultEquity'])
  follower
end

def ok?(result, label)
  dump_status(result)
  if result.is_a?(Hash) && result['status'] == 'ok'
    puts green("#{label} successful!")
  else
    fail!("#{label}: expected status ok, got #{result.inspect}")
  end
end

sdk = build_sdk
separator('TEST 10: Vault Status / Deposit / Withdraw')

action = ARGV[0] # nil, "deposit", or "withdraw"

puts "Vault: #{VAULT_ADDR}"
puts

vault = sdk.info.vault_details(VAULT_ADDR, sdk.exchange.address)
follower = assert_vault_shape(vault, sdk.exchange.address)
test_passed(TEST_NAME) if $test_failed

puts green("vault_details shape OK: #{vault['name']} (leader #{vault['leader']}, closed=#{vault['isClosed']})")
if follower
  puts "Vault equity:  $#{follower['vaultEquity']}"
  puts "Entry date:    #{Time.at(follower['vaultEntryTime'] / 1000.0).utc}" if follower['vaultEntryTime']
  puts "Unlock date:   #{Time.at(follower['lockupUntil'] / 1000.0).utc}" if follower['lockupUntil']
else
  puts 'No position in this vault.'
end
puts

case action
when 'deposit'
  puts 'Depositing $10 to vault...'
  ok?(sdk.exchange.vault_transfer(vault_address: VAULT_ADDR, is_deposit: true, usd: 10), 'Vault deposit')
when 'withdraw'
  equity = follower ? follower['vaultEquity'].to_f : 0
  if equity > 1
    withdraw_amount = equity.floor
    puts "Withdrawing $#{withdraw_amount} from vault..."
    ok?(sdk.exchange.vault_transfer(vault_address: VAULT_ADDR, is_deposit: false, usd: withdraw_amount),
        'Vault withdrawal')
  else
    fail!("Insufficient vault equity to withdraw ($#{equity})")
  end
else
  puts 'Pass "deposit" or "withdraw" as an argument to perform a transfer.'
  puts '  ruby scripts/test_10_vault.rb deposit'
  puts '  ruby scripts/test_10_vault.rb withdraw'
end

test_passed(TEST_NAME)
