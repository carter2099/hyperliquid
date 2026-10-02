#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 17: createVault (L1 exchange action)
#
# Default mode (zero-cost wire check, automated): mirrors the TS SDK's
# `tests/api/exchange/createVault.test.ts` — requests an impossible seed
# (initial_usd: 1_000_000_000) and passes only on the structured
# "Insufficient balance to create vault" rejection. The same call is then sent
# from a throwaway (never funded) key, which must get a signature-class
# rejection ("User or API Wallet ... does not exist" / "Must deposit ...") that
# differs from the wallet's. Together they prove on every run that the server
# recovered the L1 signer to this wallet, i.e. L1 signing works end-to-end,
# without creating a vault. Anything else is a hard failure.
#
# `live` mode: creates a real vault with the calling wallet as leader, using a
# $100 testnet USDC seed (server-enforced minimum), and prints the new vault
# address from response.data. The $100 seed is locked into the created vault
# per Hyperliquid's vault lockup rules — run intentionally, never from a runner.
# Reports SKIPPED if the wallet has < $100 perp USDC available.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_17_create_vault.rb [live]

require_relative 'test_helpers'

NAME = 'Test 17 createVault'
EXPECTED_REJECTION = 'Insufficient balance to create vault'

live = ARGV[0] == 'live'

sdk = build_sdk
separator("TEST 17: createVault (#{live ? 'live' : 'wire check'})")

vault_name = "AgentVault#{Time.now.to_i}"
vault_description = 'Vault created by hyperliquid-run integration test (test_17).'

unless live
  probe_args = { name: vault_name, description: vault_description, initial_usd: 1_000_000_000 }
  puts "Creating vault \"#{vault_name}\" with an impossible $1,000,000,000 seed (expecting structured rejection)..."
  result = sdk.exchange.create_vault(**probe_args)
  if result.is_a?(Hash) && result['status'] == 'err' &&
     result['response'].to_s.include?(EXPECTED_REJECTION)
    puts "  Rejected: #{result['response']}"
    puts 'Sending the same call from a throwaway key (signer-dependence control)...'
    control_text =
      begin
        control = throwaway_sdk.exchange.create_vault(**probe_args)
        control.is_a?(Hash) ? control['response'].to_s : control.inspect
      rescue Hyperliquid::Error => e
        "raised #{e.class}: #{e.message}"
      end
    assert_signer_dependent('createVault', result['response'].to_s, control_text)
    puts green('  Wire check passed (L1 signature recovered to this wallet; balance-class rejection).') unless $test_failed
  else
    fail!("Expected err including #{EXPECTED_REJECTION.inspect}, got: #{result.inspect}")
  end
  test_passed(NAME)
end

state = sdk.info.user_state(sdk.exchange.address)
withdrawable = state['withdrawable'].to_f
puts "Withdrawable: $#{format('%.2f', withdrawable)}"
puts

if withdrawable < 100
  finish_skipped(NAME, "need >= $100 perp USDC to seed a vault (have $#{format('%.2f', withdrawable)})")
end

puts "Creating vault \"#{vault_name}\" with $100 seed..."
result = sdk.exchange.create_vault(
  name: vault_name,
  description: vault_description,
  initial_usd: 100
)

if api_error?(result)
  fail!("createVault FAILED: #{result.inspect}")
  test_passed(NAME)
end

fail!("Unexpected status: #{result.inspect}") unless result.is_a?(Hash) && result['status'] == 'ok'

response_type = result.dig('response', 'type')
fail!("Expected response.type 'createVault', got: #{response_type.inspect}") unless response_type == 'createVault'

vault_address = result.dig('response', 'data')
unless vault_address.is_a?(String) && vault_address.start_with?('0x') && vault_address.length == 42
  fail!("Expected response.data to be a 0x-prefixed 40-hex-char vault address, got: #{vault_address.inspect}")
end

puts green("createVault OK: status=ok, response.type=#{response_type}, vault=#{vault_address}") unless $test_failed

test_passed(NAME)
