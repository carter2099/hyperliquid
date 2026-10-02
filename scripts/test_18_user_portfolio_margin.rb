#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 18: userPortfolioMargin (user-signed exchange action)
#
# Default mode is a rejection wire check by design: the protocol enforces a $10k
# account value or $5m volume threshold for portfolio margin, which the agent
# testnet wallet meets neither of, so enabling is rejected with THRESHOLD_REJECTION.
# The same call is then sent from a throwaway (never funded) key, which must get a
# signature-class rejection that differs from the wallet's: together they prove on
# every run that the server recovered the signer to this wallet (EIP-712 signing
# works end-to-end) without changing state.
#
# If the wallet is eligible and enabling succeeds, the script disables portfolio
# margin again (in an `ensure`, so an error after enabling still restores it).
#
# WARNING: Toggling portfolio margin alters margining math on existing perp positions.
# Run only on a wallet without significant open exposure on testnet.
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_18_user_portfolio_margin.rb

require_relative 'test_helpers'

NAME = 'Test 18 user_portfolio_margin'
THRESHOLD_REJECTION = 'Portfolio margin requires'

def default_ok?(result)
  result.is_a?(Hash) && result['status'] == 'ok' && result.dig('response', 'type') == 'default'
end

sdk = build_sdk
separator('TEST 18: userPortfolioMargin')

user = sdk.exchange.address
puts "Wallet: #{user}"
puts

# true from the moment enable is sent until the server rejects it: an exception or an
# unexpected response may mean portfolio margin got enabled, and disabling is the safe restore.
restore = false
begin
  puts 'Enabling portfolio margin...'
  restore = true
  result = sdk.exchange.user_portfolio_margin(user: user, enabled: true)
  restore = false if result.is_a?(Hash) && result['status'] == 'err'

  if result.is_a?(Hash) && result['status'] == 'err' &&
     result['response'].to_s.include?(THRESHOLD_REJECTION)
    puts "  Rejected (eligibility threshold): #{result['response']}"
    puts 'Sending the same call from a throwaway key (signer-dependence control)...'
    control_text =
      begin
        control = throwaway_sdk.exchange.user_portfolio_margin(user: user, enabled: true)
        control.is_a?(Hash) ? control['response'].to_s : control.inspect
      rescue Hyperliquid::Error => e
        "raised #{e.class}: #{e.message}"
      end
    assert_signer_dependent('userPortfolioMargin', result['response'].to_s, control_text)
    puts green('  Wire check passed (signature recovered to this wallet; signer-dependent rejection).') unless $test_failed
  elsif default_ok?(result)
    puts green("Enable OK: #{result.inspect}")
    wait_with_countdown(WAIT_SECONDS, 'Settling before toggle back...')
  else
    fail!("user_portfolio_margin (enable) FAILED: #{result.inspect}")
  end
rescue StandardError => e
  fail!("user_portfolio_margin raised #{e.class}: #{e.message}")
ensure
  if restore
    puts 'Disabling portfolio margin...'
    begin
      result = sdk.exchange.user_portfolio_margin(user: user, enabled: false)
      if default_ok?(result)
        puts green("Disable OK: #{result.inspect}")
      else
        fail!("user_portfolio_margin (disable) FAILED: #{result.inspect}; run `ruby scripts/testnet_wallet_check.rb --fix`")
      end
    rescue StandardError => e
      fail!("user_portfolio_margin (disable) raised #{e.class}: #{e.message}; run `ruby scripts/testnet_wallet_check.rb --fix`")
    end
  end
end

test_passed(NAME)
