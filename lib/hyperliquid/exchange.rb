# frozen_string_literal: true

module Hyperliquid
  # Exchange API client for write operations (orders, cancels, etc.)
  class Exchange
    # Initialize the exchange client
    # @param client [Hyperliquid::Client] HTTP client
    # @param signer [Hyperliquid::Signing::Signer] EIP-712 signer
    # @param info [Hyperliquid::Info] Info API client for metadata
    def initialize(client:, signer:, info:)
      @client = client
      @signer = signer
      @info = info
      @asset_indices = nil
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
    # @param cloid [String, nil] Client order ID (optional)
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

      signature = @signer.sign_l1_action(action, nonce, vault_address: vault_address)
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

      signature = @signer.sign_l1_action(action, nonce, vault_address: vault_address)
      post_action(action, signature, nonce, vault_address)
    end

    # Place a market order (aggressive limit IoC with slippage)
    # @param coin [String] Asset symbol
    # @param is_buy [Boolean] True for buy, false for sell
    # @param size [String, Numeric] Order size
    # @param slippage [Float] Slippage tolerance (default: 0.05 = 5%)
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Order response
    def market_order(coin:, is_buy:, size:, slippage: 0.05, vault_address: nil)
      # Get current mid price
      mids = @info.all_mids
      mid = mids[coin]&.to_f
      raise ArgumentError, "Unknown asset or no price available: #{coin}" unless mid&.positive?

      # Apply slippage
      limit_px = if is_buy
                   mid * (1 + slippage)
                 else
                   mid * (1 - slippage)
                 end

      order(
        coin: coin,
        is_buy: is_buy,
        size: size.to_s,
        limit_px: format_price(limit_px, coin),
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

      signature = @signer.sign_l1_action(action, nonce, vault_address: vault_address)
      post_action(action, signature, nonce, vault_address)
    end

    # Cancel a single order by client order ID
    # @param coin [String] Asset symbol
    # @param cloid [String] Client order ID
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Cancel response
    def cancel_by_cloid(coin:, cloid:, vault_address: nil)
      nonce = timestamp_ms

      action = {
        type: 'cancelByCloid',
        cancels: [{ asset: asset_index(coin), cloid: cloid }]
      }

      signature = @signer.sign_l1_action(action, nonce, vault_address: vault_address)
      post_action(action, signature, nonce, vault_address)
    end

    # Cancel multiple orders
    # @param cancels [Array<Hash>] Array of cancel hashes with keys:
    #   :coin and either :oid (order ID) or :cloid (client order ID)
    # @param vault_address [String, nil] Vault address for vault trading (optional)
    # @return [Hash] Bulk cancel response
    def bulk_cancel(cancels:, vault_address: nil)
      nonce = timestamp_ms

      # Determine cancel type based on first cancel
      if cancels.first&.key?(:cloid)
        cancel_wires = cancels.map do |c|
          { asset: asset_index(c[:coin]), cloid: c[:cloid] }
        end
        action = { type: 'cancelByCloid', cancels: cancel_wires }
      else
        cancel_wires = cancels.map do |c|
          { a: asset_index(c[:coin]), o: c[:oid] }
        end
        action = { type: 'cancel', cancels: cancel_wires }
      end

      signature = @signer.sign_l1_action(action, nonce, vault_address: vault_address)
      post_action(action, signature, nonce, vault_address)
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
      wire[:c] = cloid if cloid
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
      load_asset_indices unless @asset_indices
      @asset_indices[coin] || raise(ArgumentError, "Unknown asset: #{coin}")
    end

    # Load asset indices from metadata
    def load_asset_indices
      meta = @info.meta
      @asset_indices = {}
      meta['universe'].each_with_index do |asset, index|
        @asset_indices[asset['name']] = index
      end
    end

    # Convert float to wire format (string representation)
    # Hyperliquid uses string representation of floats, not integer scaling
    def float_to_wire(value)
      value.to_s
    end

    # Format price with appropriate precision
    def format_price(price, _coin = nil)
      # Use 5 significant figures for most prices
      format('%.5g', price)
    end

    # Convert order type to wire format
    def order_type_to_wire(order_type)
      if order_type[:limit]
        { limit: { tif: order_type[:limit][:tif] || 'Gtc' } }
      elsif order_type[:trigger]
        {
          trigger: {
            isMarket: order_type[:trigger][:is_market] || false,
            triggerPx: order_type[:trigger][:trigger_px].to_s,
            tpsl: order_type[:trigger][:tpsl] || 'tp'
          }
        }
      else
        { limit: { tif: 'Gtc' } }
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

      @client.post(Constants::EXCHANGE_ENDPOINT, payload)
    end
  end
end
