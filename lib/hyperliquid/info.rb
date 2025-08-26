# frozen_string_literal: true

module Hyperliquid
  # Client for read-only Info API endpoints
  class Info
    def initialize(client)
      @client = client
    end

    # Get all market mid prices
    # @return [Hash] Hash containing mid prices for all markets
    def all_mids
      @client.post(Constants::INFO_ENDPOINT, { type: 'allMids' })
    end

    # Get a user's open orders
    # @param user [String] Wallet address
    # @return [Array] Array of open orders for the user
    def open_orders(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'openOrders', user: user })
    end

    # Get a user's fill history
    # @param user [String] Wallet address
    # @return [Array] Array of fill history for the user
    def user_fills(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'userFills', user: user })
    end

    # Get order status by order ID
    # @param user [String] Wallet address
    # @param oid [Integer] Order ID
    # @return [Hash] Order status information
    def order_status(user, oid)
      @client.post(Constants::INFO_ENDPOINT, { type: 'orderStatus', user: user, oid: oid })
    end

    # Get user's trading state
    # @param user [String] Wallet address
    # @return [Hash] User's trading state including positions and balances
    def user_state(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'clearinghouseState', user: user })
    end

    # Get metadata for all assets
    # @return [Hash] Metadata for all tradable assets
    def meta
      @client.post(Constants::INFO_ENDPOINT, { type: 'meta' })
    end

    # Get metadata for all assets including universe info
    # @return [Hash] Extended metadata for all assets with universe information
    def meta_and_asset_ctxs
      @client.post(Constants::INFO_ENDPOINT, { type: 'metaAndAssetCtxs' })
    end

    # Get L2 order book for a coin
    # @param coin [String] Coin symbol (e.g., "BTC", "ETH")
    # @return [Hash] L2 order book data with bids and asks
    def l2_book(coin)
      @client.post(Constants::INFO_ENDPOINT, { type: 'l2Book', coin: coin })
    end

    # Get candlestick data
    # @param coin [String] Coin symbol
    # @param interval [String] Time interval (e.g., "1m", "1h", "1d")
    # @param start_time [Integer] Start timestamp in milliseconds
    # @param end_time [Integer] End timestamp in milliseconds
    # @return [Array] Array of candlestick data
    def candles_snapshot(coin, interval, start_time, end_time)
      @client.post(Constants::INFO_ENDPOINT, {
                     type: 'candleSnapshot',
                     req: {
                       coin: coin,
                       interval: interval,
                       startTime: start_time,
                       endTime: end_time
                     }
                   })
    end
  end
end
