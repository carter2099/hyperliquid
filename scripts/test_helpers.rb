# frozen_string_literal: true

require_relative '../lib/hyperliquid'
require 'json'

WAIT_SECONDS = 3
SPOT_SLIPPAGE = 0.40  # 40% for illiquid testnet spot markets
PERP_SLIPPAGE = 0.05  # 5% for perp markets

def green(text)
  "\e[32m#{text}\e[0m"
end

def red(text)
  "\e[31m#{text}\e[0m"
end

$test_failed = false

def separator(title)
  puts
  puts '=' * 60
  puts title
  puts '=' * 60
  puts
end

def wait_with_countdown(seconds, message)
  puts message
  seconds.downto(1) do |i|
    print "\r  #{i} seconds remaining...  "
    sleep 1
  end
  puts "\r  Done!                      "
  puts
end

def api_error?(result)
  return false unless result.is_a?(Hash) && result['status'] == 'err'

  $test_failed = true
  puts red("FAILED: #{result['response']}")
  true
end

def check_result(result, operation)
  return false if api_error?(result)

  status = result.dig('response', 'data', 'statuses', 0)

  if status.is_a?(Hash) && status['error']
    $test_failed = true
    puts red("FAILED: #{status['error']}")
    return false
  end

  if status.is_a?(Hash) && status['resting']
    puts green("Order resting with OID: #{status['resting']['oid']}")
    return status['resting']['oid']
  end

  if status == 'success' || (status.is_a?(Hash) && status['filled'])
    puts green("#{operation} successful!")
    return true
  end

  puts "Result: #{status.inspect}"
  true
end

def test_passed(name)
  puts
  if $test_failed
    puts red("#{name} FAILED!")
    exit 1
  else
    puts green("#{name} passed!")
  end
end

def build_sdk
  private_key = ENV['HYPERLIQUID_PRIVATE_KEY']
  unless private_key
    puts red('Error: Set HYPERLIQUID_PRIVATE_KEY environment variable')
    puts 'Usage: HYPERLIQUID_PRIVATE_KEY=0x... ruby <script>'
    exit 1
  end

  sdk = Hyperliquid.new(
    testnet: true,
    private_key: private_key
  )

  puts "Wallet: #{sdk.exchange.address}"
  puts 'Network: Testnet'
  puts "Testnet UI: https://app.hyperliquid-testnet.xyz"
  puts

  sdk
end
