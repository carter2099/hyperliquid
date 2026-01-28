#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 10: Vault Deposit/Withdraw
# Check vault equity and either deposit or withdraw.

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 10: Vault Deposit/Withdraw')

vault_addr = '0xa15099a30bbf2e68942d6f4c43d70d04faeab0a0'
puts "Vault: #{vault_addr}"
puts

vault = sdk.info.vault_details(vault_addr, sdk.exchange.address)
user_vault_equity = vault.dig('portfolio', 0, 1, 'accountValue')&.to_f || 0
puts "User equity in vault: $#{user_vault_equity}"
puts

if user_vault_equity > 1
  withdraw_amount = user_vault_equity.floor
  puts "Withdrawing $#{withdraw_amount} from vault..."
  result = sdk.exchange.vault_transfer(
    vault_address: vault_addr,
    is_deposit: false,
    usd: withdraw_amount
  )
  api_error?(result) || puts(green('Vault withdrawal successful!'))
else
  puts "User has $#{user_vault_equity} in vault (insufficient to withdraw)"
  puts 'Depositing $10 to vault...'
  result = sdk.exchange.vault_transfer(
    vault_address: vault_addr,
    is_deposit: true,
    usd: 10
  )
  api_error?(result) || puts(green('Vault deposit successful!'))
end

test_passed('Test 10 Vault Deposit/Withdraw')
