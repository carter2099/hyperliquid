#!/usr/bin/env ruby
# frozen_string_literal: true

# Test 26: spotDeploy structured-rejection wire check (L1 action, testnet)
#
# Every probe targets token 0 (USDC), whose deployer is the protocol, so no wallet can be
# authorized and nothing can change on-chain. A correctly shaped, correctly signed action
# gets a structured `err` naming a deployer/token/precondition problem. Each probe is then
# repeated with a throwaway key (never funded, so it cannot exist on-chain): that control
# must get a signature-class rejection ("User or API Wallet ... does not exist") whose text
# differs from the wallet's, proving the rejection depended on the recovered signer (a
# hash/signing bug recovers a random address and gets the control's text -> FAIL).
#
# Usage:
#   HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_26_spot_deploy_rejection.rb

require_relative 'test_helpers'

NAME = 'Test 26 spot_deploy rejection'

WIRE_OR_SIGNATURE = /does not exist|deserializ|unknown variant|missing field|invalid type|signature|signer/i

PROBES = [
  # SP1
  [:spot_deploy_genesis, { token: 0, max_supply: '1' }],
  [:spot_deploy_user_genesis, { token: 0, user_and_wei: [], existing_token_and_wei: [],
                                blacklist_users: [['0x0000000000000000000000000000000000000001', false]] }],
  # SP2
  [:spot_deploy_set_deployer_trading_fee_share, { token: 0, share: '100%' }],
  [:spot_deploy_freeze_user, { token: 0, user: '0x0000000000000000000000000000000000000001', freeze: false }],
  # SP3
  [:spot_deploy_request_evm_contract, { token: 0, address: '0x0000000000000000000000000000000000000001',
                                        evm_extra_wei_decimals: 0 }],
  [:spot_deploy_set_token_annotation, { token: 0, category: 'test', description: 'sdk probe', keywords: [] }]
].freeze

# Returns [status, text]; status is 'ok', 'err', or 'raised' (HTTP error, e.g. 422 deserialize failure).
def send_probe(sdk, method, kwargs)
  result = sdk.exchange.public_send(method, **kwargs)
  return ['unexpected', result.inspect] unless result.is_a?(Hash)

  [result['status'].to_s, result['response'].to_s]
rescue Hyperliquid::Error => e
  ['raised', "#{e.class}: #{e.message} #{e.response_body.inspect}"]
end

sdk = build_sdk
control = throwaway_sdk
separator('TEST 26: spotDeploy rejection wire check')

PROBES.each do |method, kwargs|
  puts "#{method}(#{kwargs.inspect})"
  status, text = send_probe(sdk, method, kwargs)
  if status == 'ok'
    fail!("  FAIL: unexpected success: #{text} (wallet has deployer rights on token 0?)")
    next
  end
  if status != 'err' || text.match?(WIRE_OR_SIGNATURE)
    fail!("  FAIL (wire/signature class): #{status} #{text}")
    next
  end

  control_status, control_text = send_probe(control, method, kwargs)
  if control_status == 'ok'
    fail!("  FAIL: throwaway key succeeded: #{control_text}")
  else
    puts "  wallet rejection: #{text}"
    assert_signer_dependent(method.to_s, text, control_text)
  end
end

test_passed(NAME)
