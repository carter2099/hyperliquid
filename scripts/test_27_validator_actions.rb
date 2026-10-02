#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 27: validator-operator actions (rejection-only wire check)
#
# Sends validator-operator L1 actions from a wallet that is NOT a validator or a
# validator signer, and expects a structured server rejection (`status: 'err'` with a
# known message) for each. A structured rejection proves the request deserialised
# server-side into the action type (a malformed body gets HTTP 422 and the client raises).
# Each expected rejection is then repeated from a throwaway (never funded) key, which must
# get a signature-class rejection ("User or API Wallet ... does not exist" / "Must deposit
# ...") that differs from the wallet's: a wrong hash recovers a random, nonexistent address
# and would get the control's text, so this proves on every run that the signer recovered
# to this wallet. Byte-parity is additionally pinned by the Python SDK parity fixtures in
# spec/hyperliquid/exchange_spec.rb.
#
# SAFETY: the guard below is mandatory, runs first, and fails closed. Never remove or
# weaken it — this script runs unattended in the scheduled gate. Any `status: 'ok'`
# response stops the script immediately so no later (harmful) call runs. The throwaway
# control key is never a validator or signer, so its calls cannot change anything.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_27_validator_actions.rb

require_relative 'test_helpers'

NAME = 'Test 27 validator actions'

# Fail-closed stop: records the failure, prints the RESULT line, and exits non-zero.
def refuse!(message)
  fail!(message)
  test_passed(NAME)
  exit 1
end

sdk = build_sdk # hard-wired to testnet; never construct a mainnet SDK in this script
separator('TEST 27: validator operator actions (rejection-only)')

# --- Safety guard (mandatory, first, fail-closed) ---
me = sdk.exchange.address.downcase

# (a) Plain user only. An agent/API-wallet key acts for its master account on L1 actions, and
#     vault/subAccount roles are not ours to probe — refuse anything but role == 'user'.
role = sdk.info.user_role(me)
refuse!("Refusing to run: userRole is #{role.inspect}, need {'role' => 'user'}") unless role.is_a?(Hash) && role['role'] == 'user'

# (b) Not a validator or a validator signer (fail closed on an unexpected/empty response).
summaries = sdk.info.validator_summaries
refuse!('Refusing to run: validatorSummaries unavailable') unless summaries.is_a?(Array) && !summaries.empty?
if summaries.any? { |v| v['validator'].to_s.downcase == me || v['signer'].to_s.downcase == me }
  refuse!('Refusing to run: wallet is a validator or validator signer')
end

# (c) No self-delegation (catches a validator missing from summaries; testnet returned exactly
#     250 entries on 2026-10-01, so the list may be capped).
delegations = sdk.info.delegations(me)
refuse!('Refusing to run: delegations unavailable') unless delegations.is_a?(Array)
refuse!('Refusing to run: wallet self-delegates (is a validator)') if delegations.any? { |d| d['validator'].to_s.downcase == me }

puts green('Safety guard passed: plain user, not a validator/signer, no self-delegation')
puts

# Yields the wallet's exchange, then (only after the expected rejection) the throwaway's.
def expect_rejection(label, expected_substring, wallet_exchange, control_exchange)
  result = yield wallet_exchange
  if result.is_a?(Hash) && result['status'] == 'ok'
    refuse!("#{label}: SAFETY STOP — action was ACCEPTED (#{result.inspect}); wallet controls a validator")
  elsif result.is_a?(Hash) && result['status'] == 'err' && result['response'].is_a?(String) &&
        result['response'].include?(expected_substring)
    puts green("#{label}: structured rejection as expected (#{result['response']})")
    control_text =
      begin
        control = yield control_exchange
        control.is_a?(Hash) ? control['response'].to_s : control.inspect
      rescue Hyperliquid::Error => e
        "raised #{e.class}: #{e.message}"
      end
    assert_signer_dependent(label, result['response'], control_text)
  else
    fail!("#{label}: unexpected response #{result.inspect}")
  end
end

wallet = sdk.exchange
control = throwaway_sdk.exchange

# --- CSignerAction + validatorL1Stream ---
# jail_self runs last: the only harmful call here runs only after two rejections have
# already proved the wallet is not a signer.
expect_rejection('validator_l1_stream', 'Unknown validator', wallet, control) do |exchange|
  exchange.validator_l1_stream(risk_free_rate: '0.04')
end
expect_rejection('c_signer_unjail_self', 'Signer invalid or inactive for current epoch', wallet, control,
                 &:c_signer_unjail_self)
expect_rejection('c_signer_jail_self', 'Signer invalid or inactive for current epoch', wallet, control,
                 &:c_signer_jail_self)

# --- CValidatorAction ---
# change_profile sends unjailed: true with every other field nil: for any account this is at
# worst a no-op/unjail, never a jail or rename.
expect_rejection('c_validator_change_profile', 'Unknown validator', wallet, control) do |exchange|
  exchange.c_validator_change_profile(unjailed: true)
end
expect_rejection('c_validator_unregister', 'Action disabled on this chain', wallet, control,
                 &:c_validator_unregister)

# c_validator_register is NEVER sent: it moves real stake if it ever succeeded, and the server
# has been observed to get past identity checks for an ordinary wallet.

test_passed(NAME)
