# frozen_string_literal: true

module Hyperliquid
  module Signing
    # EIP-712 domain and type definitions for Hyperliquid
    # These values are defined by the Hyperliquid protocol and must match exactly
    class EIP712
      # Hyperliquid L1 chain ID (same for mainnet and testnet)
      L1_CHAIN_ID = 1337

      # Source identifier for phantom agent
      MAINNET_SOURCE = 'a'
      TESTNET_SOURCE = 'b'

      # Chain ID for user-signed actions (Arbitrum Sepolia: 0x66eee = 421614)
      USER_SIGNED_CHAIN_ID = 421_614

      # EIP-712 type definitions for user-signed actions

      USD_SEND_TYPES = {
        'HyperliquidTransaction:UsdSend': [
          { name: :hyperliquidChain, type: 'string' },
          { name: :destination, type: 'string' },
          { name: :amount, type: 'string' },
          { name: :time, type: 'uint64' }
        ]
      }.freeze

      SPOT_SEND_TYPES = {
        'HyperliquidTransaction:SpotSend': [
          { name: :hyperliquidChain, type: 'string' },
          { name: :destination, type: 'string' },
          { name: :token, type: 'string' },
          { name: :amount, type: 'string' },
          { name: :time, type: 'uint64' }
        ]
      }.freeze

      USD_CLASS_TRANSFER_TYPES = {
        'HyperliquidTransaction:UsdClassTransfer': [
          { name: :hyperliquidChain, type: 'string' },
          { name: :amount, type: 'string' },
          { name: :toPerp, type: 'bool' },
          { name: :nonce, type: 'uint64' }
        ]
      }.freeze

      WITHDRAW_TYPES = {
        'HyperliquidTransaction:Withdraw': [
          { name: :hyperliquidChain, type: 'string' },
          { name: :destination, type: 'string' },
          { name: :amount, type: 'string' },
          { name: :time, type: 'uint64' }
        ]
      }.freeze

      SEND_ASSET_TYPES = {
        'HyperliquidTransaction:SendAsset': [
          { name: :hyperliquidChain, type: 'string' },
          { name: :destination, type: 'string' },
          { name: :sourceDex, type: 'string' },
          { name: :destinationDex, type: 'string' },
          { name: :token, type: 'string' },
          { name: :amount, type: 'string' },
          { name: :fromSubAccount, type: 'string' },
          { name: :nonce, type: 'uint64' }
        ]
      }.freeze

      APPROVE_AGENT_TYPES = {
        'HyperliquidTransaction:ApproveAgent': [
          { name: :hyperliquidChain, type: 'string' },
          { name: :agentAddress, type: 'address' },
          { name: :agentName, type: 'string' },
          { name: :nonce, type: 'uint64' }
        ]
      }.freeze

      APPROVE_BUILDER_FEE_TYPES = {
        'HyperliquidTransaction:ApproveBuilderFee': [
          { name: :hyperliquidChain, type: 'string' },
          { name: :maxFeeRate, type: 'string' },
          { name: :builder, type: 'address' },
          { name: :nonce, type: 'uint64' }
        ]
      }.freeze

      TOKEN_DELEGATE_TYPES = {
        'HyperliquidTransaction:TokenDelegate': [
          { name: :hyperliquidChain, type: 'string' },
          { name: :validator, type: 'address' },
          { name: :wei, type: 'uint64' },
          { name: :isUndelegate, type: 'bool' },
          { name: :nonce, type: 'uint64' }
        ]
      }.freeze

      USER_DEX_ABSTRACTION_TYPES = {
        'HyperliquidTransaction:UserDexAbstraction': [
          { name: :hyperliquidChain, type: 'string' },
          { name: :user, type: 'address' },
          { name: :enabled, type: 'bool' },
          { name: :nonce, type: 'uint64' }
        ]
      }.freeze

      class << self
        # Domain for L1 actions (orders, cancels, leverage, etc.)
        # @return [Hash] EIP-712 domain configuration
        def l1_action_domain
          {
            name: 'Exchange',
            version: '1',
            chainId: L1_CHAIN_ID,
            verifyingContract: '0x0000000000000000000000000000000000000000'
          }
        end

        # Domain for user-signed actions (transfers, withdrawals, etc.)
        # @return [Hash] EIP-712 domain configuration
        def user_signed_domain
          {
            name: 'HyperliquidSignTransaction',
            version: '1',
            chainId: USER_SIGNED_CHAIN_ID,
            verifyingContract: '0x0000000000000000000000000000000000000000'
          }
        end

        # EIP-712 domain type definition
        # @return [Array<Hash>] Domain type fields
        def domain_type
          [
            { name: :name, type: 'string' },
            { name: :version, type: 'string' },
            { name: :chainId, type: 'uint256' },
            { name: :verifyingContract, type: 'address' }
          ]
        end

        # Agent type for phantom agent signing
        # @return [Array<Hash>] Agent type fields
        def agent_type
          [
            { name: :source, type: 'string' },
            { name: :connectionId, type: 'bytes32' }
          ]
        end

        # Get source identifier for phantom agent
        # @param testnet [Boolean] Whether testnet
        # @return [String] Source identifier ('a' for mainnet, 'b' for testnet)
        def source(testnet:)
          testnet ? TESTNET_SOURCE : MAINNET_SOURCE
        end

        # Get hyperliquid chain name for user-signed actions
        # @param testnet [Boolean] Whether testnet
        # @return [String] "Mainnet" or "Testnet"
        def hyperliquid_chain(testnet:)
          testnet ? 'Testnet' : 'Mainnet'
        end
      end
    end
  end
end
