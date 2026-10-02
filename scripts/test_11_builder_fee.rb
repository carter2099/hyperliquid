#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 11: Builder Fee (Approve + Order with Builder)
# Approve a builder fee, require max_builder_fee >= 10 back from Info, then
# place a resting order with the builder param and cancel it (confirmed via
# open_orders). `ensure` cancels this script's own order if it is still open.
#
# The builder is a third-party address (the TS SDK's test builder). Builders must
# keep >= 100 USDC perp account value and standard abstraction to be approvable.
# An Info preflight checks that; if the builder drifted ineligible and the
# approval is rejected, the script reports GUARDED (the rejection must not be a
# signer-class error, which would mean the signature recovered to an unknown user).

require_relative 'test_helpers'

TEST_NAME = 'Test 11 Builder Fee'
PERP_COIN = 'BTC'
BUILDER = '0xe019d6167E7e324aEd003d94098496b6d986aB05' # TS SDK test builder; must keep >=100 USDC perp value + standard abstraction
MAX_FEE_RATE = '0.01%'
BUILDER_FEE = 10 # tenths of a basis point (1bp)
SIGNER_CLASS = /does not exist|User or API Wallet|Must deposit before performing actions/i

def first_status(result)
  response = result.is_a?(Hash) ? result['response'] : nil
  data = response.is_a?(Hash) ? response['data'] : nil
  data.is_a?(Hash) ? data.dig('statuses', 0) : nil
end

def open_oids(sdk)
  sdk.info.open_orders(sdk.exchange.address).map { |o| o['oid'] }
end

# Polls open_orders (read-after-write lag) until the oid's presence matches.
def await_open(sdk, oid, present:, attempts: 5)
  attempts.times do |i|
    return true if open_oids(sdk).include?(oid) == present

    sleep 1 unless i == attempts - 1
  end
  false
end

# Places an order that must rest; records its oid in own_oids. Returns the oid or nil.
def place_resting!(sdk, own_oids, label, **order)
  result = sdk.exchange.order(**order)
  oid = check_result(result, label)
  unless oid.is_a?(Integer)
    fail!("#{label}: expected a resting order, got #{result.inspect}") if oid
    return nil
  end
  own_oids << oid
  return oid if await_open(sdk, oid, present: true)

  fail!("#{label}: oid #{oid} reported resting but is not in open_orders")
  nil
end

def cancel_confirmed!(sdk, coin, oid)
  result = sdk.exchange.cancel(coin: coin, oid: oid)
  dump_status(result)
  return fail!("Cancel #{oid}: expected status \"success\", got #{result.inspect}") unless first_status(result) == 'success'

  if await_open(sdk, oid, present: false)
    puts green("Cancel confirmed: #{oid} is no longer in open_orders")
  else
    fail!("Cancel #{oid}: reported success but the order is still in open_orders")
  end
end

# Cancels this script's own orders that are still open. Reports, never raises.
def cancel_own_orders(sdk, coin, own_oids)
  return if own_oids.empty?

  (open_oids(sdk) & own_oids).each do |oid|
    puts "Cleanup: cancelling own order #{oid}..."
    result = sdk.exchange.cancel(coin: coin, oid: oid)
    fail!("Cleanup: cancel #{oid} failed: #{result.inspect}") unless first_status(result) == 'success'
  end
rescue StandardError => e
  fail!("Cleanup error (#{e.class}): #{e.message}")
end

def run(sdk, own_oids)
  btc_price = sdk.info.all_mids[PERP_COIN]&.to_f
  return fail!("Could not get #{PERP_COIN} mid price") unless btc_price&.positive?

  sz_decimals = sdk.info.meta['universe'].find { |a| a['name'] == PERP_COIN }['szDecimals']
  limit_price = (btc_price * 1.50).round(0).to_i
  perp_size = (20.0 / btc_price).ceil(sz_decimals)

  puts "#{PERP_COIN} mid: $#{btc_price.round(2)}"
  puts "Limit price: $#{limit_price} (50% above mid - won't fill)"
  puts "Size: #{perp_size} BTC"
  puts "Builder: #{BUILDER} (fee: #{BUILDER_FEE} = 1bp)"
  puts

  puts 'Placing limit SELL order with builder fee...'
  oid = place_resting!(sdk, own_oids, 'Limit short with builder',
                       coin: PERP_COIN, is_buy: false, size: perp_size, limit_px: limit_price,
                       order_type: { limit: { tif: 'Gtc' } }, builder: { b: BUILDER, f: BUILDER_FEE })
  return unless oid

  wait_with_countdown(WAIT_SECONDS, 'Order resting. Waiting before cancel...')

  puts "Canceling order #{oid}..."
  cancel_confirmed!(sdk, PERP_COIN, oid)
end

sdk = build_sdk
separator('TEST 11: Builder Fee (Approve + Order with Builder)')

# Step 1: Preflight builder eligibility, then approve builder fee
b_value = sdk.info.user_state(BUILDER).dig('marginSummary', 'accountValue').to_f
b_mode = sdk.info.user_abstraction(BUILDER)
eligible = b_value >= 100 && %w[disabled default].include?(b_mode)
puts "Builder #{BUILDER}: accountValue=#{b_value} abstraction=#{b_mode.inspect} " \
     "(#{eligible ? 'eligible' : 'INELIGIBLE'})"
puts

puts "Approving builder fee for #{BUILDER} (max #{MAX_FEE_RATE})..."
result = sdk.exchange.approve_builder_fee(builder: BUILDER, max_fee_rate: MAX_FEE_RATE)
dump_status(result)
approved = result.is_a?(Hash) && result['status'] == 'ok'
if approved
  puts green('Builder fee approved')
elsif eligible
  fail!("Approval of an eligible builder: expected status ok, got #{result.inspect}")
  test_passed(TEST_NAME)
else
  text = result.is_a?(Hash) ? result['response'].to_s : result.inspect
  if text.match?(SIGNER_CLASS)
    fail!("Approval rejected with a signer-class error (signature did not recover to this wallet): #{text}")
    test_passed(TEST_NAME)
  end
  finish_guarded(TEST_NAME, "builder ineligible (accountValue=#{b_value}, abstraction=#{b_mode.inspect}); " \
                            "approval rejected with non-signer error: #{text}")
end
puts

wait_with_countdown(WAIT_SECONDS, 'Waiting before checking approval...')

# Step 2: Verify approval via Info API
approval = sdk.info.max_builder_fee(sdk.exchange.address, BUILDER).to_i
puts "Max builder fee: #{approval.inspect}"
if approval < BUILDER_FEE
  fail!("max builder fee #{approval} < #{BUILDER_FEE} after a successful approval")
  test_passed(TEST_NAME)
end
puts

# Step 3: Place order with builder param, then cancel
own_oids = []
begin
  run(sdk, own_oids)
ensure
  cancel_own_orders(sdk, PERP_COIN, own_oids)
end

test_passed(TEST_NAME)
