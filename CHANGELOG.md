## [Ruby Hyperliquid SDK Changelog]

## [1.0.0] - 2026-02-03

### WebSocket Support

- Add real-time WebSocket client (`Hyperliquid::WS::Client`) with managed connection
  - Three-thread architecture: read thread, dispatch thread, ping thread
  - Automatic reconnection with exponential backoff (1s, 2s, 4s, ..., 30s cap)
  - Heartbeat ping every 50 seconds to keep connection alive
  - Bounded message queue (1024) with overflow detection
  - Lifecycle callbacks: `on(:open)`, `on(:close)`, `on(:error)`

- Add 9 WebSocket subscription channels
  - `allMids` — mid prices for all coins
  - `l2Book` — level 2 order book updates
  - `trades` — trade feed for a coin
  - `bbo` — best bid/offer for a coin
  - `candle` — candlestick updates
  - `orderUpdates` — order status changes for a user
  - `userEvents` — all events for a user (fills, liquidations, etc.)
  - `userFills` — fill updates for a user
  - `userFundings` — funding payments for a user

### HIP-3 Support

- Add HIP-3 DEX abstraction Exchange actions
  - `user_dex_abstraction` — enable/disable DEX abstraction for automatic collateral transfers (user-signed)
  - `agent_enable_dex_abstraction` — enable DEX abstraction via agent (L1 action, enable only)
- Add full HIP-3 trading support
  - Lazy loading of HIP-3 dex asset metadata when trading prefixed coins (e.g., `xyz:GOLD`)
  - Correct HIP-3 asset ID calculation: `100000 + perp_dex_index * 10000 + index_in_meta`
  - `market_order` and `market_close` automatically use dex-specific price endpoints
- Add `dex:` parameter to `all_mids` Info endpoint for HIP-3 perp dex prices

### Info API

- Add 3 more Info endpoints
  - `extra_agents` — get authorized agent addresses for a user
  - `user_to_multi_sig_signers` — get multi-sig signer mappings for a user
  - `user_dex_abstraction` — get dex abstraction config for a user

## [0.7.0] - 2026-01-30

- Add agent, builder & delegation actions to Exchange API
  - `approve_agent` — authorize an agent wallet to trade on behalf of the account
  - `approve_builder_fee` — approve a builder fee rate for a builder address
  - `token_delegate` — delegate or undelegate HYPE tokens to a validator
- Add builder fee support on order placement
  - Optional `builder:` parameter on `order`, `bulk_orders`, `market_order`, `market_close`
- Add EIP-712 type definitions for `ApproveAgent`, `ApproveBuilderFee`, and `TokenDelegate`

## [0.6.0] - 2026-01-28

- Add transfers and account management to Exchange API
  - USD transfers: `usd_send`, `usd_class_transfer`, `withdraw_from_bridge`
  - Spot transfers: `spot_send`, `send_asset`
  - Sub-accounts: `create_sub_account`, `sub_account_transfer`, `sub_account_spot_transfer`
  - Vaults: `vault_transfer`
  - Referrals: `set_referrer`
- Add user-signed action signing (`sign_user_signed_action`) for EIP-712 typed data with `HyperliquidSignTransaction` domain
- Add Python SDK parity test vectors for `usd_send`, `withdraw_from_bridge`, `create_sub_account`, and `sub_account_transfer`
- Reorganize integration tests into individual scripts under `scripts/` for easier debugging

## [0.5.0] - 2026-01-28

- Add core trading features to Exchange API
  - Order modification: `modify_order`, `batch_modify`
  - Position management: `update_leverage`, `update_isolated_margin`, `market_close`
  - Dead man's switch: `schedule_cancel`
- Add `market_close` helper for closing positions at market price with auto-detection of size and direction
- Add integration tests for leverage updates, order modification, and market close
- Add GitHub Release workflow (`.github/workflows/release.yml`)

## [0.4.1] - 2026-01-28

- Reorganize documentation for improved readability
  - Streamline README with basic setup and links to detailed docs
  - Add `docs/API.md` with complete method reference
  - Add `docs/EXAMPLES.md` with Info and Exchange code examples
  - Add `docs/CONFIGURATION.md` with SDK options and retry settings
  - Add `docs/ERRORS.md` with error handling guide
  - Add `docs/DEVELOPMENT.md` with setup and testing instructions

## [0.4.0] - 2026-01-27

- Add Exchange API for authenticated write operations (trading)
  - Order placement: `order`, `bulk_orders`, `market_order`
  - Order cancellation: `cancel`, `cancel_by_cloid`, `bulk_cancel`, `bulk_cancel_by_cloid`
  - Trigger orders (stop loss / take profit) support
  - Vault trading support via optional `vault_address` parameter
  - Order expiration support via `expires_after` parameter
- Add EIP-712 signing infrastructure matching official Python SDK
  - Phantom agent signing scheme
  - Full parity with Python SDK signature generation
- Add new dependencies: `eth` (~> 0.5), `msgpack` (~> 1.7)
- SDK now accepts optional `private_key` and `expires_after` parameters

## [0.3.0] - 2025-09-24

- Full parity with all Hyperliquid Info APIs
  - All Info APIs implemented
  - Code, tests, and docs reflect structure of official Hyperliquid API documentation

## [0.2.0] - 2025-09-24

- Add info endpoints for user spot data

## [0.1.1] - 2025-09-23

- Fixed retry logic, make retry logic disabled by default

## [0.1.0] - 2025-08-21

- Initial release which includes info endpoints for market and user perps data
