# frozen_string_literal: true

require 'json'

# Verifies, after every example, that each POST the example made to an `/exchange` URL carries a
# signature that recovers to a Signer built during that example, for the network the request
# claims. The recomputation works from the POSTED body only (raw JSON, key order preserved), so a
# method that signs one thing and posts another — wrong expiresAfter, vaultAddress, nonce, field
# value or chain — fails here even when its own example only checks the wire shape.
#
# Opt out (only for examples that deliberately post bad signatures):
#   it '...', skip_signature_verification: 'posts a forged signature on purpose' do
#
# Load-order independent: nothing touches Hyperliquid constants until the suite starts.
class ExchangeSignatureVerifier
  # Posted user-signed action type => name of its Hyperliquid::Signing::EIP712 type table,
  # exactly as Exchange signs it. `multiSig` (the outer envelope) is verified separately.
  USER_SIGNED_TABLES = {
    'usdSend' => :USD_SEND_TYPES,
    'spotSend' => :SPOT_SEND_TYPES,
    'usdClassTransfer' => :USD_CLASS_TRANSFER_TYPES,
    'withdraw3' => :WITHDRAW_TYPES,
    'sendAsset' => :SEND_ASSET_TYPES,
    'approveAgent' => :APPROVE_AGENT_TYPES,
    'approveBuilderFee' => :APPROVE_BUILDER_FEE_TYPES,
    'tokenDelegate' => :TOKEN_DELEGATE_TYPES,
    'userDexAbstraction' => :USER_DEX_ABSTRACTION_TYPES,
    'convertToMultiSigUser' => :CONVERT_TO_MULTI_SIG_USER_TYPES,
    'userSetAbstraction' => :USER_SET_ABSTRACTION_TYPES,
    'linkStakingUser' => :LINK_STAKING_USER_TYPES,
    'stakingLinkDisableTradingUser' => :STAKING_LINK_DISABLE_TRADING_USER_TYPES,
    'userPortfolioMargin' => :USER_PORTFOLIO_MARGIN_TYPES,
    'cDeposit' => :C_DEPOSIT_TYPES,
    'cWithdraw' => :C_WITHDRAW_TYPES,
    'sendToEvmWithData' => :SEND_TO_EVM_WITH_DATA_TYPES
  }.freeze

  # Signed fields the posted action may omit, with the value that was signed in their place
  # (approveAgent signs agentName '' but posts it only when a name is given; matches Python).
  OMITTABLE_FIELDS = { 'approveAgent' => { 'agentName' => '' } }.freeze

  NETWORKS = { 'Mainnet' => false, 'Testnet' => true }.freeze

  # Records every Signer built during the current example.
  module SignerRegistration
    def initialize(...)
      super
      ExchangeSignatureVerifier.register(address, testnet?)
    end
  end

  class << self
    def install!
      return if @installed

      Hyperliquid::Signing::Signer.prepend(SignerRegistration)
      @installed = true
    end

    def signers
      @signers ||= []
    end

    def reset!
      signers.clear
    end

    def register(address, testnet)
      entry = [address.downcase, testnet ? true : false]
      signers << entry unless signers.include?(entry)
    end

    # @return [Array<String>] one message per /exchange request whose signature does not verify
    def failures
      failures = []
      # requested_signatures is a WebMock::Util::HashCounter (no #each_key); #hash is its request => count Hash.
      WebMock::RequestRegistry.instance.requested_signatures.hash.each_key do |request|
        next unless request.method == :post && request.uri.path.end_with?('/exchange')

        problem = verify_request(request.body)
        failures << "POST #{request.uri}: #{problem}" if problem
      end
      failures
    end

    private

    def verify_request(raw_body)
      body = JSON.parse(raw_body.to_s)
      return 'body has no action/nonce/signature to verify' unless checkable?(body)
      return verify_l1(body) unless body['action'].key?('signatureChainId')

      body['action']['type'] == 'multiSig' ? verify_multi_sig(body) : verify_user_signed(body)
    rescue JSON::ParserError => e
      "body is not JSON (#{e.message})"
    end

    def checkable?(body)
      body.is_a?(Hash) && body['action'].is_a?(Hash) && body['nonce'] && body['signature'].is_a?(Hash)
    end

    def verify_l1(body)
      action_hash = action_hash_for(body['action'], body)
      candidates = [false, true].map do |testnet|
        message = { source: eip712.source(testnet: testnet), connectionId: action_hash }
        typed = typed_data({ Agent: eip712.agent_type }, 'Agent', eip712.l1_action_domain, message)
        [testnet, recover(typed, body['signature'])]
      end
      return nil if candidates.any? { |testnet, address| registered?(address, testnet) }

      mismatch("L1 action '#{body['action']['type']}'", candidates)
    end

    def verify_user_signed(body)
      action = body['action']
      label = "user-signed '#{action['type']}'"
      types, problem = user_signed_types(action)
      message, problem = user_signed_message(action, types.values.first) unless problem
      problem ||= nonce_mismatch(message, body['nonce'])
      return "#{label}: #{problem}" if problem

      testnet = NETWORKS[action['hyperliquidChain']]
      address = recover_user_signed(types, action, message, body['signature'])
      registered?(address, testnet) ? nil : mismatch("#{label} (#{types.keys.first})", [[testnet, address]])
    end

    def recover_user_signed(types, action, message, signature)
      recover(typed_data(types, types.keys.first.to_s, user_signed_domain(action), message), signature)
    end

    def user_signed_types(action)
      table = USER_SIGNED_TABLES[action['type']]
      return [nil, "unknown user-signed action type: add it to #{name}::USER_SIGNED_TABLES"] unless table

      chain = action['hyperliquidChain']
      return [nil, "hyperliquidChain #{chain.inspect} is neither Mainnet nor Testnet"] unless NETWORKS.key?(chain)

      [eip712.const_get(table), nil]
    end

    def user_signed_message(action, fields)
      omittable = OMITTABLE_FIELDS.fetch(action['type'], {})
      message = {}
      fields.each do |field|
        name = field[:name].to_s
        return [nil, "posted action lacks signed field '#{name}'"] unless action.key?(name) || omittable.key?(name)

        message[field[:name]] = action.fetch(name) { omittable[name] }
      end
      [message, nil]
    end

    def nonce_mismatch(message, nonce)
      signed = message[:nonce] || message[:time]
      "signed nonce/time #{signed.inspect} != posted nonce #{nonce.inspect}" unless signed == nonce
    end

    def verify_multi_sig(body)
      action = body['action']
      action_hash = action_hash_for(action.except('type'), body)
      types = eip712::MULTI_SIG_TYPES
      candidates = [false, true].map do |testnet|
        message = { hyperliquidChain: eip712.hyperliquid_chain(testnet: testnet),
                    multiSigActionHash: action_hash, nonce: body['nonce'] }
        [testnet, recover_user_signed(types, action, message, body['signature'])]
      end
      match = candidates.find { |testnet, address| registered?(address, testnet) }
      return mismatch("multiSig envelope (#{types.keys.first})", candidates) unless match

      outer_signer_mismatch(action, match[1])
    end

    def outer_signer_mismatch(action, envelope_signer)
      outer_signer = action.dig('payload', 'outerSigner').to_s.downcase
      return nil if outer_signer == envelope_signer

      "multiSig envelope: payload.outerSigner #{outer_signer} != envelope signer #{envelope_signer}"
    end

    def action_hash_for(action, body)
      Hyperliquid::Signing::Signer.compute_action_hash(
        action, body['nonce'], vault_address: body['vaultAddress'], expires_after: body['expiresAfter']
      )
    end

    def typed_data(types, primary_type, domain, message)
      { types: { EIP712Domain: eip712.domain_type }.merge(types), primaryType: primary_type,
        domain: domain, message: message }
    end

    def user_signed_domain(action)
      eip712.user_signed_domain.merge(chainId: Integer(action['signatureChainId']))
    end

    def recover(typed, signature)
      r = signature['r'].to_s.delete_prefix('0x').rjust(64, '0')
      s = signature['s'].to_s.delete_prefix('0x').rjust(64, '0')
      v = Integer(signature['v']).to_s(16).rjust(2, '0')
      public_key = Eth::Signature.recover_typed_data(typed, "#{r}#{s}#{v}")
      Eth::Util.public_key_to_address(public_key).to_s.downcase
    rescue StandardError => e
      "<unrecoverable: #{e.class}: #{e.message}>"
    end

    def registered?(address, testnet)
      signers.include?([address, testnet])
    end

    def mismatch(what, candidates)
      recovered = candidates.map { |testnet, address| describe_signer(address, testnet) }.join(', ')
      expected = signers.map { |address, testnet| describe_signer(address, testnet) }.join(', ')
      expected = 'none (no Signer was built in this example)' if expected.empty?
      "#{what} signature does not verify: recovered #{recovered}; expected one of #{expected}"
    end

    def describe_signer(address, testnet)
      "#{address} (#{testnet ? 'testnet' : 'mainnet'})"
    end

    def eip712
      Hyperliquid::Signing::EIP712
    end
  end
end

RSpec.configure do |config|
  config.before(:suite) { ExchangeSignatureVerifier.install! }
  config.before { ExchangeSignatureVerifier.reset! }

  config.after do |example|
    reason = example.metadata[:skip_signature_verification]
    next if reason.is_a?(String) && !reason.strip.empty?
    raise ArgumentError, 'skip_signature_verification needs a non-empty String reason' unless reason.nil?

    failures = ExchangeSignatureVerifier.failures
    next if failures.empty?

    RSpec::Expectations.fail_with(
      "Exchange signature verification failed (spec/support/exchange_signature_verifier.rb):\n  " \
      "#{failures.join("\n  ")}"
    )
  end
end
