# frozen_string_literal: true

module Hyperliquid
  module Signing
    # EIP-712 domain and type definitions for Hyperliquid
    class EIP712
      MAINNET_CHAIN_ID = 42_161   # Arbitrum One
      TESTNET_CHAIN_ID = 421_614  # Arbitrum Sepolia

      # Source identifier for phantom agent
      MAINNET_SOURCE = 'a'
      TESTNET_SOURCE = 'b'

      class << self
        # Domain for L1 actions (orders, cancels, leverage, etc.)
        # @param mainnet [Boolean] Whether to use mainnet chain ID
        # @return [Hash] EIP-712 domain configuration
        def l1_action_domain(mainnet:)
          {
            name: 'HyperliquidSignTransaction',
            version: '1',
            chainId: mainnet ? MAINNET_CHAIN_ID : TESTNET_CHAIN_ID,
            verifyingContract: '0x0000000000000000000000000000000000000000'
          }
        end

        # EIP-712 domain type definition (symbol names, string types for eth gem)
        # @return [Array<Hash>] Domain type fields
        def domain_type
          [
            { name: :name, type: 'string' },
            { name: :version, type: 'string' },
            { name: :chainId, type: 'uint256' },
            { name: :verifyingContract, type: 'address' }
          ]
        end

        # Agent type for phantom agent signing (symbol names, string types for eth gem)
        # @return [Array<Hash>] Agent type fields
        def agent_type
          [
            { name: :source, type: 'string' },
            { name: :connectionId, type: 'bytes32' }
          ]
        end

        # Get source identifier for phantom agent
        # @param mainnet [Boolean] Whether mainnet
        # @return [String] Source identifier ('a' for mainnet, 'b' for testnet)
        def source(mainnet:)
          mainnet ? MAINNET_SOURCE : TESTNET_SOURCE
        end
      end
    end
  end
end
