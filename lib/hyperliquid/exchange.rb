# frozen_string_literal: true

module Hyperliquid
  # Client for write (Exchange) API endpoints
  # Note: Signing is not yet implemented in this Ruby SDK. Provide pre-signed inputs.
  class Exchange
    def initialize(client)
      @client = client
    end

    # Place an order via the Exchange API.
    # This method can accept a prebuilt signature or sign using a private key.
    #
    # @param action [Hash] Canonical action payload for placing an order (as required by Hyperliquid)
    # @param nonce [Integer] Millisecond nonce used for the signature
    # @param signature [String, nil] Hex-encoded ECDSA signature (0x-prefixed)
    # @param private_key [String, nil] 0x-prefixed private key. If provided and signature is nil, will sign.
    # @param vault_address [String, nil] Optional vault address if applicable
    # @return [Hash] Parsed JSON response from the API
    def place_order(action:, nonce:, signature: nil, private_key: nil, vault_address: nil, is_mainnet: false)
      if (signature.nil? || !signature.start_with?('0x')) && private_key
        signature = Signing.sign_l1_action(
          private_key: private_key,
          action: action,
          nonce: nonce,
          vault_address: vault_address,
          is_mainnet: is_mainnet
        )
      end

      unless signature && signature.start_with?('0x')
        raise ArgumentError, 'signature is required (or provide private_key to auto-sign)'
      end

      # API expects `action`, `nonce`, and `signature` top-level.
      # Try flattened schema with optional singular order support
      act = action.transform_keys { |k| k.is_a?(Symbol) ? k : k.to_sym }
      if act[:type] == 'order' && act[:orders].is_a?(Array) && act[:orders].length == 1
        body = {
          type: 'order',
          order: act[:orders].first,
          nonce: nonce.to_s,
          signature: signature
        }
      else
        body = {
          action: action,
          nonce: nonce.to_s,
          signature: signature
        }
      end
      body[:vaultAddress] = vault_address if vault_address

      @client.post(Constants::EXCHANGE_ENDPOINT, body)
    end
  end
end


