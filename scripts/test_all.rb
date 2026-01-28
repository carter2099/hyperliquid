#!/usr/bin/env ruby
# frozen_string_literal: true

# Hyperliquid Ruby SDK - Testnet Integration Tests (Runner)
#
# Runs all integration test scripts in order.
# Each script can also be run individually for debugging.
#
# Prerequisites:
#   - Testnet wallet with USDC balance
#   - Get testnet funds from: https://app.hyperliquid-testnet.xyz
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_all.rb
#
# Run a single test:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_08_usd_class_transfer.rb
#
# Note: These scripts execute real trades on testnet. No real funds are at risk.

SCRIPTS = [
  'test_01_spot_market_roundtrip.rb',
  'test_02_spot_limit_order.rb',
  'test_03_perp_market_roundtrip.rb',
  'test_04_perp_limit_order.rb',
  'test_05_update_leverage.rb',
  'test_06_modify_order.rb',
  'test_07_market_close.rb',
  'test_08_usd_class_transfer.rb',
  'test_09_sub_account_lifecycle.rb',
  'test_10_vault_transfer.rb'
].freeze

def green(text)
  "\e[32m#{text}\e[0m"
end

def red(text)
  "\e[31m#{text}\e[0m"
end

unless ENV['HYPERLIQUID_PRIVATE_KEY']
  puts red('Error: Set HYPERLIQUID_PRIVATE_KEY environment variable')
  puts 'Usage: HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_all.rb'
  exit 1
end

scripts_dir = __dir__
passed = []
failed = []

SCRIPTS.each do |script|
  path = File.join(scripts_dir, script)
  puts
  puts '#' * 60
  puts "# Running: #{script}"
  puts '#' * 60

  success = system(RbConfig.ruby, path)

  if success
    passed << script
  else
    failed << script
    puts red("!!! #{script} exited with error !!!")
  end
end

puts
puts '=' * 60
puts 'INTEGRATION TEST SUMMARY'
puts '=' * 60
puts
puts "Passed: #{passed.length}/#{SCRIPTS.length}"
passed.each { |s| puts green("  [PASS] #{s}") }
if failed.any?
  puts
  puts "Failed: #{failed.length}/#{SCRIPTS.length}"
  failed.each { |s| puts red("  [FAIL] #{s}") }
end
puts
puts 'Check your testnet wallet for trade history:'
puts 'https://app.hyperliquid-testnet.xyz'
puts

exit(failed.empty? ? 0 : 1)
