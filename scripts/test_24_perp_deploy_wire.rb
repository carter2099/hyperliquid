#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 24: perpDeploy wire check (structured rejection)
#
# Sends HIP-3 perpDeploy L1 actions against a perp dex that does not exist. The wallet is
# not a deployer, so every call is rejected, but only after the server has recovered the
# signer. A structured rejection from ACCEPTED proves the action hash, key order, and
# types are correct. "User or API Wallet ... does not exist" means the signature recovered
# to a random address (SDK hash bug); an HTTP 422 deserialize error means a malformed shape.
#
# No state changes and no gas: the target dex does not exist, and register_asset* is never
# sent (it touches the deploy auction).
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_24_perp_deploy_wire.rb

require_relative 'test_helpers'

# Live server error strings observed as the `error` of included perpDeploy txs in explorer
# `userDetails` (2026-10-01 probe), i.e. emitted after signer recovery.
ACCEPTED = /Invalid perp DEX|Invalid perp deployer|Unknown coin|Action disabled when unified account is active|User must have abstractions disabled|Perp DEX disabled|Invalid oracle updater/

sdk = build_sdk
separator('TEST 24: perpDeploy wire check (structured rejection)')

existing = sdk.info.perp_dexs.compact.map { |d| d['name'] }
dex = %w[qzqz zqzq qqzz zzqq].find { |name| !existing.include?(name) }
unless dex
  puts red('FAILED: every candidate dex name already exists; pick new unused names')
  $test_failed = true
  test_passed('Test 24 perp_deploy wire check')
end
coin = "#{dex}:WIRE"
puts "Target (nonexistent) dex: #{dex}, coin: #{coin}"
puts

def check_wire(name)
  puts "#{name}..."
  result = yield
  response = result.is_a?(Hash) ? result['response'] : nil
  message = response.is_a?(String) ? response : response.inspect

  if result.is_a?(Hash) && result['status'] == 'ok'
    $test_failed = true
    puts red("  FAILED: unexpected ok on a nonexistent dex (investigate immediately): #{result.inspect}")
  elsif message.match?(/User or API Wallet .* does not exist/)
    $test_failed = true
    puts red("  FAILED: signature recovered to an unknown address (hash/signature bug): #{message}")
  elsif result.is_a?(Hash) && result['status'] == 'err' && message.match?(ACCEPTED)
    puts green("  structured rejection (signature accepted): #{message}")
  else
    $test_failed = true
    puts red("  FAILED: unrecognized response: #{result.inspect}")
  end
rescue Hyperliquid::Error => e
  $test_failed = true
  puts red("  FAILED: #{e.class}: #{e.message}")
ensure
  sleep 1
end

check_wire('perp_deploy_set_oracle') do
  sdk.exchange.perp_deploy_set_oracle(dex: dex, oracle_pxs: { coin => '1' }, all_mark_pxs: [],
                                      external_perp_pxs: { coin => '1' })
end

check_wire('perp_deploy_halt_trading') do
  sdk.exchange.perp_deploy_halt_trading(coin: coin, is_halted: false)
end

check_wire('perp_deploy_disable_dex') do
  sdk.exchange.perp_deploy_disable_dex(dex: dex)
end

check_wire('perp_deploy_set_funding_multipliers') do
  sdk.exchange.perp_deploy_set_funding_multipliers(multipliers: { coin => '1' })
end

check_wire('perp_deploy_set_funding_interest_rates') do
  sdk.exchange.perp_deploy_set_funding_interest_rates(rates: { coin => '0' })
end

check_wire('perp_deploy_set_funding_clamps') do
  sdk.exchange.perp_deploy_set_funding_clamps(clamps: { coin => '0.0003' })
end

check_wire('perp_deploy_insert_margin_table') do
  sdk.exchange.perp_deploy_insert_margin_table(dex: dex, description: 'wire',
                                               margin_tiers: [{ lower_bound: 0, max_leverage: 10 }])
end

check_wire('perp_deploy_set_margin_table_ids') do
  sdk.exchange.perp_deploy_set_margin_table_ids(margin_table_ids: { coin => 10 })
end

check_wire('perp_deploy_set_margin_modes') do
  sdk.exchange.perp_deploy_set_margin_modes(margin_modes: { coin => 'noCross' })
end

check_wire('perp_deploy_set_open_interest_caps') do
  sdk.exchange.perp_deploy_set_open_interest_caps(caps: { coin => 1_000_000 })
end

check_wire('perp_deploy_set_fee_recipient') do
  sdk.exchange.perp_deploy_set_fee_recipient(dex: dex, fee_recipient: sdk.exchange.address)
end

check_wire('perp_deploy_set_deployer_fees') do
  sdk.exchange.perp_deploy_set_deployer_fees(fees: { coin => { scale: '1', growth_mode: false } })
end

check_wire('perp_deploy_set_sub_deployers') do
  sdk.exchange.perp_deploy_set_sub_deployers(
    dex: dex, sub_deployers: [{ variant: 'setOracle', user: sdk.exchange.address, allowed: false }]
  )
end

check_wire('perp_deploy_set_perp_annotation') do
  sdk.exchange.perp_deploy_set_perp_annotation(coin: coin, category: 'test', description: 'wire check', keywords: [])
end

test_passed('Test 24 perp_deploy wire check')
