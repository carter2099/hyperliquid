#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 25: HIP-3* star operations (testnet-only, structured rejection)
#
# Reads Info#user_star_state for the wallet, then sends HIP-3* `star` operations
# (`perpDeploy` L1 action, star variant) to a live star dex. The wallet is not a deployer
# or sub-deployer of any star dex, so the server rejects each action, but only after it has
# recovered the signer. "Invalid perp deployer or sub-deployer" (or, for proxy operations
# on the unapproved wallet, "User requires approval") proves the action hash, key order,
# and types are correct. "User or API Wallet ... does not exist" means the signature
# recovered to a random address (SDK hash bug); an HTTP 422 deserialize error means a
# malformed shape.
#
# No state changes and no balance needed. Soft-skips when testnet has no star dex.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_25_hip3_star.rb

require_relative 'test_helpers'

DEPLOYER_REJECTION = 'Invalid perp deployer or sub-deployer'
APPROVAL_REJECTION = 'User requires approval'

sdk = build_sdk
separator('TEST 25: HIP-3* star (testnet-only)')

# Live read: dexToState is an Array of [dex, state] pairs (the wallet is never approved)
puts 'user_star_state...'
state = sdk.info.user_star_state(sdk.exchange.address)
if state.is_a?(Hash) && state['dexToState'].is_a?(Array)
  puts green("  dexToState: #{state['dexToState'].inspect}")
else
  $test_failed = true
  puts red("  FAILED: unexpected userStarState shape: #{state.inspect}")
end
puts

dex = sdk.info.perp_dexs.compact.find do |d|
  d['subDeployers']&.any? { |variant, _| variant.is_a?(Hash) && variant.key?('hip3Star') }
end&.dig('name')
unless dex
  puts red('WARNING: no HIP-3* dex with star sub-deployer grants found on testnet; skipping star actions')
  test_passed('Test 25 HIP-3* star')
  exit 0
end
puts "Target star dex: #{dex}"
puts

def check_star(name, accepted)
  puts "#{name}..."
  result = yield
  response = result.is_a?(Hash) ? result['response'] : nil
  message = response.is_a?(String) ? response : response.inspect

  if result.is_a?(Hash) && result['status'] == 'ok'
    puts red("  WARNING: wallet unexpectedly authorized (harmless on testnet): #{result.inspect}")
  elsif message.match?(/does not exist/i)
    $test_failed = true
    puts red("  FAILED: signature/hash mismatch (signer recovered to an unknown address): #{message}")
  elsif result.is_a?(Hash) && result['status'] == 'err' && accepted.any? { |text| message.include?(text) }
    puts green("  structured rejection: wire+signature accepted: #{message}")
  else
    $test_failed = true
    puts red("  FAILED: unrecognized response: #{result.inspect}")
  end
rescue Hyperliquid::ClientError, Hyperliquid::BadRequestError => e
  $test_failed = true
  puts red("  FAILED: action failed to deserialize: #{e.class}: #{e.message}")
ensure
  sleep 1
end

check_star('star_modify_approval', [DEPLOYER_REJECTION]) do
  sdk.exchange.star_modify_approval(dex: dex, user: sdk.exchange.address, approved: true)
end

# Exercises asset_index on a live star dex plus the nested asset-list wire
universe = sdk.info.meta(dex: dex)['universe'].map { |asset| asset['name'] }
cancel_coin = universe.include?("#{dex}:BTC") ? "#{dex}:BTC" : universe.first
check_star("star_cancel_all (#{cancel_coin})", [DEPLOYER_REJECTION, APPROVAL_REJECTION]) do
  sdk.exchange.star_cancel_all(dex: dex, user: sdk.exchange.address, coins: [cancel_coin])
end

test_passed('Test 25 HIP-3* star')
