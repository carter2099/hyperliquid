# API Reference

## Info Methods

Read-only methods for querying market data and user information.

### General Info

- `all_mids()` - Retrieve mids for all coins
- `open_orders(user)` - Retrieve a user's open orders
- `frontend_open_orders(user, dex: nil)` - Retrieve a user's open orders with additional frontend info
- `user_fills(user)` - Retrieve a user's fills
- `user_fills_by_time(user, start_time, end_time = nil)` - Retrieve a user's fills by time (optional end time)
- `user_rate_limit(user)` - Query user rate limits
- `order_status(user, oid)` - Query order status by order id (oid)
- `order_status_by_cloid(user, cloid)` - Query order status by client order id (cloid)
- `l2_book(coin)` - L2 book snapshot (Perpetuals and Spot)
- `candles_snapshot(coin, interval, start_time, end_time)` - Candle snapshot (Perpetuals and Spot)
- `max_builder_fee(user, builder)` - Check builder fee approval
- `historical_orders(user, start_time = nil, end_time = nil)` - Retrieve a user's historical orders
- `user_twap_slice_fills(user, start_time = nil, end_time = nil)` - Retrieve a user's TWAP slice fills
- `user_subaccounts(user)` - Retrieve a user's subaccounts
- `vault_details(vault_address, user = nil)` - Retrieve details for a vault
- `user_vault_equities(user)` - Retrieve a user's vault deposits
- `user_role(user)` - Query a user's role
- `portfolio(user)` - Query a user's portfolio
- `referral(user)` - Query a user's referral information
- `user_fees(user)` - Query a user's fees and fee schedule
- `delegations(user)` - Query a user's staking delegations
- `delegator_summary(user)` - Query a user's staking summary
- `delegator_history(user)` - Query a user's staking history
- `delegator_rewards(user)` - Query a user's staking rewards

### Perpetuals Methods

- `perp_dexs()` - Retrieve all perpetual DEXs
- `meta(dex: nil)` - Get asset metadata (optionally for a specific perp DEX)
- `meta_and_asset_ctxs()` - Get extended asset metadata
- `user_state(user, dex: nil)` - Retrieve user's perpetuals account summary (optionally for a specific perp DEX)
- `predicted_fundings()` - Retrieve predicted funding rates across venues
- `perps_at_open_interest_cap()` - Query perps at open interest caps
- `perp_deploy_auction_status()` - Retrieve Perp Deploy Auction status
- `active_asset_data(user, coin)` - Retrieve a user's active asset data for a coin
- `perp_dex_limits(dex)` - Retrieve builder-deployed perp market limits for a DEX
- `user_funding(user, start_time, end_time = nil)` - Retrieve a user's funding history (optional end time)
- `user_non_funding_ledger_updates(user, start_time, end_time = nil)` - Retrieve a user's non-funding ledger updates. Non-funding ledger updates include deposits, transfers, and withdrawals. (optional end time)
- `funding_history(coin, start_time, end_time = nil)` - Retrieve historical funding rates (optional end time)

### Spot Methods

- `spot_meta()` - Retrieve spot metadata (tokens and universe)
- `spot_meta_and_asset_ctxs()` - Retrieve spot metadata and asset contexts
- `spot_balances(user)` - Retrieve a user's spot token balances
- `spot_deploy_state(user)` - Retrieve Spot Deploy Auction information
- `spot_pair_deploy_auction_status()` - Retrieve Spot Pair Deploy Auction status
- `token_details(token_id)` - Retrieve information about a token by tokenId

## Exchange Methods (Trading)

**Note:** Exchange methods require initializing the SDK with a `private_key`.

- `order(coin:, is_buy:, size:, limit_px:, ...)` - Place a single limit order
- `bulk_orders(orders:, grouping:, ...)` - Place multiple orders in a batch
- `market_order(coin:, is_buy:, size:, slippage:, ...)` - Place a market order with slippage
- `cancel(coin:, oid:, ...)` - Cancel an order by order ID
- `cancel_by_cloid(coin:, cloid:, ...)` - Cancel an order by client order ID
- `bulk_cancel(cancels:, ...)` - Cancel multiple orders by order ID
- `bulk_cancel_by_cloid(cancels:, ...)` - Cancel multiple orders by client order ID
- `address` - Get the wallet address associated with the private key

All exchange methods support an optional `vault_address:` parameter for vault trading.

### Order Types

- `{ limit: { tif: 'Gtc' } }` - Good-til-canceled (default)
- `{ limit: { tif: 'Ioc' } }` - Immediate-or-cancel
- `{ limit: { tif: 'Alo' } }` - Add-liquidity-only (post-only)

### Trigger Orders (Stop Loss / Take Profit)

Trigger orders execute when a price threshold is reached:

- `tpsl: 'sl'` - Stop loss
- `tpsl: 'tp'` - Take profit
- `is_market: true/false` - Execute as market or limit order when triggered

### Client Order IDs (Cloid)

Client order IDs must be 16 bytes in hex format (`0x` + 32 hex characters).

Factory methods:
- `Hyperliquid::Cloid.from_int(n)` - Create from integer (zero-padded)
- `Hyperliquid::Cloid.from_str(s)` - Create from hex string
- `Hyperliquid::Cloid.from_uuid(uuid)` - Create from UUID
- `Hyperliquid::Cloid.random` - Generate random
