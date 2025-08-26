# frozen_string_literal: true

module Hyperliquid
  # Constants for Hyperliquid API
  module Constants
    # API URLs
    MAINNET_API_URL = 'https://api.hyperliquid.xyz'
    TESTNET_API_URL = 'https://api.hyperliquid-testnet.xyz'

    # API endpoints
    INFO_ENDPOINT = '/info'

    # Request timeouts (seconds)
    DEFAULT_TIMEOUT = 30
    DEFAULT_READ_TIMEOUT = 30
  end
end
