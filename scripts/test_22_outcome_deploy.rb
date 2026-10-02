#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 22: HIP-4 outcome deployer actions (structured-rejection wire check)
#
# Sends HIP-4 deployer actions (outcomeDeploy, activateOutcomeDeployer deactivate) that
# the server must reject for a wallet that is not a deployer of the target venue. A
# business rejection ("Incorrect deployer", "Invalid outcome", ...) proves the action
# deserialized and its L1 signature recovered our wallet; a "does not exist" / "must
# deposit" error means the signed hash differed (wrong key order or types); an HTTP
# error means the shape did not deserialize. Moves no funds and changes no state.
#
# Never sends activate_outcome_deployer: it could claim a venue and lock stake.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_22_outcome_deploy.rb

require_relative 'test_helpers'

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
  puts red('WARNING: wallet is a HIP-4 (sub-)deployer; refusing to send probes')
  test_passed('Test 22 outcome deploy')
  exit 0
end

if deployers.empty?
  puts red('WARNING: outcomeMeta lists no deployers; skipping probes')
  test_passed('Test 22 outcome deploy')
  exit 0
end

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

def probe(label)
  puts "#{label}..."
  result = yield
  if !result.is_a?(Hash)
    $test_failed = true
    puts red("  unexpected response: #{result.inspect}")
  elsif result['status'] == 'ok'
    $test_failed = true
    puts red("  UNEXPECTED ACCEPTANCE: #{result.inspect} (state may have changed; investigate)")
  elsif result['response'].to_s =~ /does not exist|must deposit/i
    $test_failed = true
    puts red("  signature/hash mismatch: #{result['response']}")
  else
    puts green("  structured rejection: #{result['response']}")
  end
rescue Hyperliquid::Error => e
  $test_failed = true
  puts red("  request failed: #{e.message} (status #{e.status_code.inspect}) #{e.response_body}")
end

exchange = sdk.exchange

probe('deactivate_outcome_deployer') { exchange.deactivate_outcome_deployer }

probe('register_standalone_outcome_from_template') do
  exchange.register_standalone_outcome_from_template(
    venue: venue, template_id: 'binaryPrice', keyword_to_value: { 'perp' => 'BTC' }, deployer_fee_scale: '0'
  )
end

probe('settle_outcome') do
  exchange.settle_outcome(venue: venue, settle_fraction: '0', **settle_inputs)
end

probe('register_question_from_template') do
  exchange.register_question_from_template(
    venue: venue, template_id: 'x', keyword_to_value: {}, deployer_fee_scale: '0',
    named_outcomes: [{ template_id: 'y', keyword_to_value: {} }]
  )
end

probe('register_and_associate_named_outcome_from_template') do
  exchange.register_and_associate_named_outcome_from_template(
    venue: venue, question: 0, template_id: 'y', keyword_to_value: {}
  )
end

probe('set_outcome_sub_deployers') do
  exchange.set_outcome_sub_deployers(venue: venue, changes: [{ variant: 'settleOutcome', user: signer, allowed: false }])
end

probe('settle_question') do
  exchange.settle_question(
    venue: venue, question: 0, name: 'x', description: 'x',
    settlements: [{ outcome: 0, settle_fraction: '1', name: 'x', description: 'x', side_names: %w[Yes No] }]
  )
end

test_passed('Test 22 outcome deploy')
