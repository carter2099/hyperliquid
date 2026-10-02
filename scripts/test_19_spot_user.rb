#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 19: spotUser (L1 exchange action)
#
# Toggles spot-dusting opt-out for the calling wallet. Sends two actions:
# opt_out: true, then opt_out: false, leaving the wallet in its original state
# (spot dusting opted-in by default). The opt-in runs in an `ensure`, so an error
# after the opt-out still restores the wallet.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_19_spot_user.rb

require_relative 'test_helpers'

NAME = 'Test 19 spot_user'

def default_ok?(result)
  result.is_a?(Hash) && result['status'] == 'ok' && result.dig('response', 'type') == 'default'
end

sdk = build_sdk
separator('TEST 19: spotUser (spot-dusting opt-out)')

puts "Wallet: #{sdk.exchange.address}"
puts

# true from the moment the opt-out is sent until the server rejects it: an exception or an
# unexpected response may mean the wallet got opted out, and opting back in is the safe restore.
restore = false
begin
  puts 'Opting out of spot dusting...'
  restore = true
  result = sdk.exchange.spot_user(opt_out: true)
  restore = false if result.is_a?(Hash) && result['status'] == 'err'

  if default_ok?(result)
    puts green("Opt-out OK: #{result.inspect}")
    wait_with_countdown(WAIT_SECONDS, 'Settling before toggle back...')
  else
    fail!("spot_user (opt_out: true) FAILED: #{result.inspect}")
  end
rescue StandardError => e
  fail!("spot_user (opt_out: true) raised #{e.class}: #{e.message}")
ensure
  if restore
    puts 'Opting back in to spot dusting...'
    begin
      result = sdk.exchange.spot_user(opt_out: false)
      if default_ok?(result)
        puts green("Opt-in OK: #{result.inspect}")
      else
        fail!("spot_user (opt_out: false) FAILED: #{result.inspect}; the wallet may be left opted out of spot dusting")
      end
    rescue StandardError => e
      fail!("spot_user (opt_out: false) raised #{e.class}: #{e.message}; the wallet may be left opted out of spot dusting")
    end
  end
end

test_passed(NAME)
