# API Reference

## Info Methods

Read-only methods for querying market data and user information.

### General Info

- `all_mids(dex: nil)` - Retrieve mids for all coins (optional dex for HIP-3 perp dexs; spot mids only included with default dex)
- `open_orders(user, dex: nil)` - Retrieve a user's open orders (optional dex for HIP-3)
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
- `extra_agents(user)` - Get authorized agent addresses for a user
- `user_to_multi_sig_signers(user)` - Get multi-sig signer mappings for a user
- `user_dex_abstraction(user)` - Get dex abstraction config for a user

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

### Order Placement

- `order(coin:, is_buy:, size:, limit_px:, ...)` - Place a single limit order
- `bulk_orders(orders:, grouping:, ...)` - Place multiple orders in a batch
- `market_order(coin:, is_buy:, size:, slippage:, ...)` - Place a market order with slippage

### Order Modification

- `modify_order(oid:, coin:, is_buy:, size:, limit_px:, ...)` - Modify an existing order by oid or cloid
- `batch_modify(modifies:, ...)` - Modify multiple orders at once

### Order Cancellation

- `cancel(coin:, oid:, ...)` - Cancel an order by order ID
- `cancel_by_cloid(coin:, cloid:, ...)` - Cancel an order by client order ID
- `bulk_cancel(cancels:, ...)` - Cancel multiple orders by order ID
- `bulk_cancel_by_cloid(cancels:, ...)` - Cancel multiple orders by client order ID
- `schedule_cancel(time:, ...)` - Auto-cancel all orders at a given time

### Position Management

- `market_close(coin:, size:, slippage:, ...)` - Close a position at market price (auto-detects position size)
- `update_leverage(coin:, leverage:, is_cross:, ...)` - Set cross or isolated leverage for a coin
- `update_isolated_margin(coin:, amount:, ...)` - Add or remove isolated margin for a position

### Transfers & Account Management

- `usd_send(amount:, destination:)` - Transfer USDC to another address
- `spot_send(amount:, destination:, token:)` - Transfer a spot token to another address
- `usd_class_transfer(amount:, to_perp:)` - Move USDC between perp and spot accounts
- `withdraw_from_bridge(amount:, destination:)` - Withdraw USDC via the bridge
- `send_asset(destination:, source_dex:, destination_dex:, token:, amount:)` - Move assets between DEX instances
- `create_sub_account(name:)` - Create a sub-account
- `sub_account_transfer(sub_account_user:, is_deposit:, usd:)` - Transfer USDC to/from a sub-account
- `sub_account_spot_transfer(sub_account_user:, is_deposit:, token:, amount:)` - Transfer spot tokens to/from a sub-account
- `vault_transfer(vault_address:, is_deposit:, usd:)` - Deposit or withdraw USDC to/from a vault
- `set_referrer(code:)` - Set referral code

### Agent & Builder

- `approve_agent(agent_address:, agent_name:)` - Authorize an agent wallet to trade on behalf of this account
- `approve_builder_fee(builder:, max_fee_rate:)` - Approve a builder fee rate for a builder address
- `token_delegate(validator:, wei:, is_undelegate:)` - Delegate or undelegate HYPE tokens to a validator

### HIP-3 DEX Abstraction

HIP-3 DEX abstraction allows automatic collateral transfers when trading on builder-deployed perpetual DEXs.

- `user_dex_abstraction(enabled:, user: nil)` - Enable or disable DEX abstraction for an account (user-signed)
- `agent_enable_dex_abstraction(vault_address: nil)` - Enable DEX abstraction via agent (L1 action, enable only)

### Other

- `address` - Get the wallet address associated with the private key

Order placement and management methods support an optional `vault_address:` parameter for vault trading.

Order placement methods (`order`, `bulk_orders`, `market_order`, `market_close`) support an optional `builder:` parameter for builder fee integration. The builder is a Hash with `:b` (builder address) and `:f` (fee in tenths of a basis point).

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

## WebSocket

Real-time data streaming via WebSocket. No private key required.

### Connection

- `ws.connect` - Connect to the WebSocket server (also called automatically on first `subscribe`)
- `ws.connected?` - Check if the WebSocket is connected
- `ws.close` - Disconnect and stop all background threads

### Subscriptions

- `ws.subscribe(subscription, &callback)` - Subscribe to a channel. Returns a subscription ID.
- `ws.unsubscribe(id)` - Unsubscribe by subscription ID. Sends unsubscribe to server when the last callback for a channel is removed.

### Lifecycle Events

- `ws.on(:open, &callback)` - Called when connection is established
- `ws.on(:close, &callback)` - Called when connection is closed
- `ws.on(:error, &callback)` - Called on connection error

### Monitoring

- `ws.dropped_message_count` - Number of messages dropped due to a full internal queue (callbacks too slow)

### Available Channels

| Channel | Subscription | Description |
|---------|-------------|-------------|
| `allMids` | `{ type: 'allMids' }` | Mid prices for all coins |
| `l2Book` | `{ type: 'l2Book', coin: 'ETH' }` | Level 2 order book updates |
| `trades` | `{ type: 'trades', coin: 'ETH' }` | Trade feed for a coin |
| `bbo` | `{ type: 'bbo', coin: 'ETH' }` | Best bid/offer for a coin |
| `candle` | `{ type: 'candle', coin: 'ETH', interval: '1m' }` | Candlestick updates |
| `orderUpdates` | `{ type: 'orderUpdates', user: '0x...' }` | Order status changes for a user |
| `userEvents` | `{ type: 'userEvents', user: '0x...' }` | All events for a user (fills, liquidations, etc.) |
| `userFills` | `{ type: 'userFills', user: '0x...' }` | Fill updates for a user |
| `userFundings` | `{ type: 'userFundings', user: '0x...' }` | Funding payments for a user |

Candle intervals: `1m`, `3m`, `5m`, `15m`, `30m`, `1h`, `2h`, `4h`, `8h`, `12h`, `1d`, `3d`, `1w`, `1M`

### Configuration

`Hyperliquid::WS::Client.new` accepts:
- `testnet:` (Boolean, default: false) - Use testnet WebSocket endpoint
- `max_queue_size:` (Integer, default: 1024) - Max messages buffered before dropping
- `reconnect:` (Boolean, default: true) - Auto-reconnect on unexpected disconnect
