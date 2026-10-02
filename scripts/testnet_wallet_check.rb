#!/usr/bin/env ruby
# frozen_string_literal: true

# Testnet wallet precondition check for the integration suite.
#
# Default: read-only report (abstraction, balances, open positions/orders,
# staking, builder eligibility). Exit 0.
# --fix:  close leftover positions/orders, switch a unified wallet to standard
#         ('disabled') abstraction, and rebalance USDC so perp >= $60 withdrawable
#         and spot >= $40 available. Never run from a runner.
#         Exit 0 when both targets are met, 2 when underfunded (no state change
#         beyond what was already safe), 1 on an unexpected API result.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/testnet_wallet_check.rb [--fix]

require_relative 'test_helpers'

BUILDER = '0xe019d6167E7e324aEd003d94098496b6d986aB05' # keep in sync with test_11
# Keep PERP_TARGET < 100: test_17's pre-wire-check default creates a real $100 vault
# whenever perp withdrawable >= 100.
PERP_TARGET = 60
SPOT_TARGET = 40
MIN_TOTAL = PERP_TARGET + SPOT_TARGET
STANDARD_MODES = %w[disabled default].freeze

def snapshot(sdk, addr)
  state = sdk.info.user_state(addr)
  spot = sdk.info.spot_balances(addr)
  usdc = (spot['balances'] || []).find { |b| b['coin'] == 'USDC' } || {}
  {
    abstraction: sdk.info.user_abstraction(addr),
    perp_value: state.dig('marginSummary', 'accountValue').to_f,
    perp_withdrawable: state['withdrawable'].to_f,
    positions: (state['assetPositions'] || []).map { |p| p['position'] }
                                              .reject { |p| p['szi'].to_f.zero? },
    orders: sdk.info.open_orders(addr),
    spot_usdc_total: usdc['total'].to_f,
    spot_usdc_avail: usdc['total'].to_f - usdc['hold'].to_f
  }
end

# Unified balances live in the spot clearinghouse; perp states are not meaningful
# there, so summing both would double-count.
def total_usdc(snap)
  return snap[:spot_usdc_total] if snap[:abstraction] == 'unifiedAccount'

  snap[:spot_usdc_total] + snap[:perp_value]
end

def money(value)
  format('$%.2f', value)
end

def targets_met?(snap)
  STANDARD_MODES.include?(snap[:abstraction]) &&
    snap[:perp_withdrawable] >= PERP_TARGET &&
    snap[:spot_usdc_avail] >= SPOT_TARGET
end

def report(sdk, addr, snap)
  puts "Abstraction:          #{snap[:abstraction].inspect}" \
       "#{STANDARD_MODES.include?(snap[:abstraction]) ? ' (standard)' : ''}"
  puts "Perp account value:   #{money(snap[:perp_value])}"
  puts "Perp withdrawable:    #{money(snap[:perp_withdrawable])} (target >= #{money(PERP_TARGET)})"
  puts "Spot USDC total:      #{money(snap[:spot_usdc_total])}"
  puts "Spot USDC available:  #{money(snap[:spot_usdc_avail])} (target >= #{money(SPOT_TARGET)})"
  puts "Total USDC:           #{money(total_usdc(snap))} (minimum #{money(MIN_TOTAL)})"
  puts "Open positions:       #{snap[:positions].length}"
  snap[:positions].each { |p| puts "  #{p['coin']} szi=#{p['szi']} entryPx=#{p['entryPx']}" }
  puts "Open orders:          #{snap[:orders].length}"
  snap[:orders].each { |o| puts "  #{o['coin']} oid=#{o['oid']} #{o['side']} #{o['sz']} @ #{o['limitPx']}" }
  puts "Delegator summary:    #{sdk.info.delegator_summary(addr).inspect}"
  puts "Vault equities:       #{sdk.info.user_vault_equities(addr).inspect}"

  b_value = sdk.info.user_state(BUILDER).dig('marginSummary', 'accountValue').to_f
  b_mode = sdk.info.user_abstraction(BUILDER)
  eligible = b_value >= 100 && STANDARD_MODES.include?(b_mode)
  puts "Builder #{BUILDER}:"
  puts "  accountValue=#{money(b_value)} abstraction=#{b_mode.inspect} " \
       "#{eligible ? green('eligible') : red('INELIGIBLE (needs >= $100 perp value + standard mode)')}"
  puts "  Max builder fee approved by this wallet: #{sdk.info.max_builder_fee(addr, BUILDER).inspect}"
  puts
  puts(targets_met?(snap) ? green('Wallet meets integration-suite targets.') : red('Wallet does NOT meet targets.'))
