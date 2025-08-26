# frozen_string_literal: true

require_relative 'hyperliquid/version'
require_relative 'hyperliquid/constants'
require_relative 'hyperliquid/errors'
require_relative 'hyperliquid/client'
require_relative 'hyperliquid/info'

# Ruby SDK for Hyperliquid API
# Provides read-only access to Hyperliquid's decentralized exchange API
module Hyperliquid
  # Create a new SDK instance
  # @param testnet [Boolean] Whether to use testnet (default: false for mainnet)
  # @param timeout [Integer] Request timeout in seconds (default: 30)
  # @return [Hyperliquid::SDK] A new SDK instance
  def self.new(testnet: false, timeout: Constants::DEFAULT_TIMEOUT)
    SDK.new(testnet: testnet, timeout: timeout)
  end

  # Main SDK class
  class SDK
    attr_reader :info

    # Initialize the SDK
    # @param testnet [Boolean] Whether to use testnet (default: false for mainnet)
    # @param timeout [Integer] Request timeout in seconds
    def initialize(testnet: false, timeout: Constants::DEFAULT_TIMEOUT)
      base_url = testnet ? Constants::TESTNET_API_URL : Constants::MAINNET_API_URL
      client = Client.new(base_url: base_url, timeout: timeout)

      @info = Info.new(client)
      @testnet = testnet
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
