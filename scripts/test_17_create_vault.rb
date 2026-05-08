#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 17: createVault (L1 exchange action)
#
# Creates a new vault with the calling wallet as leader, using a $100 testnet
# USDC seed (server-enforced minimum). On success, prints the new vault address
# from response.data.
#
# WARNING: This is a real testnet action. The $100 seed is locked into the
# created vault per Hyperliquid's vault lockup rules. Run intentionally —
# do NOT wire into test_automated.rb.
#
# Skips with a warning if the wallet has < $100 perp USDC available.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_17_create_vault.rb

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 17: createVault')

state = sdk.info.user_state(sdk.exchange.address)
withdrawable = state['withdrawable'].to_f
puts "Wallet:       #{sdk.exchange.address}"
puts "Withdrawable: $#{format('%.2f', withdrawable)}"
puts

if withdrawable < 100
  puts red("SKIPPED: Need >= $100 perp USDC to seed a vault (have $#{format('%.2f', withdrawable)}).")
  test_passed('Test 17 createVault')
  exit 0
end

vault_name = "AgentVault#{Time.now.to_i}"
vault_description = 'Vault created by hyperliquid-run integration test (test_17).'

puts "Creating vault \"#{vault_name}\" with $100 seed..."
result = sdk.exchange.create_vault(
  name: vault_name,
  description: vault_description,
  initial_usd: 100
)

if api_error?(result)
  puts red("createVault FAILED: #{result.inspect}")
  test_passed('Test 17 createVault')
  exit 1
end

unless result.is_a?(Hash) && result['status'] == 'ok'
  $test_failed = true
  puts red("Unexpected status: #{result.inspect}")
end

response_type = result.dig('response', 'type')
unless response_type == 'createVault'
  $test_failed = true
  puts red("Expected response.type 'createVault', got: #{response_type.inspect}")
end

vault_address = result.dig('response', 'data')
unless vault_address.is_a?(String) && vault_address.start_with?('0x') && vault_address.length == 42
  $test_failed = true
  puts red("Expected response.data to be a 0x-prefixed 40-hex-char vault address, got: #{vault_address.inspect}")
end

unless $test_failed
  puts green("createVault OK: status=ok, response.type=#{response_type}, vault=#{vault_address}")
end

test_passed('Test 17 createVault')
