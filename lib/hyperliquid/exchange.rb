# frozen_string_literal: true

require 'bigdecimal'

module Hyperliquid
  # Exchange API client for write operations (orders, cancels, etc.)
  # Requires a private key for signing transactions
  class Exchange
    # Default slippage for market orders (5%)
    DEFAULT_SLIPPAGE = 0.05

    # Spot assets have indices >= 10000
    SPOT_ASSET_THRESHOLD = 10_000

    # Initialize the exchange client
    # @param client [Hyperliquid::Client] HTTP client
    # @param signer [Hyperliquid::Signing::Signer] EIP-712 signer
    # @param info [Hyperliquid::Info] Info API client for metadata
    # @param expires_after [Integer, nil] Optional global expiration timestamp
    def initialize(client:, signer:, info:, expires_after: nil)
      @client = client
      @signer = signer
      @info = info
      @expires_after = expires_after
      @asset_cache = nil
    end

    # Get the wallet address
    # @return [String] Checksummed Ethereum address
    def address
      @signer.address
    end

    # Place a single order
    # @param coin [String] Asset symbol (e.g., "BTC")
    # @param is_buy [Boolean] True for buy, false for sell
    # @param size [String, Numeric] Order size
    # @param limit_px [String, Numeric] Limit price
    # @param order_type [Hash] Order type config (default: { limit: { tif: "Gtc" } })
    # @param reduce_only [Boolean] Reduce-only flag (default: false)
    # @param cloid [Cloid, String, nil] Client order ID (optional)
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Order response
    def order(coin:, is_buy:, size:, limit_px:, order_type: { limit: { tif: 'Gtc' } },
              reduce_only: false, cloid: nil, vault_address: nil)
      nonce = timestamp_ms

      order_wire = build_order_wire(
        coin: coin,
        is_buy: is_buy,
        size: size,
        limit_px: limit_px,
        order_type: order_type,
        reduce_only: reduce_only,
        cloid: cloid
      )

      action = {
        type: 'order',
        orders: [order_wire],
        grouping: 'na'
      }

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Place multiple orders in a batch
    # @param orders [Array<Hash>] Array of order hashes with keys:
    #   :coin, :is_buy, :size, :limit_px, :order_type, :reduce_only, :cloid
    # @param grouping [String] Order grouping ("na", "normalTpsl", "positionTpsl")
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Bulk order response
    def bulk_orders(orders:, grouping: 'na', vault_address: nil)
      nonce = timestamp_ms

      order_wires = orders.map do |o|
        build_order_wire(
          coin: o[:coin],
          is_buy: o[:is_buy],
          size: o[:size],
          limit_px: o[:limit_px],
          order_type: o[:order_type] || { limit: { tif: 'Gtc' } },
          reduce_only: o[:reduce_only] || false,
          cloid: o[:cloid]
        )
      end

      action = {
        type: 'order',
        orders: order_wires,
        grouping: grouping
      }

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Place a market order (aggressive limit IoC with slippage)
    # @param coin [String] Asset symbol
    # @param is_buy [Boolean] True for buy, false for sell
    # @param size [String, Numeric] Order size
    # @param slippage [Float] Slippage tolerance (default: 0.05 = 5%)
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Order response
    def market_order(coin:, is_buy:, size:, slippage: DEFAULT_SLIPPAGE, vault_address: nil)
      # Get current mid price
      mids = @info.all_mids
      mid = mids[coin]&.to_f
      raise ArgumentError, "Unknown asset or no price available: #{coin}" unless mid&.positive?

      # Apply slippage and round to appropriate precision
      slippage_price = calculate_slippage_price(coin, mid, is_buy, slippage)

      order(
        coin: coin,
        is_buy: is_buy,
        size: size,
        limit_px: slippage_price,
        order_type: { limit: { tif: 'Ioc' } },
        vault_address: vault_address
      )
    end

    # Cancel a single order by order ID
    # @param coin [String] Asset symbol
    # @param oid [Integer] Order ID
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Cancel response
    def cancel(coin:, oid:, vault_address: nil)
      nonce = timestamp_ms

      action = {
        type: 'cancel',
        cancels: [{ a: asset_index(coin), o: oid }]
      }

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Cancel a single order by client order ID
    # @param coin [String] Asset symbol
    # @param cloid [Cloid, String] Client order ID
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Cancel response
    def cancel_by_cloid(coin:, cloid:, vault_address: nil)
      nonce = timestamp_ms
      cloid_raw = normalize_cloid(cloid)

      action = {
        type: 'cancelByCloid',
        cancels: [{ asset: asset_index(coin), cloid: cloid_raw }]
      }

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Cancel multiple orders by order ID
    # @param cancels [Array<Hash>] Array of cancel hashes with :coin and :oid
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Bulk cancel response
    def bulk_cancel(cancels:, vault_address: nil)
      nonce = timestamp_ms

      cancel_wires = cancels.map do |c|
        { a: asset_index(c[:coin]), o: c[:oid] }
      end
      action = { type: 'cancel', cancels: cancel_wires }

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Cancel multiple orders by client order ID
    # @param cancels [Array<Hash>] Array of cancel hashes with :coin and :cloid
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Bulk cancel by cloid response
    def bulk_cancel_by_cloid(cancels:, vault_address: nil)
      nonce = timestamp_ms

      cancel_wires = cancels.map do |c|
        { asset: asset_index(c[:coin]), cloid: normalize_cloid(c[:cloid]) }
      end
      action = { type: 'cancelByCloid', cancels: cancel_wires }

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Modify a single existing order
    # @param oid [Integer, Cloid, String] Order ID or client order ID to modify
    # @param coin [String] Asset symbol (e.g., "BTC")
    # @param is_buy [Boolean] True for buy, false for sell
    # @param size [String, Numeric] New order size
    # @param limit_px [String, Numeric] New limit price
    # @param order_type [Hash] Order type config (default: { limit: { tif: "Gtc" } })
    # @param reduce_only [Boolean] Reduce-only flag (default: false)
    # @param cloid [Cloid, String, nil] Client order ID for the modified order (optional)
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Modify response
    def modify_order(oid:, coin:, is_buy:, size:, limit_px:,
                     order_type: { limit: { tif: 'Gtc' } },
                     reduce_only: false, cloid: nil, vault_address: nil)
      batch_modify(
        modifies: [{
          oid: oid, coin: coin, is_buy: is_buy, size: size,
          limit_px: limit_px, order_type: order_type,
          reduce_only: reduce_only, cloid: cloid
        }],
        vault_address: vault_address
      )
    end

    # Modify multiple orders at once
    # @param modifies [Array<Hash>] Array of modify hashes with keys:
    #   :oid, :coin, :is_buy, :size, :limit_px, :order_type, :reduce_only, :cloid
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Batch modify response
    def batch_modify(modifies:, vault_address: nil)
      nonce = timestamp_ms

      modify_wires = modifies.map do |m|
        order_wire = build_order_wire(
          coin: m[:coin],
          is_buy: m[:is_buy],
          size: m[:size],
          limit_px: m[:limit_px],
          order_type: m[:order_type] || { limit: { tif: 'Gtc' } },
          reduce_only: m[:reduce_only] || false,
          cloid: m[:cloid]
        )
        { oid: normalize_oid(m[:oid]), order: order_wire }
      end

      action = {
        type: 'batchModify',
        modifies: modify_wires
      }

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Set cross or isolated leverage for a coin
    # @param coin [String] Asset symbol (perps only)
    # @param leverage [Integer] Leverage value
    # @param is_cross [Boolean] True for cross margin, false for isolated (default: true)
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Leverage update response
    def update_leverage(coin:, leverage:, is_cross: true, vault_address: nil)
      nonce = timestamp_ms

      action = {
        type: 'updateLeverage',
        asset: asset_index(coin),
        isCross: is_cross,
        leverage: leverage
      }

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Add or remove isolated margin for a position
    # @param coin [String] Asset symbol (perps only)
    # @param amount [Numeric] Amount in USD (positive to add, negative to remove)
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Margin update response
    def update_isolated_margin(coin:, amount:, vault_address: nil)
      nonce = timestamp_ms

      action = {
        type: 'updateIsolatedMargin',
        asset: asset_index(coin),
        isBuy: true,
        ntli: float_to_usd_int(amount)
      }

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Schedule automatic cancellation of all orders
    # @param time [Integer, nil] UTC timestamp in milliseconds to cancel at (nil to activate with server default)
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Schedule cancel response
    def schedule_cancel(time: nil, vault_address: nil)
      nonce = timestamp_ms

      action = { type: 'scheduleCancel' }
      action[:time] = time if time

      signature = @signer.sign_l1_action(
        action, nonce,
        vault_address: vault_address,
        expires_after: @expires_after
      )
      post_action(action, signature, nonce, vault_address)
    end

    # Close a position at market price
    # @param coin [String] Asset symbol (perps only)
    # @param size [Numeric, nil] Size to close (nil = close entire position)
    # @param slippage [Float] Slippage tolerance (default: 5%)
    # @param cloid [Cloid, String, nil] Client order ID (optional)
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Order response
    def market_close(coin:, size: nil, slippage: DEFAULT_SLIPPAGE, cloid: nil, vault_address: nil)
      address = vault_address || @signer.address
      state = @info.user_state(address)

      position = state['assetPositions']&.find do |pos|
        pos.dig('position', 'coin') == coin
      end
      raise ArgumentError, "No open position found for #{coin}" unless position

      szi = position.dig('position', 'szi').to_f
      is_buy = szi.negative?
      close_size = size || szi.abs

      mids = @info.all_mids
      mid = mids[coin]&.to_f
      raise ArgumentError, "Unknown asset or no price available: #{coin}" unless mid&.positive?

      slippage_price = calculate_slippage_price(coin, mid, is_buy, slippage)

      order(
        coin: coin,
        is_buy: is_buy,
        size: close_size,
        limit_px: slippage_price,
        order_type: { limit: { tif: 'Ioc' } },
        reduce_only: true,
        cloid: cloid,
        vault_address: vault_address
      )
    end

    # Clear the asset metadata cache
    # Call this if metadata has been updated
    def reload_metadata!
      @asset_cache = nil
    end

    private

    # Build order wire format
    def build_order_wire(coin:, is_buy:, size:, limit_px:, order_type:, reduce_only:, cloid:)
      wire = {
        a: asset_index(coin),
        b: is_buy,
        p: float_to_wire(limit_px),
        s: float_to_wire(size),
        r: reduce_only,
        t: order_type_to_wire(order_type)
      }
      wire[:c] = normalize_cloid(cloid) if cloid
      wire
    end

    # Get current timestamp in milliseconds
    def timestamp_ms
      (Time.now.to_f * 1000).to_i
    end

    # Get asset index for a coin symbol
    # @param coin [String] Asset symbol
    # @return [Integer] Asset index
    def asset_index(coin)
      load_asset_cache unless @asset_cache
      @asset_cache[:indices][coin] || raise(ArgumentError, "Unknown asset: #{coin}")
    end

    # Get asset metadata for a coin symbol
    # @param coin [String] Asset symbol
    # @return [Hash] Asset metadata with :sz_decimals and :is_spot
    def asset_metadata(coin)
      load_asset_cache unless @asset_cache
      @asset_cache[:metadata][coin] || raise(ArgumentError, "Unknown asset: #{coin}")
    end

    # Load asset metadata from Info API (perps and spot)
    def load_asset_cache
      @asset_cache = { indices: {}, metadata: {} }

      # Load perpetual assets
      meta = @info.meta
      meta['universe'].each_with_index do |asset, index|
        name = asset['name']
        @asset_cache[:indices][name] = index
        @asset_cache[:metadata][name] = {
          sz_decimals: asset['szDecimals'],
          is_spot: false
        }
      end

      # Load spot assets (index starts at SPOT_ASSET_THRESHOLD)
      spot_meta = @info.spot_meta
      spot_meta['universe'].each_with_index do |pair, index|
        name = pair['name']
        spot_index = index + SPOT_ASSET_THRESHOLD
        @asset_cache[:indices][name] = spot_index
        @asset_cache[:metadata][name] = {
          sz_decimals: pair['szDecimals'] || 0,
          is_spot: true
        }
      end
    end

    # Convert float to wire format (string representation)
    # Maintains parity with official Python SDK
    # - 8 decimal precision
    # - Rounding tolerance validation (1e-12)
    # - Decimal normalization (remove trailing zeros)
    # @param value [String, Numeric] Value to convert
    # @return [String] Wire format string
    def float_to_wire(value)
      decimal = BigDecimal(value.to_s)

      # Format to 8 decimal places
      rounded_str = format('%.8f', decimal)
      rounded = BigDecimal(rounded_str)

      # Validate rounding tolerance
      raise ArgumentError, "float_to_wire causes rounding: #{value}" if (rounded - decimal).abs >= BigDecimal('1e-12')

      # Negative zero edge case
      rounded_str = '0.00000000' if rounded_str == '-0.00000000'

      # Normalize: remove trailing zeros and unnecessary decimal point
      # BigDecimal#to_s('F') gives fixed-point notation
      normalized = BigDecimal(rounded_str).to_s('F')
      # Remove trailing zeros after decimal point, and trailing decimal point
      normalized.sub(/(\.\d*?)0+\z/, '\1').sub(/\.\z/, '')
    end

    # Calculate slippage price for market orders
    # Maintains parity with official Python SDK
    # 1. Apply slippage to mid price
    # 2. Round to 5 significant figures
    # 3. Round to asset-specific decimal places
    # @param coin [String] Asset symbol
    # @param mid [Float] Current mid price
    # @param is_buy [Boolean] True for buy
    # @param slippage [Float] Slippage tolerance
    # @return [String] Formatted price string
    def calculate_slippage_price(coin, mid, is_buy, slippage)
      # Apply slippage
      px = is_buy ? mid * (1 + slippage) : mid * (1 - slippage)

      # Get asset metadata
      metadata = asset_metadata(coin)
      sz_decimals = metadata[:sz_decimals]
      is_spot = metadata[:is_spot]

      # Round to 5 significant figures first
      sig_figs_str = format('%.5g', px)
      sig_figs_price = sig_figs_str.to_f

      # Calculate decimal places: (6 for perp, 8 for spot) - szDecimals
      base_decimals = is_spot ? 8 : 6
      decimal_places = [base_decimals - sz_decimals, 0].max

      # Round to decimal places
      rounded = sig_figs_price.round(decimal_places)

      # Format with fixed decimal places
      format("%.#{decimal_places}f", rounded)
    end

    # Normalize an order ID to the correct wire format
    # @param oid [Integer, Cloid, String] Order ID or client order ID
    # @return [Integer, String] Normalized order ID
    def normalize_oid(oid)
      case oid
      when Integer then oid
      when Cloid then oid.to_raw
      when String then normalize_cloid(oid)
      else raise ArgumentError, "oid must be Integer, Cloid, or String. Got: #{oid.class}"
      end
    end

    # Convert a float USD amount to an integer (scaled by 10^6)
    # @param value [Numeric] USD amount
    # @return [Integer] Scaled integer value
    def float_to_usd_int(value)
      scaled = value.to_f * 1_000_000
      rounded = scaled.round
      raise ArgumentError, "float_to_usd_int causes rounding: #{value}" if (rounded - scaled).abs >= 1e-3

      rounded
    end

    # Convert cloid to raw string format
    # @param cloid [Cloid, String, nil] Client order ID
    # @return [String, nil] Raw cloid string
    def normalize_cloid(cloid)
      case cloid
      when nil
        nil
      when Cloid
        cloid.to_raw
      when String
        # Validate format
        unless cloid.match?(/\A0x[0-9a-fA-F]{32}\z/i)
          raise ArgumentError,
                "cloid must be '0x' followed by 32 hex characters (16 bytes). Got: #{cloid.inspect}"
        end
        cloid.downcase
      else
        raise ArgumentError, "cloid must be Cloid, String, or nil. Got: #{cloid.class}"
      end
    end

    # Convert order type to wire format
    # @param order_type [Hash] Order type configuration
    # @return [Hash] Wire format order type
    def order_type_to_wire(order_type)
      if order_type[:limit]
        { limit: { tif: order_type[:limit][:tif] || 'Gtc' } }
      elsif order_type[:trigger]
        trigger = order_type[:trigger]

        # Validate required fields
        raise ArgumentError, 'Trigger orders require :trigger_px' unless trigger[:trigger_px]
        raise ArgumentError, 'Trigger orders require :tpsl' unless trigger[:tpsl]
        unless %w[tp sl].include?(trigger[:tpsl])
          raise ArgumentError, "tpsl must be 'tp' or 'sl', got: #{trigger[:tpsl]}"
        end

        {
          trigger: {
            isMarket: trigger[:is_market] || false,
            triggerPx: float_to_wire(trigger[:trigger_px]),
            tpsl: trigger[:tpsl]
          }
        }
      else
        raise ArgumentError, 'order_type must specify :limit or :trigger'
      end
    end

    # Post an action to the exchange endpoint
    def post_action(action, signature, nonce, vault_address)
      payload = {
        action: action,
        nonce: nonce,
        signature: signature
      }
      payload[:vaultAddress] = vault_address if vault_address
      payload[:expiresAfter] = @expires_after if @expires_after

      @client.post(Constants::EXCHANGE_ENDPOINT, payload)
    end
  end
end
