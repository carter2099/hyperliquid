#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 15: Explorer RPC (tx_details + user_details)
#
# Calls the explorer RPC for the wallet's recent transactions:
#   1. user_details(wallet_address)  -> list of recent txs
#   2. tx_details(first tx hash)     -> full details of one tx
#
# Requires HYPERLIQUID_PRIVATE_KEY (used to derive wallet address; no signing).
# A wallet with no explorer txs reports SKIPPED: tx_details had nothing to look up.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_15_explorer.rb

require_relative 'test_helpers'

NAME = 'Test 15 explorer RPC'

separator('TEST 15: Explorer RPC (tx_details + user_details)')

sdk = build_sdk

begin
  user_details_resp = sdk.info.user_details(sdk.exchange.address)
rescue Hyperliquid::Error => e
  fail!("user_details FAILED: #{e.class}: #{e.message}")
  test_passed(NAME)
end

unless user_details_resp.is_a?(Hash) && user_details_resp['type'] == 'userDetails'
  fail!("user_details: unexpected response shape: #{user_details_resp.inspect}")
  test_passed(NAME)
end

txs = user_details_resp['txs'] || []
puts green("user_details OK: #{txs.length} txs returned")

finish_skipped(NAME, 'wallet has no explorer txs; tx_details had nothing to look up') if txs.empty?

first_hash = txs.first['hash']
unless first_hash.is_a?(String) && first_hash.start_with?('0x')
  fail!("First tx hash missing or malformed: #{first_hash.inspect}")
  test_passed(NAME)
end

puts "Looking up tx_details for #{first_hash}..."
begin
  tx_resp = sdk.info.tx_details(first_hash)
rescue Hyperliquid::Error => e
  fail!("tx_details FAILED: #{e.class}: #{e.message}")
  test_passed(NAME)
end

unless tx_resp.is_a?(Hash) && tx_resp['type'] == 'txDetails'
  fail!("tx_details: unexpected response shape: #{tx_resp.inspect}")
  test_passed(NAME)
end

tx = tx_resp['tx']
unless tx.is_a?(Hash) && tx['hash'] == first_hash
  fail!("tx_details: hash mismatch or missing tx: #{tx.inspect}")
  test_passed(NAME)
end

puts green("tx_details OK: action=#{tx.dig('action', 'type')} time=#{tx['time']}")

test_passed(NAME)