end

def require_ok(result, what)
  puts "  #{result.inspect}"
  dump_status(result)
  return if result.is_a?(Hash) && result['status'] == 'ok'

  puts red("ABORT: #{what} did not return status ok")
  exit 1
end

def close_leftovers(sdk, addr, snap)
  return snap if snap[:orders].empty? && snap[:positions].empty?

  snap[:orders].each do |o|
    puts "Cancelling order #{o['coin']} oid=#{o['oid']}..."
    require_ok(sdk.exchange.cancel(coin: o['coin'], oid: o['oid']), 'cancel')
  end
  snap[:positions].each do |p|
    puts "Closing position #{p['coin']} szi=#{p['szi']}..."
    require_ok(sdk.exchange.market_close(coin: p['coin'], slippage: PERP_SLIPPAGE + 0.20), 'market_close')
  end
  sleep WAIT_SECONDS
  snap = snapshot(sdk, addr)
  return snap if snap[:orders].empty? && snap[:positions].empty?

  puts red("ABORT: #{snap[:orders].length} order(s) / #{snap[:positions].length} position(s) remain")
  exit 1
end

def switch_to_standard(sdk, addr, snap)
  return snap if STANDARD_MODES.include?(snap[:abstraction])

  unless snap[:abstraction] == 'unifiedAccount'
    puts red("ABORT: abstraction #{snap[:abstraction].inspect} is not unifiedAccount; not touching it")
    exit 1
  end

  puts "Switching #{addr} from unifiedAccount to standard ('disabled')..."
  require_ok(sdk.exchange.user_set_abstraction(user: addr, abstraction: 'disabled'), 'user_set_abstraction')
  sleep WAIT_SECONDS
  snap = snapshot(sdk, addr)
  return snap if STANDARD_MODES.include?(snap[:abstraction])

  puts red("ABORT: abstraction is #{snap[:abstraction].inspect} after the switch")
  exit 1
end

def underfunded_after_switch(snap)
  puts red("UNDERFUNDED after switch: perp_withdrawable=#{money(snap[:perp_withdrawable])} " \
           "spot_avail=#{money(snap[:spot_usdc_avail])}")
  exit 2
end

def rebalance(sdk, addr, snap)
  if snap[:perp_withdrawable] < PERP_TARGET
    need = (PERP_TARGET - snap[:perp_withdrawable]).ceil
    underfunded_after_switch(snap) unless snap[:spot_usdc_avail] - need >= SPOT_TARGET
    puts "Transferring $#{need} spot -> perp..."
    require_ok(sdk.exchange.usd_class_transfer(amount: need.to_s, to_perp: true), 'usd_class_transfer')
  elsif snap[:spot_usdc_avail] < SPOT_TARGET
    need = (SPOT_TARGET - snap[:spot_usdc_avail]).ceil
    underfunded_after_switch(snap) unless snap[:perp_withdrawable] - need >= PERP_TARGET
    puts "Transferring $#{need} perp -> spot..."
    require_ok(sdk.exchange.usd_class_transfer(amount: need.to_s, to_perp: false), 'usd_class_transfer')
  else
    puts 'Balances already meet targets; no transfer.'
    return snap
  end
  sleep WAIT_SECONDS
  snapshot(sdk, addr)
end

fix = ARGV.include?('--fix')
sdk = build_sdk
addr = sdk.exchange.address
separator("TESTNET WALLET CHECK#{fix ? ' --fix' : ''}")

snap = snapshot(sdk, addr)
report(sdk, addr, snap)
exit 0 unless fix

separator('FIX: leftover orders/positions')
snap = close_leftovers(sdk, addr, snap)

total = total_usdc(snap)
if total < MIN_TOTAL
  puts red("UNDERFUNDED: total USDC $#{format('%.2f', total)} < $#{MIN_TOTAL}; staying in current mode")
  exit 2
end

separator('FIX: abstraction')
snap = switch_to_standard(sdk, addr, snap)

separator('FIX: rebalance')
snap = rebalance(sdk, addr, snap)

separator('FINAL STATE')
report(sdk, addr, snap)
exit(targets_met?(snap) ? 0 : 2)
