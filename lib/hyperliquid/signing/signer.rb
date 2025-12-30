# frozen_string_literal: true

require 'eth'
require 'msgpack'

module Hyperliquid
  module Signing
    # EIP-712 signature generation for Hyperliquid exchange operations
    class Signer
      # Initialize a new signer
      # @param private_key [String] Ethereum private key (hex string with or without 0x prefix)
      # @param mainnet [Boolean] Whether to sign for mainnet (default: true)
      def initialize(private_key:, mainnet: true)
        @mainnet = mainnet
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
      # @return [Hash] Signature with :r, :s, :v components
      def sign_l1_action(action, nonce, vault_address: nil)
        phantom_agent = construct_phantom_agent(action, nonce, vault_address)

        typed_data = {
          types: {
            EIP712Domain: EIP712.domain_type,
            Agent: EIP712.agent_type
          },
          primaryType: 'Agent',
          domain: EIP712.l1_action_domain(mainnet: @mainnet),
          message: phantom_agent
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
      # @param action [Hash] Action payload
      # @param nonce [Integer] Nonce timestamp
      # @param vault_address [String, nil] Optional vault address
      # @return [Hash] Phantom agent with source and connectionId
      def construct_phantom_agent(action, nonce, vault_address = nil)
        # Compute action hash per Python SDK spec:
        # data = msgpack(action) + nonce(8 bytes BE) + vault_flag + [vault_addr]
        data = action.to_msgpack
        data += [nonce].pack('Q>') # 8-byte big-endian uint64

        if vault_address.nil?
          data += "\x00"  # no vault flag
        else
          data += "\x01"  # has vault flag
          data += address_to_bytes(vault_address.downcase)
        end

        connection_id = Eth::Util.keccak256(data)

        {
          source: EIP712.source(mainnet: @mainnet),
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
      # @param typed_data [Hash] Complete EIP-712 structure with symbol keys
      # @return [Hash] Signature components :r, :s, :v
      def sign_typed_data(typed_data)
        # eth gem's sign_typed_data handles encoding internally
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
