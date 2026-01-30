# frozen_string_literal: true

require_relative 'hyperliquid/version'
require_relative 'hyperliquid/constants'
require_relative 'hyperliquid/errors'
require_relative 'hyperliquid/client'
require_relative 'hyperliquid/info'
require_relative 'hyperliquid/cloid'
require_relative 'hyperliquid/signing/eip712'
require_relative 'hyperliquid/signing/signer'
require_relative 'hyperliquid/exchange'

# Ruby SDK for Hyperliquid API
# Provides access to Hyperliquid's decentralized exchange API
# including both read (Info) and write (Exchange) operations
module Hyperliquid
  # Create a new SDK instance
  # @param testnet [Boolean] Whether to use testnet (default: false for mainnet)
  # @param timeout [Integer] Request timeout in seconds (default: 30)
  # @param retry_enabled [Boolean] Whether to enable retry logic (default: false)
  # @param private_key [String, nil] Ethereum private key for exchange operations (optional)
  # @param expires_after [Integer, nil] Global order expiration timestamp in ms (optional)
  # @return [Hyperliquid::SDK] A new SDK instance
  def self.new(testnet: false, timeout: Constants::DEFAULT_TIMEOUT, retry_enabled: false,
               private_key: nil, expires_after: nil)
    SDK.new(
      testnet: testnet,
      timeout: timeout,
      retry_enabled: retry_enabled,
      private_key: private_key,
      expires_after: expires_after
    )
  end

  # Main SDK class
  class SDK
    attr_reader :info, :exchange

    # Initialize the SDK
    # @param testnet [Boolean] Whether to use testnet (default: false for mainnet)
    # @param timeout [Integer] Request timeout in seconds
    # @param retry_enabled [Boolean] Whether to enable retry logic (default: false)
    # @param private_key [String, nil] Ethereum private key for exchange operations (optional)
    # @param expires_after [Integer, nil] Global order expiration timestamp in ms (optional)
    def initialize(testnet: false, timeout: Constants::DEFAULT_TIMEOUT, retry_enabled: false,
                   private_key: nil, expires_after: nil)
      base_url = testnet ? Constants::TESTNET_API_URL : Constants::MAINNET_API_URL
      client = Client.new(base_url: base_url, timeout: timeout, retry_enabled: retry_enabled)

      @info = Info.new(client)
      @testnet = testnet
      @exchange = nil

      return unless private_key

      signer = Signing::Signer.new(private_key: private_key, testnet: testnet)
      @exchange = Exchange.new(
        client: client,
        signer: signer,
        info: @info,
        testnet: testnet,
        expires_after: expires_after
      )
    end

    # Check if using testnet
    # @return [Boolean] True if using testnet, false if mainnet
    def testnet?
      @testnet
    end

    # Get the base API URL being used
    # @return [String] The base API URL
    def base_url
      @testnet ? Constants::TESTNET_API_URL : Constants::MAINNET_API_URL
    end
  end
end
