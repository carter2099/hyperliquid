# frozen_string_literal: true

module Hyperliquid
  # Client for read-only Info API endpoints
  class Info
    def initialize(client)
      @client = client
    end

    # ============================
    # Info
    # ============================

    # Get all market mid prices
    # @param dex [String, nil] Optional perp dex name (defaults to first perp dex;
    #   spot mids only included with first perp dex)
    # @return [Hash] Hash containing mid prices for all markets
    def all_mids(dex: nil)
      body = { type: 'allMids' }
      body[:dex] = dex if dex
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Get a user's open orders
    # @param user [String] Wallet address
    # @param dex [String, nil] Optional perp dex name
    # @return [Array] Array of open orders for the user
    def open_orders(user, dex: nil)
      body = { type: 'openOrders', user: user }
      body[:dex] = dex if dex
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Get a user's open orders with additional frontend info
    # @param user [String] Wallet address
    # @param dex [String, nil] Optional perp dex name
    # @return [Array]
    def frontend_open_orders(user, dex: nil)
      body = { type: 'frontendOpenOrders', user: user }
      body[:dex] = dex if dex
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Get a user's fill history
    # @param user [String] Wallet address
    # @return [Array] Array of fill history for the user
    def user_fills(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'userFills', user: user })
    end

    # Get a user's fills within a time range
    # @param user [String] Wallet address
    # @param start_time [Integer] Start timestamp in milliseconds
    # @param end_time [Integer, nil] Optional end timestamp in milliseconds
    # @return [Array]
    def user_fills_by_time(user, start_time, end_time = nil)
      body = { type: 'userFillsByTime', user: user, startTime: start_time }
      body[:endTime] = end_time if end_time
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Query user rate limits and usage
    # @param user [String] Wallet address
    # @return [Hash]
    def user_rate_limit(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'userRateLimit', user: user })
    end

    # Get order status by order ID
    # @param user [String] Wallet address
    # @param oid [Integer] Order ID
    # @return [Hash] Order status information
    def order_status(user, oid)
      @client.post(Constants::INFO_ENDPOINT, { type: 'orderStatus', user: user, oid: oid })
    end

    # Get order status by client order ID (cloid)
    # @param user [String] Wallet address
    # @param cloid [String] Client order ID
    # @return [Hash] Order status information
    def order_status_by_cloid(user, cloid)
      @client.post(Constants::INFO_ENDPOINT, { type: 'orderStatus', user: user, cloid: cloid })
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

    # Check builder fee approval
    # @param user [String] Wallet address
    # @param builder [String] Builder address
    # @return [Hash]
    def max_builder_fee(user, builder)
      @client.post(Constants::INFO_ENDPOINT, { type: 'maxBuilderFee', user: user, builder: builder })
    end

    # Retrieve a user's historical orders
    # @param user [String] Wallet address
    # @param start_time [Integer, nil] Optional start timestamp in milliseconds
    # @param end_time [Integer, nil] Optional end timestamp in milliseconds
    # @return [Array]
    def historical_orders(user, start_time = nil, end_time = nil)
      body = { type: 'historicalOrders', user: user }
      body[:startTime] = start_time if start_time
      body[:endTime] = end_time if end_time
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Retrieve a user's TWAP slice fills
    # @param user [String] Wallet address
    # @param start_time [Integer, nil] Optional start timestamp in milliseconds
    # @param end_time [Integer, nil] Optional end timestamp in milliseconds
    # @return [Array]
    def user_twap_slice_fills(user, start_time = nil, end_time = nil)
      body = { type: 'userTwapSliceFills', user: user }
      body[:startTime] = start_time if start_time
      body[:endTime] = end_time if end_time
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Retrieve a user's subaccounts
    # @param user [String]
    # @return [Array]
    def user_subaccounts(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'subaccounts', user: user })
    end

    # Retrieve details for a vault
    # @param vault_address [String] Vault address
    # @param user [String, nil] Optional wallet address
    # @return [Hash]
    def vault_details(vault_address, user = nil)
      body = { type: 'vaultDetails', vaultAddress: vault_address }
      body[:user] = user if user
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Retrieve a user's vault deposits
    # @param user [String] Wallet address
    # @return [Array]
    def user_vault_equities(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'userVaultEquities', user: user })
    end

    # Query a user's role
    # @param user [String]
    # @return [Hash]
    def user_role(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'userRole', user: user })
    end

    # Query a user's portfolio time series
    # @param user [String]
    # @return [Array]
    def portfolio(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'portfolio', user: user })
    end

    # Query a user's referral information
    # @param user [String]
    # @return [Hash]
    def referral(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'referral', user: user })
    end

    # Query a user's effective fee rates and schedule
    # @param user [String]
    # @return [Hash]
    def user_fees(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'userFees', user: user })
    end

    # Query a user's staking delegations
    # @param user [String]
    # @return [Array]
    def delegations(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'delegations', user: user })
    end

    # Query a user's staking summary
    # @param user [String]
    # @return [Hash]
    def delegator_summary(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'delegatorSummary', user: user })
    end

    # Query a user's staking history
    # @param user [String]
    # @return [Array]
    def delegator_history(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'delegatorHistory', user: user })
    end

    # Query a user's staking rewards
    # @param user [String]
    # @return [Array]
    def delegator_rewards(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'delegatorRewards', user: user })
    end

    # Get authorized agent addresses for a user
    # @param user [String] Wallet address
    # @return [Array] Array of authorized agent addresses
    def extra_agents(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'extraAgents', user: user })
    end

    # Get multi-sig signer mappings for a user
    # @param user [String] Multi-sig wallet address
    # @return [Hash] Multi-sig signer information
    def user_to_multi_sig_signers(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'userToMultiSigSigners', user: user })
    end

    # Get dex abstraction config for a user
    # @param user [String] Wallet address
    # @return [Hash] Dex abstraction configuration
    def user_dex_abstraction(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'userDexAbstraction', user: user })
    end

    # ============================
    # Info: Perpetuals
    # ============================

    # Retrieve all perpetual dexs
    # @return [Array]
    def perp_dexs
      @client.post(Constants::INFO_ENDPOINT, { type: 'perpDexs' })
    end

    # Get metadata for all assets
    # @return [Hash] Metadata for all tradable assets
    # @param dex [String, nil] Optional perp dex name (defaults to first perp dex when not provided)
    def meta(dex: nil)
      body = { type: 'meta' }
      body[:dex] = dex if dex
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Get metadata for all assets including universe info
    # @return [Hash] Extended metadata for all assets with universe information
    def meta_and_asset_ctxs
      @client.post(Constants::INFO_ENDPOINT, { type: 'metaAndAssetCtxs' })
    end

    # Get user's trading state
    # @param user [String] Wallet address
    # @param dex [String, nil] Optional perp dex name
    # @return [Hash] User's trading state including positions and balances
    def user_state(user, dex: nil)
      body = { type: 'clearinghouseState', user: user }
      body[:dex] = dex if dex
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Retrieve predicted funding rates for different venues
    # @return [Array]
    def predicted_fundings
      @client.post(Constants::INFO_ENDPOINT, { type: 'predictedFundings' })
    end

    # Query perps at open interest caps
    # @return [Array]
    def perps_at_open_interest_cap
      @client.post(Constants::INFO_ENDPOINT, { type: 'perpsAtOpenInterestCap' })
    end

    # Retrieve information about the Perp Deploy Auction
    # @return [Hash]
    def perp_deploy_auction_status
      @client.post(Constants::INFO_ENDPOINT, { type: 'perpDeployAuctionStatus' })
    end

    # Retrieve User's Active Asset Data
    # @param user [String]
    # @param coin [String]
    # @return [Hash]
    def active_asset_data(user, coin)
      @client.post(Constants::INFO_ENDPOINT, { type: 'activeAssetData', user: user, coin: coin })
    end

    # Retrieve Builder-Deployed Perp Market Limits
    # @param dex [String]
    # @return [Hash]
    def perp_dex_limits(dex)
      @client.post(Constants::INFO_ENDPOINT, { type: 'perpDexLimits', dex: dex })
    end

    # Retrieve a user's funding history
    # @param user [String]
    # @param start_time [Integer]
    # @param end_time [Integer, nil]
    # @return [Array]
    def user_funding(user, start_time, end_time = nil)
      body = { type: 'userFunding', user: user, startTime: start_time }
      body[:endTime] = end_time if end_time
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Retrieve a user's non-funding ledger updates
    # @param user [String]
    # @param start_time [Integer]
    # @param end_time [Integer, nil]
    # @return [Array]
    def user_non_funding_ledger_updates(user, start_time, end_time = nil)
      body = { type: 'userNonFundingLedgerUpdates', user: user, startTime: start_time }
      body[:endTime] = end_time if end_time
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # Retrieve historical funding rates
    # @param coin [String]
    # @param start_time [Integer]
    # @param end_time [Integer, nil]
    # @return [Array]
    def funding_history(coin, start_time, end_time = nil)
      body = { type: 'fundingHistory', coin: coin, startTime: start_time }
      body[:endTime] = end_time if end_time
      @client.post(Constants::INFO_ENDPOINT, body)
    end

    # ============================
    # Info: Spot
    # ============================

    # Get spot metadata
    # @return [Hash] Spot tokens and universe metadata
    def spot_meta
      @client.post(Constants::INFO_ENDPOINT, { type: 'spotMeta' })
    end

    # Get spot metadata and asset contexts
    # @return [Array] [spot_meta, spot_asset_ctxs]
    def spot_meta_and_asset_ctxs
      @client.post(Constants::INFO_ENDPOINT, { type: 'spotMetaAndAssetCtxs' })
    end

    # Get a user's spot token balances
    # @param user [String] Wallet address
    # @return [Hash] Object containing balances array
    def spot_balances(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'spotClearinghouseState', user: user })
    end

    # Get Spot Deploy Auction state for a user
    # @param user [String] Wallet address
    # @return [Hash] Spot deploy state
    def spot_deploy_state(user)
      @client.post(Constants::INFO_ENDPOINT, { type: 'spotDeployState', user: user })
    end

    # Get Spot Pair Deploy Auction status
    # @return [Hash] Auction timing and gas parameters
    def spot_pair_deploy_auction_status
      @client.post(Constants::INFO_ENDPOINT, { type: 'spotPairDeployAuctionStatus' })
    end

    # Get token details by tokenId
    # @param token_id [String] 34-character hexadecimal token id
    # @return [Hash] Token details
    def token_details(token_id)
      @client.post(Constants::INFO_ENDPOINT, { type: 'tokenDetails', tokenId: token_id })
    end
  end
  # rubocop:enable Metrics/ClassLength
end
