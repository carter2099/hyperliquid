# frozen_string_literal: true

require_relative '../lib/hyperliquid'
require 'json'

WAIT_SECONDS = 3
SPOT_SLIPPAGE = 0.40  # 40% for illiquid testnet spot markets
PERP_SLIPPAGE = 0.15
ORACLE_RETRY_ATTEMPTS = 3
ORACLE_SLIPPAGE_INCREMENT = 0.10  # Increase slippage by 10% on each retry

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

# Extract and display the status from an API response
def dump_status(result)
  return unless result.is_a?(Hash)

  status = result.dig('response', 'data', 'statuses', 0)
  return unless status

  puts "  API status: #{status.inspect}"
end

def check_result(result, operation)
  dump_status(result)

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

# Check if result has "Price too far from oracle" error
def oracle_error?(result)
  return false unless result.is_a?(Hash)

  if result['status'] == 'err' && result['response'].to_s.include?('Price too far from oracle')
    return true
  end

  status = result.dig('response', 'data', 'statuses', 0)
  status.is_a?(Hash) && status['error'].to_s.include?('Price too far from oracle')
end

# Execute a market order with retry logic for oracle errors
def market_order_with_retry(sdk, coin:, is_buy:, size:, base_slippage:)
  slippage = base_slippage

  ORACLE_RETRY_ATTEMPTS.times do |attempt|
    result = sdk.exchange.market_order(
      coin: coin,
      is_buy: is_buy,
      size: size,
      slippage: slippage
    )

    unless oracle_error?(result)
      return result
    end

    if attempt < ORACLE_RETRY_ATTEMPTS - 1
      slippage += ORACLE_SLIPPAGE_INCREMENT
      puts red("Oracle price error. Retrying with #{(slippage * 100).to_i}% slippage (attempt #{attempt + 2}/#{ORACLE_RETRY_ATTEMPTS})...")
      sleep 1
    else
      return result
    end
  end
end

# Get position for a coin, returns nil if no position
def get_position(sdk, coin)
  state = sdk.info.user_state(sdk.exchange.address)
  positions = state['assetPositions'] || []
  positions.find { |p| p.dig('position', 'coin') == coin }
end

# Check for open position and prompt user to clean up
# Returns true if test should continue, false if should skip
def check_position_and_prompt(sdk, coin, timeout: 10)
  position = get_position(sdk, coin)
  return true unless position

  size = position.dig('position', 'szi').to_f
  return true if size.zero?

  puts red("WARNING: Open #{coin} position detected (size: #{size})")
  puts "This test requires no open #{coin} position."
  puts
  puts "Options:"
  puts "  [c] Close the position and continue"
  puts "  [s] Skip this test"
  puts
  print "Choice (auto-skip in #{timeout}s): "
  $stdout.flush

  # Non-blocking read with timeout
  require 'io/wait'
  choice = nil
  start = Time.now
  loop do
    if $stdin.ready?
      choice = $stdin.gets&.strip&.downcase
      break
    end
    elapsed = Time.now - start
    remaining = (timeout - elapsed).ceil
    if elapsed >= timeout
      puts
      puts "No response, skipping test..."
      return false
    end
    print "\rChoice (auto-skip in #{remaining}s): "
    $stdout.flush
    sleep 0.5
  end

  case choice
  when 'c'
    puts "Closing #{coin} position..."
    result = sdk.exchange.market_close(coin: coin, slippage: PERP_SLIPPAGE + 0.20)
    dump_status(result)
    if api_error?(result)
      puts red("Failed to close position. Skipping test.")
      return false
    end
    puts green("Position closed. Waiting for settlement...")

    # Wait and verify position is actually closed
    5.times do |i|
      sleep 2
      position = get_position(sdk, coin)
      remaining = position&.dig('position', 'szi').to_f.abs
      if remaining < 0.000001
        puts green("Position fully settled.")
        return true
      end
      puts "  Still settling... (#{remaining} remaining)"
    end

    puts red("Position did not fully close. Skipping test.")
    false
  else
    puts "Skipping test."
    false
  end
end
