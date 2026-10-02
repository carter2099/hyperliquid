#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 24: perpDeploy wire check (structured rejection)
#
# Sends HIP-3 perpDeploy L1 actions against a perp dex that does not exist. The wallet is
# not a deployer, so every call is rejected, but only after the server has recovered the
# signer. A structured rejection from ACCEPTED proves the action hash, key order, and
# types are correct. "User or API Wallet ... does not exist" means the signature recovered
# to a random address (SDK hash bug); an HTTP 422 deserialize error means a malformed shape.
# Each accepted rejection is repeated from a throwaway (never funded) key, which must get a
# signature-class rejection that differs from the wallet's: that proves on every run the
# ACCEPTED text depended on the recovered signer.
#
# No state changes and no gas: the target dex does not exist, and register_asset* is never
# sent (it touches the deploy auction).
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_24_perp_deploy_wire.rb

require_relative 'test_helpers'

NAME = 'Test 24 perp_deploy wire check'

# Live server error strings observed as the `error` of included perpDeploy txs in explorer
# `userDetails` (2026-10-01 probe), i.e. emitted after signer recovery.
ACCEPTED = /Invalid perp DEX|Invalid perp deployer|Unknown coin|Action disabled when unified account is active|User must have abstractions disabled|Perp DEX disabled|Invalid oracle updater/

sdk = build_sdk
separator('TEST 24: perpDeploy wire check (structured rejection)')

existing = sdk.info.perp_dexs.compact.map { |d| d['name'] }
dex = %w[qzqz zqzq qqzz zzqq].find { |name| !existing.include?(name) }
unless dex
  fail!('FAILED: every candidate dex name already exists; pick new unused names')
  test_passed(NAME)
end
coin = "#{dex}:WIRE"
puts "Target (nonexistent) dex: #{dex}, coin: #{coin}"
puts

def response_message(result)
  response = result.is_a?(Hash) ? result['response'] : nil
  response.is_a?(String) ? response : response.inspect
end

# Yields the wallet's exchange, then (only after an ACCEPTED rejection) the throwaway's.
def check_wire(name, wallet_exchange, control_exchange)
  puts "#{name}..."
  result = yield wallet_exchange
  message = response_message(result)

  if result.is_a?(Hash) && result['status'] == 'ok'
    fail!("  FAILED: unexpected ok on a nonexistent dex (investigate immediately): #{result.inspect}")
  elsif message.match?(/User or API Wallet .* does not exist/)
    fail!("  FAILED: signature recovered to an unknown address (hash/signature bug): #{message}")
  elsif result.is_a?(Hash) && result['status'] == 'err' && message.match?(ACCEPTED)
    puts green("  structured rejection: #{message}")
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
rescue Hyperliquid::Error => e
  fail!("  FAILED: #{e.class}: #{e.message}")
ensure
  sleep 1
end

wallet = sdk.exchange
control = throwaway_sdk.exchange
address = wallet.address

check_wire('perp_deploy_set_oracle', wallet, control) do |exchange|
  exchange.perp_deploy_set_oracle(dex: dex, oracle_pxs: { coin => '1' }, all_mark_pxs: [],
                                  external_perp_pxs: { coin => '1' })
end

check_wire('perp_deploy_halt_trading', wallet, control) do |exchange|
  exchange.perp_deploy_halt_trading(coin: coin, is_halted: false)
end

check_wire('perp_deploy_disable_dex', wallet, control) do |exchange|
  exchange.perp_deploy_disable_dex(dex: dex)
end

check_wire('perp_deploy_set_funding_multipliers', wallet, control) do |exchange|
  exchange.perp_deploy_set_funding_multipliers(multipliers: { coin => '1' })
end

check_wire('perp_deploy_set_funding_interest_rates', wallet, control) do |exchange|
  exchange.perp_deploy_set_funding_interest_rates(rates: { coin => '0' })
end

check_wire('perp_deploy_set_funding_clamps', wallet, control) do |exchange|
  exchange.perp_deploy_set_funding_clamps(clamps: { coin => '0.0003' })
end

check_wire('perp_deploy_insert_margin_table', wallet, control) do |exchange|
  exchange.perp_deploy_insert_margin_table(dex: dex, description: 'wire',
                                           margin_tiers: [{ lower_bound: 0, max_leverage: 10 }])
end

check_wire('perp_deploy_set_margin_table_ids', wallet, control) do |exchange|
  exchange.perp_deploy_set_margin_table_ids(margin_table_ids: { coin => 10 })
end

check_wire('perp_deploy_set_margin_modes', wallet, control) do |exchange|
  exchange.perp_deploy_set_margin_modes(margin_modes: { coin => 'noCross' })
end

check_wire('perp_deploy_set_open_interest_caps', wallet, control) do |exchange|
  exchange.perp_deploy_set_open_interest_caps(caps: { coin => 1_000_000 })
end

check_wire('perp_deploy_set_fee_recipient', wallet, control) do |exchange|
  exchange.perp_deploy_set_fee_recipient(dex: dex, fee_recipient: address)
end

check_wire('perp_deploy_set_deployer_fees', wallet, control) do |exchange|
  exchange.perp_deploy_set_deployer_fees(fees: { coin => { scale: '1', growth_mode: false } })
end

check_wire('perp_deploy_set_sub_deployers', wallet, control) do |exchange|
  exchange.perp_deploy_set_sub_deployers(
    dex: dex, sub_deployers: [{ variant: 'setOracle', user: address, allowed: false }]
  )
end

check_wire('perp_deploy_set_perp_annotation', wallet, control) do |exchange|
  exchange.perp_deploy_set_perp_annotation(coin: coin, category: 'test', description: 'wire check', keywords: [])
end

test_passed(NAME)
