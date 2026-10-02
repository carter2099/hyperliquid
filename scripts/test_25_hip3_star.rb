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
# malformed shape. Each accepted rejection is repeated from a throwaway (never funded) key,
# which must get a signature-class rejection that differs from the wallet's: that proves on
# every run the accepted text depended on the recovered signer.
#
# Results: PASS on accepted rejections; SKIPPED when testnet has no star dex; GUARDED when
# the wallet was unexpectedly authorized (an `ok`, harmless on testnet, still proves the
# signature recovered to an authorized identity). No balance needed.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_25_hip3_star.rb

require_relative 'test_helpers'

NAME = 'Test 25 HIP-3* star'

DEPLOYER_REJECTION = 'Invalid perp deployer or sub-deployer'
APPROVAL_REJECTION = 'User requires approval'
# Observed 2026-10-02 for the standard-abstraction agent wallet on star dex `ignp`; a throwaway
# key gets "User or API Wallet … does not exist." for the same call, so the text is signer-dependent.
TRADE_REJECTION = 'User cannot trade the specified asset'

sdk = build_sdk
separator('TEST 25: HIP-3* star (testnet-only)')

# Live read: dexToState is an Array of [dex, state] pairs (the wallet is never approved)
puts 'user_star_state...'
state = sdk.info.user_star_state(sdk.exchange.address)
if state.is_a?(Hash) && state['dexToState'].is_a?(Array)
  puts green("  dexToState: #{state['dexToState'].inspect}")
else
  fail!("  FAILED: unexpected userStarState shape: #{state.inspect}")
end
puts

dex = sdk.info.perp_dexs.compact.find do |d|
  d['subDeployers']&.any? { |variant, _| variant.is_a?(Hash) && variant.key?('hip3Star') }
end&.dig('name')
finish_skipped(NAME, 'no HIP-3* dex with star sub-deployer grants found on testnet; star actions not sent') unless dex
puts "Target star dex: #{dex}"
puts

def response_message(result)
  response = result.is_a?(Hash) ? result['response'] : nil
  response.is_a?(String) ? response : response.inspect
end

# Yields the wallet's exchange, then (only after an accepted rejection) the throwaway's.
# Returns a guard reason String when the wallet was unexpectedly authorized, else nil.
def check_star(name, accepted, wallet_exchange, control_exchange)
  puts "#{name}..."
  result = yield wallet_exchange
  message = response_message(result)

  if result.is_a?(Hash) && result['status'] == 'ok'
    puts red("  WARNING: wallet unexpectedly authorized (harmless on testnet): #{result.inspect}")
    return "#{name}: wallet unexpectedly authorized: #{result.inspect}"
  elsif message.match?(/does not exist/i)
    fail!("  FAILED: signature/hash mismatch (signer recovered to an unknown address): #{message}")
  elsif result.is_a?(Hash) && result['status'] == 'err' && accepted.any? { |text| message.include?(text) }
    puts green("  structured rejection: wire+signature accepted: #{message}")
    control_text =
      begin
        response_message(yield(control_exchange))
      rescue Hyperliquid::Error => e
        "raised #{e.class}: #{e.message}"
      end
    assert_signer_dependent(name, message, control_text)
  else
    fail!("  FAILED: unrecognized response: #{result.inspect}")
  end
  nil
rescue Hyperliquid::ClientError, Hyperliquid::BadRequestError => e
  fail!("  FAILED: action failed to deserialize: #{e.class}: #{e.message}")
  nil
ensure
  sleep 1
end

wallet = sdk.exchange
control = throwaway_sdk.exchange
address = wallet.address
guards = []

guards << check_star('star_modify_approval', [DEPLOYER_REJECTION, TRADE_REJECTION], wallet, control) do |exchange|
  exchange.star_modify_approval(dex: dex, user: address, approved: true)
end

# Exercises asset_index on a live star dex plus the nested asset-list wire
universe = sdk.info.meta(dex: dex)['universe'].map { |asset| asset['name'] }
cancel_coin = universe.include?("#{dex}:BTC") ? "#{dex}:BTC" : universe.first
guards << check_star("star_cancel_all (#{cancel_coin})", [DEPLOYER_REJECTION, APPROVAL_REJECTION, TRADE_REJECTION],
                     wallet, control) do |exchange|
  exchange.star_cancel_all(dex: dex, user: address, coins: [cancel_coin])
end

guards.compact!
finish_guarded(NAME, guards.join('; ')) unless guards.empty?

test_passed(NAME)
