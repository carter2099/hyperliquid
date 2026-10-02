#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 27: validator-operator actions (rejection-only wire check)
#
# Sends validator-operator L1 actions from a wallet that is NOT a validator or a
# validator signer, and expects a structured server rejection (`status: 'err'` with a
# known message) for each. A structured rejection proves the request deserialised
# server-side into the action type (a malformed body gets HTTP 422 and the client raises).
#
# Honest limit: these rejections happen after signer recovery but do NOT prove the action
# hash is right — a wrong hash recovers a random address that is equally "not a
# validator/signer". Byte-parity is proven by the Python SDK parity fixtures in
# spec/hyperliquid/exchange_spec.rb, not by this script.
#
# SAFETY: the guard below is mandatory, runs first, and fails closed. Never remove or
# weaken it — this script runs unattended in the scheduled gate. Any `status: 'ok'`
# response stops the script immediately so no later (harmful) call runs.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_27_validator_actions.rb

require_relative 'test_helpers'

sdk = build_sdk # hard-wired to testnet; never construct a mainnet SDK in this script
separator('TEST 27: validator operator actions (rejection-only)')

# --- Safety guard (mandatory, first, fail-closed) ---
me = sdk.exchange.address.downcase

# (a) Plain user only. An agent/API-wallet key acts for its master account on L1 actions, and
#     vault/subAccount roles are not ours to probe — refuse anything but role == 'user'.
role = sdk.info.user_role(me)
unless role.is_a?(Hash) && role['role'] == 'user'
  abort red("Refusing to run: userRole is #{role.inspect}, need {'role' => 'user'}")
end

# (b) Not a validator or a validator signer (fail closed on an unexpected/empty response).
summaries = sdk.info.validator_summaries
abort red('Refusing to run: validatorSummaries unavailable') unless summaries.is_a?(Array) && !summaries.empty?
if summaries.any? { |v| v['validator'].to_s.downcase == me || v['signer'].to_s.downcase == me }
  abort red('Refusing to run: wallet is a validator or validator signer')
end

# (c) No self-delegation (catches a validator missing from summaries; testnet returned exactly
#     250 entries on 2026-10-01, so the list may be capped).
delegations = sdk.info.delegations(me)
abort red('Refusing to run: delegations unavailable') unless delegations.is_a?(Array)
if delegations.any? { |d| d['validator'].to_s.downcase == me }
  abort red('Refusing to run: wallet self-delegates (is a validator)')
end

puts green('Safety guard passed: plain user, not a validator/signer, no self-delegation')
puts

def expect_rejection(label, result, expected_substring)
  if result.is_a?(Hash) && result['status'] == 'ok'
    puts red("#{label}: SAFETY STOP — action was ACCEPTED (#{result.inspect}); wallet controls a validator")
    exit 1
  elsif result.is_a?(Hash) && result['status'] == 'err' && result['response'].is_a?(String) &&
        result['response'].include?(expected_substring)
    puts green("#{label}: structured rejection as expected (#{result['response']})")
  else
    $test_failed = true
    puts red("#{label}: unexpected response #{result.inspect}")
  end
end

# --- CSignerAction + validatorL1Stream ---
# jail_self runs last: the only harmful call here runs only after two rejections have
# already proved the wallet is not a signer.
expect_rejection('validator_l1_stream',
                 sdk.exchange.validator_l1_stream(risk_free_rate: '0.04'),
                 'Unknown validator')
expect_rejection('c_signer_unjail_self',
                 sdk.exchange.c_signer_unjail_self,
                 'Signer invalid or inactive for current epoch')
expect_rejection('c_signer_jail_self',
                 sdk.exchange.c_signer_jail_self,
                 'Signer invalid or inactive for current epoch')

# --- CValidatorAction ---
# change_profile sends unjailed: true with every other field nil: for any account this is at
# worst a no-op/unjail, never a jail or rename.
expect_rejection('c_validator_change_profile',
                 sdk.exchange.c_validator_change_profile(unjailed: true),
                 'Unknown validator')
expect_rejection('c_validator_unregister',
                 sdk.exchange.c_validator_unregister,
                 'Action disabled on this chain')

# c_validator_register is NEVER sent: it moves real stake if it ever succeeded, and the server
# has been observed to get past identity checks for an ordinary wallet.

test_passed('Test 27 validator actions')
