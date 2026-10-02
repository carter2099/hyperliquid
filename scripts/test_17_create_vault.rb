#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 17: createVault (L1 exchange action)
#
# Default mode (zero-cost wire check, automated): mirrors the TS SDK's
# `tests/api/exchange/createVault.test.ts` — requests an impossible seed
# (initial_usd: 1_000_000_000) and passes only on the structured
# "Insufficient balance to create vault" rejection. That text is only produced
# after the server recovered the L1 signer to this wallet (an unknown signer
# gets "User or API Wallet ... does not exist"), so it proves L1 signing
# end-to-end without creating a vault. Anything else is a hard failure.
#
# `live` mode: creates a real vault with the calling wallet as leader, using a
# $100 testnet USDC seed (server-enforced minimum), and prints the new vault
# address from response.data. The $100 seed is locked into the created vault
# per Hyperliquid's vault lockup rules — run intentionally, never from a runner.
# Skips with a warning if the wallet has < $100 perp USDC available.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_17_create_vault.rb [live]

require_relative 'test_helpers'

EXPECTED_REJECTION = 'Insufficient balance to create vault'

live = ARGV[0] == 'live'

sdk = build_sdk
separator("TEST 17: createVault (#{live ? 'live' : 'wire check'})")

vault_name = "AgentVault#{Time.now.to_i}"
vault_description = 'Vault created by hyperliquid-run integration test (test_17).'

unless live
  puts "Creating vault \"#{vault_name}\" with an impossible $1,000,000,000 seed (expecting structured rejection)..."
  result = sdk.exchange.create_vault(
    name: vault_name,
    description: vault_description,
    initial_usd: 1_000_000_000
  )
  if result.is_a?(Hash) && result['status'] == 'err' &&
     result['response'].to_s.include?(EXPECTED_REJECTION)
    puts "  Rejected: #{result['response']}"
    puts green('  Wire check passed (L1 signature recovered to this wallet; balance-class rejection).')
  else
    $test_failed = true
    puts red("Expected err including #{EXPECTED_REJECTION.inspect}, got: #{result.inspect}")
  end
  test_passed('Test 17 createVault')
  exit 0
end

state = sdk.info.user_state(sdk.exchange.address)
withdrawable = state['withdrawable'].to_f
puts "Withdrawable: $#{format('%.2f', withdrawable)}"
puts

if withdrawable < 100
  puts red("SKIPPED: Need >= $100 perp USDC to seed a vault (have $#{format('%.2f', withdrawable)}).")
  test_passed('Test 17 createVault')
  exit 0
end

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
