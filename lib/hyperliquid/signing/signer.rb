# frozen_string_literal: true

require 'eth'
require 'msgpack'

module Hyperliquid
  module Signing
    # EIP-712 signature generation for Hyperliquid exchange operations
    # Implements the phantom agent signing scheme used by Hyperliquid
    class Signer
      # Initialize a new signer
      # @param private_key [String] Ethereum private key (hex string with or without 0x prefix)
      # @param testnet [Boolean] Whether to sign for testnet (default: false)
      def initialize(private_key:, testnet: false)
        @testnet = testnet
        @key = Eth::Key.new(priv: normalize_private_key(private_key))
      end

      # Get the wallet address
      # @return [String] Checksummed Ethereum address
      def address
        @key.address.to_s
      end

      # Sign an L1 action (orders, cancels, leverage updates, etc.)
      # @param action [Hash] The action payload to sign
      # @param nonce [Integer] Timestamp in milliseconds
      # @param vault_address [String, nil] Optional vault address for vault trading
      # @param expires_after [Integer, nil] Optional expiration timestamp in milliseconds
      # @return [Hash] Signature with :r, :s, :v components
      def sign_l1_action(action, nonce, vault_address: nil, expires_after: nil)
        phantom_agent = construct_phantom_agent(action, nonce, vault_address, expires_after)

        typed_data = {
          types: {
            EIP712Domain: EIP712.domain_type,
            Agent: EIP712.agent_type
          },
          primaryType: 'Agent',
          domain: EIP712.l1_action_domain,
          message: phantom_agent
        }

        sign_typed_data(typed_data)
      end

      # Sign a user-signed action (transfers, withdrawals, etc.)
      # Uses direct EIP-712 typed data signing with HyperliquidSignTransaction domain
      # @param action [Hash] The action message to sign (will have chain fields injected)
      # @param primary_type [String] EIP-712 primary type (e.g., "HyperliquidTransaction:UsdSend")
      # @param sign_types [Hash] EIP-712 type definitions for the action
      # @return [Hash] Signature with :r, :s, :v components
      def sign_user_signed_action(action, primary_type, sign_types)
        # Inject chain fields into a copy of the action
        message = action.merge(
          hyperliquidChain: EIP712.hyperliquid_chain(testnet: @testnet),
          signatureChainId: '0x66eee'
        )

        typed_data = {
          types: {
            EIP712Domain: EIP712.domain_type
          }.merge(sign_types),
          primaryType: primary_type,
          domain: EIP712.user_signed_domain,
          message: message
        }

        sign_typed_data(typed_data)
      end

      private

      # Normalize private key format
      # @param key [String] Private key with or without 0x prefix
      # @return [String] Private key with 0x prefix
      def normalize_private_key(key)
        key.start_with?('0x') ? key : "0x#{key}"
      end

      # Construct the phantom agent for signing
      # Maintains parity with official Python SDK
      # @param action [Hash] Action payload
      # @param nonce [Integer] Nonce timestamp
      # @param vault_address [String, nil] Optional vault address
      # @param expires_after [Integer, nil] Optional expiration timestamp
      # @return [Hash] Phantom agent with source and connectionId
      def construct_phantom_agent(action, nonce, vault_address, expires_after)
        # Compute action hash
        # Maintains parity with official Python SDK
        # data = msgpack(action) + nonce(8 bytes BE) + vault_flag + [vault_addr] + [expires_flag + expires_after]
        # - Note: expires_flag is only included if expires_after exists. A bit odd but that's what the
        #     Python SDK does.
        data = action.to_msgpack
        data += [nonce].pack('Q>') # 8-byte big-endian uint64

        if vault_address.nil?
          data += "\x00" # no vault flag
        else
          data += "\x01" # has vault flag
          data += address_to_bytes(vault_address.downcase)
        end

        unless expires_after.nil?
          data += "\x00" # expiration flag
          data += [expires_after].pack('Q>') # 8-byte big-endian uint64
        end

        connection_id = Eth::Util.keccak256(data)

        {
          source: EIP712.source(testnet: @testnet),
          connectionId: bin_to_hex(connection_id)
        }
      end

      # Convert hex address to 20-byte binary
      # @param address [String] Ethereum address with 0x prefix
      # @return [String] 20-byte binary representation
      def address_to_bytes(address)
        [address.sub(/\A0x/i, '')].pack('H*')
      end

      # Sign EIP-712 typed data using eth gem's built-in method
      # @param typed_data [Hash] Complete EIP-712 structure
      # @return [Hash] Signature components :r, :s, :v
      def sign_typed_data(typed_data)
        signature = @key.sign_typed_data(typed_data)

        # Parse signature hex string into components
        # Format: r (64 hex chars) + s (64 hex chars) + v (2 hex chars)
        {
          r: "0x#{signature[0, 64]}",
          s: "0x#{signature[64, 64]}",
          v: signature[128, 2].to_i(16)
        }
      end

      # Convert binary data to hex string with 0x prefix
      # @param bin [String] Binary data
      # @return [String] Hex string with 0x prefix
      def bin_to_hex(bin)
        "0x#{bin.unpack1('H*')}"
      end
    end
  end
end
