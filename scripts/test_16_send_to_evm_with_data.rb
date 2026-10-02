#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 16: sendToEvmWithData (user-signed exchange action)
#
# Default mode (zero-cost wire check, automated): submits sendToEvmWithData
# with an impossible amount (1,000,000,000 USDC) and passes only on the
# structured EXPECTED_REJECTION below. The server can only produce that text
# after recovering the signer to this wallet (a bad signature recovers an
# unknown address and is rejected differently), so it proves the EIP-712
# signature end-to-end without moving funds. status 'ok' or any other error
# is a hard failure.
#
# `live` mode mirrors the TS SDK's `tests/api/exchange/sendToEvmWithData.test.ts`:
#   1. Top up spot USDC by 2 (via usd_class_transfer perp -> spot); skipped on
#      a unified wallet (spot already holds the unified USDC).
#   2. Submit one real sendToEvmWithData action sending 1 USDC to 0x...01
#      on HyperEVM testnet (chain 998) with empty calldata.
#   3. Assert response is { status: 'ok', response: { type: 'default' } }.
# `live` burns 1 testnet USDC to 0x...01 (no contract is there to redirect it).
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_16_send_to_evm_with_data.rb [live]

require_relative 'test_helpers'

# pinned 2026-10-02 (integration-tests Run B) from observed testnet response:
#   "Error transferring to EVM. Use Arbitrum bridge instead."
# random-key control (throwaway key, same call): "Must deposit before performing actions. User: 0x..."
EXPECTED_REJECTION = 'Error transferring to EVM. Use Arbitrum bridge instead'

live = ARGV[0] == 'live'

sdk = build_sdk
separator("TEST 16: sendToEvmWithData (#{live ? 'live' : 'wire check'})")

send_args = {
  token: 'USDC',
  source_dex: 'spot',
  destination_recipient: '0x0000000000000000000000000000000000000001',
  address_encoding: 'hex',
  destination_chain_id: 998,
  gas_limit: 200_000,
  data: '0x'
}

unless live
  puts 'Sending an impossible 1,000,000,000 USDC sendToEvmWithData (expecting structured rejection)...'
  result = sdk.exchange.send_to_evm_with_data(**send_args, amount: '1000000000')
  if result.is_a?(Hash) && result['status'] == 'err' &&
     result['response'].to_s.include?(EXPECTED_REJECTION)
    puts "  Rejected: #{result['response']}"
    puts green('  Wire check passed (signature recovered to this wallet; signer-dependent rejection).')
  else
    $test_failed = true
    puts red("Expected err including #{EXPECTED_REJECTION.inspect}, got: #{result.inspect}")
  end
  test_passed('Test 16 sendToEvmWithData')
  exit 0
end

abstraction = sdk.info.user_abstraction(sdk.exchange.address)
if abstraction == 'unifiedAccount'
  puts 'unified: skipping top-up (spot holds the unified USDC)'
  puts
else
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
end

puts 'Sending 1 USDC to 0x...01 on HyperEVM testnet (chain 998) with empty calldata...'
result = sdk.exchange.send_to_evm_with_data(**send_args, amount: '1')

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
