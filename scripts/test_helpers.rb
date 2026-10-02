# frozen_string_literal: true

# Shared helpers for the testnet integration scripts.
#
# Result contract (the runner, scripts/test_all.rb, maps exit codes to statuses):
#   PASS 0, FAIL 1, INCONCLUSIVE 75, SKIPPED 77, GUARDED 78.
#   INCONCLUSIVE: the environment gave no evidence either way.
#   SKIPPED:      the script deliberately did not test anything.
#   GUARDED:      the happy path was impossible because of wallet/testnet state and a
#                 weaker but still signature-proving check ran instead.
# Every script ends with exactly one `RESULT <STATUS> <name>` line via test_passed /
# finish_inconclusive / finish_skipped / finish_guarded.

require_relative '../lib/hyperliquid'
require 'json'

$stdout.sync = true

WAIT_SECONDS = 3
SPOT_SLIPPAGE = 0.40  # 40% for illiquid testnet spot markets
PERP_SLIPPAGE = 0.15
ORACLE_RETRY_ATTEMPTS = 3
ORACLE_SLIPPAGE_INCREMENT = 0.10  # Increase slippage by 10% on each retry

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_INCONCLUSIVE = 75
EXIT_SKIPPED = 77
EXIT_GUARDED = 78

# Response text a key with no Hyperliquid account gets back for a signed action.
SIGNER_REJECTION = /does not exist|User or API Wallet|Must deposit before performing actions/i
FIX_HINT = 'run `ruby scripts/testnet_wallet_check.rb --fix`'

COLOR = $stdout.tty? && ENV['NO_COLOR'].nil?

def green(text)
  COLOR ? "\e[32m#{text}\e[0m" : text.to_s
end

def red(text)
  COLOR ? "\e[31m#{text}\e[0m" : text.to_s
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
  unless $stdout.tty?
    puts "#{message} (waiting #{seconds}s)"
    sleep seconds
    return
  end

  puts message
  seconds.downto(1) do |i|
    print "\r  #{i} seconds remaining...  "
    sleep 1
  end
  puts "\r  Done!                      "
  puts
end

# Records a failure without exiting; the script's final test_passed/finish_* reports it.
def fail!(message)
  puts red(message)
  $test_failed = true
  false
end

def api_error?(result)
  return false unless result.is_a?(Hash) && result['status'] == 'err'

  fail!("FAILED: #{result['response']}")
  true
end

# Extract and display the status from an API response
def dump_status(result)
  return unless result.is_a?(Hash)

  response = result['response']
  return unless response.is_a?(Hash)

  data = response['data']
  return unless data.is_a?(Hash)

  status = data.dig('statuses', 0)
  return unless status

  puts "  API status: #{status.inspect}"
end

# Returns the resting oid, true for a fill/success, or false (and records a failure)
# for an error or any status it does not recognise.
def check_result(result, operation)
  dump_status(result)

  return false if api_error?(result)

  response = result.is_a?(Hash) ? result['response'] : nil
  data = response.is_a?(Hash) ? response['data'] : nil
  status = data.is_a?(Hash) ? data.dig('statuses', 0) : nil

  return fail!("FAILED: #{status['error']}") if status.is_a?(Hash) && status['error']

  if status.is_a?(Hash) && status['resting']
    puts green("Order resting with OID: #{status['resting']['oid']}")
    return status['resting']['oid']
  end

  if status == 'success' || (status.is_a?(Hash) && status['filled'])
    puts green("#{operation} successful!")
    return true
  end

  fail!("FAILED: #{operation} returned an unrecognised status #{status.inspect} (response: #{result.inspect})")
end

def finish_with(status, code, name, reason = nil)
  puts
  if $test_failed
    puts "RESULT FAIL #{name}"
    exit EXIT_FAIL
  end
  puts(reason ? "RESULT #{status} #{name}: #{reason}" : "RESULT #{status} #{name}")
  exit code
end

def test_passed(name)
  finish_with('PASS', EXIT_PASS, name)
end

def finish_inconclusive(name, reason)
  finish_with('INCONCLUSIVE', EXIT_INCONCLUSIVE, name, reason)
end

def finish_skipped(name, reason)
  finish_with('SKIPPED', EXIT_SKIPPED, name, reason)
end

def finish_guarded(name, reason)
  finish_with('GUARDED', EXIT_GUARDED, name, reason)
end

def require_testnet!(sdk)
  return sdk if sdk.base_url.include?('testnet')

  abort red("REFUSING: SDK base URL #{sdk.base_url} is not testnet")
end

def build_sdk
  private_key = ENV['HYPERLIQUID_PRIVATE_KEY']
  if private_key.nil? || private_key.empty?
    puts red('Error: Set HYPERLIQUID_PRIVATE_KEY environment variable')
    puts 'Usage: HYPERLIQUID_PRIVATE_KEY=0x... ruby <script>'
    exit EXIT_FAIL
  end

  sdk = require_testnet!(Hyperliquid.new(testnet: true, private_key: private_key))

  puts "Wallet: #{sdk.exchange.address}"
  puts "Network: #{sdk.base_url}"
  puts 'Testnet UI: https://app.hyperliquid-testnet.xyz'
  puts

  sdk
end

# Key-less testnet SDK for WebSocket and read-only scripts.
def build_public_sdk
  sdk = require_testnet!(Hyperliquid.new(testnet: true))
  puts "Network: #{sdk.base_url}"
  puts
  sdk
end

# A freshly generated, never-funded key: the control signer for wire checks.
def throwaway_sdk
  require_testnet!(Hyperliquid.new(testnet: true, private_key: "0x#{Eth::Key.new.private_hex}"))
end

# Proves a pinned rejection depends on the signer: a throwaway key must get an
# account-not-found class error, and a different one from the agent wallet's.
def assert_signer_dependent(label, agent_text, control_text)
  puts "  #{label} agent wallet:  #{agent_text}"
  puts "  #{label} throwaway key: #{control_text}"
  unless control_text.to_s.match?(SIGNER_REJECTION)
    return fail!("#{label}: throwaway-key response is not a signer rejection: #{control_text.inspect}")
  end
  if control_text.to_s == agent_text.to_s
    return fail!("#{label}: agent and throwaway-key responses are identical, so the rejection is not signer-dependent")
  end

  puts green("#{label}: rejection is signer-dependent")
  true
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

# Records a failure if the wallet holds a position or an open order on `coin`.
# Never remediates: the wallet is flat by precondition. Returns true when flat.
def require_flat!(sdk, coin)
  flat = true
  size = get_position(sdk, coin)&.dig('position', 'szi').to_f
  unless size.zero?
    flat = fail!("Open #{coin} position (szi=#{size}); this test needs a flat wallet - #{FIX_HINT}")
  end

  orders = sdk.info.open_orders(sdk.exchange.address).select { |o| o['coin'] == coin }
  unless orders.empty?
    oids = orders.map { |o| o['oid'] }.join(', ')
    flat = fail!("#{orders.length} open #{coin} order(s) (oid #{oids}); this test needs a flat wallet - #{FIX_HINT}")
  end
  flat
end
