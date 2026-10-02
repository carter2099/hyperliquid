#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 22: HIP-4 outcome deployer actions (structured-rejection wire check)
#
# Sends HIP-4 deployer actions (outcomeDeploy, activateOutcomeDeployer deactivate) that
# the server must reject for a wallet that is not a deployer of the target venue. A
# business rejection ("Incorrect deployer", "Invalid outcome", ...) proves the action
# deserialized; a "does not exist" / "must deposit" error means the signed hash differed
# (wrong key order or types); an HTTP error means the shape did not deserialize. Each
# rejected probe is repeated from a throwaway (never funded) key, which must get a
# signature-class rejection that differs from the wallet's: that proves on every run the
# business rejection depended on the L1 signature recovering our wallet. Moves no funds
# and changes no state.
#
# Never sends activate_outcome_deployer: it could claim a venue and lock stake.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_22_outcome_deploy.rb

require_relative 'test_helpers'

NAME = 'Test 22 outcome deploy'

sdk = build_sdk
separator('TEST 22: HIP-4 outcome deployer actions')

meta = sdk.info.outcome_meta
signer = sdk.exchange.address.downcase
role = sdk.info.user_role(signer)
identities = [signer]
identities << role.dig('data', 'user').downcase if role.is_a?(Hash) && role['role'] == 'agent' && role.dig('data', 'user')

deployers = meta['deployers'] || []
deployer_addresses = deployers.flat_map do |entry|
  sub = (entry['subDeployers'] || []).flat_map { |_variant, users| users }
  [entry['deployer'], *sub].map(&:downcase)
end

if identities.any? { |id| deployer_addresses.include?(id) }
  finish_skipped(NAME, 'wallet is a HIP-4 (sub-)deployer; refusing to send probes')
end

finish_skipped(NAME, 'outcomeMeta lists no deployers; nothing to probe') if deployers.empty?

venue = deployers.first['venue']
puts "Target venue: #{venue} (deployer #{deployers.first['deployer']})"
outcome = meta['outcomes'].find { |o| o['venue'] == venue }
settle_inputs =
  if outcome
    { outcome: outcome['outcome'], name: outcome['name'], description: outcome['description'],
      side_names: outcome['sideSpecs'].map { |s| s['name'] } }
  else
    { outcome: 0, name: 'x', description: 'x', side_names: %w[Yes No] }
  end
puts "Settle probe outcome: #{settle_inputs[:outcome]}"
puts

# Yields the wallet's exchange, then (only after a structured rejection) the throwaway's.
def probe(label, wallet_exchange, control_exchange)
  puts "#{label}..."
  result = yield wallet_exchange
  if !result.is_a?(Hash)
    fail!("  unexpected response: #{result.inspect}")
  elsif result['status'] == 'ok'
    fail!("  UNEXPECTED ACCEPTANCE: #{result.inspect} (state may have changed; investigate)")
  elsif result['response'].to_s =~ /does not exist|must deposit/i
    fail!("  signature/hash mismatch: #{result['response']}")
  else
    puts green("  structured rejection: #{result['response']}")
    control_text =
      begin
        control = yield control_exchange
        control.is_a?(Hash) ? control['response'].to_s : control.inspect
      rescue Hyperliquid::Error => e
        "raised #{e.class}: #{e.message}"
      end
    assert_signer_dependent(label, result['response'].to_s, control_text)
  end
rescue Hyperliquid::Error => e
  fail!("  request failed: #{e.message} (status #{e.status_code.inspect}) #{e.response_body}")
end

wallet = sdk.exchange
control = throwaway_sdk.exchange

probe('deactivate_outcome_deployer', wallet, control, &:deactivate_outcome_deployer)

probe('register_standalone_outcome_from_template', wallet, control) do |exchange|
  exchange.register_standalone_outcome_from_template(
    venue: venue, template_id: 'binaryPrice', keyword_to_value: { 'perp' => 'BTC' }, deployer_fee_scale: '0'
  )
end

probe('settle_outcome', wallet, control) do |exchange|
  exchange.settle_outcome(venue: venue, settle_fraction: '0', **settle_inputs)
end

probe('register_question_from_template', wallet, control) do |exchange|
  exchange.register_question_from_template(
    venue: venue, template_id: 'x', keyword_to_value: {}, deployer_fee_scale: '0',
    named_outcomes: [{ template_id: 'y', keyword_to_value: {} }]
  )
end

probe('register_and_associate_named_outcome_from_template', wallet, control) do |exchange|
  exchange.register_and_associate_named_outcome_from_template(
    venue: venue, question: 0, template_id: 'y', keyword_to_value: {}
  )
end

probe('set_outcome_sub_deployers', wallet, control) do |exchange|
  exchange.set_outcome_sub_deployers(venue: venue, changes: [{ variant: 'settleOutcome', user: signer, allowed: false }])
end

probe('settle_question', wallet, control) do |exchange|
  exchange.settle_question(
    venue: venue, question: 0, name: 'x', description: 'x',
    settlements: [{ outcome: 0, settle_fraction: '1', name: 'x', description: 'x', side_names: %w[Yes No] }]
  )
end

test_passed(NAME)
