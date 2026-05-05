#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 16: sendToEvmWithData (user-signed exchange action)
#
# Mirrors the TS SDK's `tests/api/exchange/sendToEvmWithData.test.ts`:
#   1. Top up spot USDC by 2 (via usd_class_transfer perp -> spot).
#   2. Submit one real sendToEvmWithData action sending 1 USDC to 0x...01
#      on HyperEVM testnet (chain 998) with empty calldata.
#   3. Assert response is { status: 'ok', response: { type: 'default' } }.
#
# This funds-moving test sends 1 testnet USDC to 0x...01 (effectively burned —
# no contract is there to redirect it). Same bar the TS SDK uses for its own
# test suite.
#
# Skips with a warning if the wallet is on unified account (usd_class_transfer
# is disabled in that mode and the top-up cannot run).
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_16_send_to_evm_with_data.rb

require_relative 'test_helpers'

sdk = build_sdk
separator('TEST 16: sendToEvmWithData')

abstraction = sdk.info.user_abstraction(sdk.exchange.address)
if abstraction == 'unifiedAccount'
  puts "SKIPPED: Wallet has unified account active (abstraction=#{abstraction.inspect})."
  puts '  usd_class_transfer top-up step is disabled by the exchange when balances are unified.'
  test_passed('Test 16 sendToEvmWithData')
  exit 0
end

puts 'Topping up spot USDC by $2 (perp -> spot)...'
top_up = sdk.exchange.usd_class_transfer(amount: '2', to_perp: false)
dump_status(top_up)
if api_error?(top_up)
  puts red('Top-up failed; aborting before sendToEvmWithData.')
  test_passed('Test 16 sendToEvmWithData')
  exit 1
end
puts green('Top-up successful.')
puts

wait_with_countdown(WAIT_SECONDS, 'Waiting before sendToEvmWithData...')

puts 'Sending 1 USDC to 0x...01 on HyperEVM testnet (chain 998) with empty calldata...'
result = sdk.exchange.send_to_evm_with_data(
  token: 'USDC',
  amount: '1',
  source_dex: 'spot',
  destination_recipient: '0x0000000000000000000000000000000000000001',
  address_encoding: 'hex',
  destination_chain_id: 998,
  gas_limit: 200_000,
  data: '0x'
)

if api_error?(result)
  puts red("sendToEvmWithData FAILED: #{result.inspect}")
  test_passed('Test 16 sendToEvmWithData')
  exit 1
end

unless result.is_a?(Hash) && result['status'] == 'ok'
  $test_failed = true
  puts red("Unexpected status: #{result.inspect}")
end

response_type = result.dig('response', 'type')
unless response_type == 'default'
  $test_failed = true
  puts red("Expected response.type 'default', got: #{response_type.inspect}")
end

puts green("sendToEvmWithData OK: status=ok, response.type=#{response_type}") unless $test_failed

test_passed('Test 16 sendToEvmWithData')
