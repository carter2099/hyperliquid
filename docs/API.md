# API Reference

Every public method of the SDK is listed here, grouped to mirror `lib/`. Entries use the form
`` - `method(signature)` - description ``; the signature is the Ruby signature from `lib/` (optional
arguments show their default). Info and Exchange methods return the parsed JSON response (Hash or Array)
unchanged. `spec/docs_coverage_spec.rb` fails the build when a public method, parameter, or WebSocket
channel is missing from this file.

## SDK

- `Hyperliquid.new(testnet: false, timeout: 30, retry_enabled: false, private_key: nil, expires_after: nil)` - Create an SDK instance. `private_key` enables `exchange`; `expires_after` (ms timestamp) applies to L1 actions. See [CONFIGURATION.md](CONFIGURATION.md)
- `info` - The `Hyperliquid::Info` client (always available)
- `exchange` - The `Hyperliquid::Exchange` client, or `nil` when no `private_key` was given
- `ws` - The `Hyperliquid::WS::Client` (main API WebSocket + explorer WebSocket)
- `testnet?` - Whether the SDK targets testnet
- `base_url` - The HTTP API base URL in use

## Info

Read-only queries (`POST /info`, or the explorer RPC for the Explorer RPC section). `user` arguments are wallet addresses (`0x` + 40 hex). Times are milliseconds since epoch.

### General

- `all_mids(dex: nil)` - Mid prices for all coins. `dex:` selects a HIP-3 perp dex; spot mids are only included for the default dex
- `open_orders(user, dex: nil)` - A user's open orders (optional HIP-3 `dex:`)
- `frontend_open_orders(user, dex: nil)` - A user's open orders with additional frontend info (optional HIP-3 `dex:`)
- `user_fills(user)` - A user's most recent fills
- `user_fills_by_time(user, start_time, end_time = nil, aggregate_by_time: nil, reversed: nil)` - A user's fills in a time range. `aggregate_by_time: true` merges partial fills of one crossing order; `reversed: true` returns newest first
- `user_rate_limit(user)` - A user's request rate limit and usage
- `order_status(user, oid)` - Order status by order id
- `order_status_by_cloid(user, cloid)` - Order status by client order id (`Cloid` or hex String)
- `l2_book(coin)` - L2 order book snapshot (perp or spot)
- `recent_trades(coin)` - Recent trades for a coin
- `block_details(height)` - Block details by block height
- `candles_snapshot(coin, interval, start_time, end_time)` - Candles for a coin (intervals listed under WebSocket below)
- `max_builder_fee(user, builder)` - Maximum builder fee the user approved for `builder`
- `approved_builders(user)` - Builders the user has approved
- `historical_orders(user, start_time = nil, end_time = nil)` - A user's historical orders
- `user_twap_slice_fills(user, start_time = nil, end_time = nil)` - A user's TWAP slice fills
- `user_twap_slice_fills_by_time(user, start_time, end_time = nil, aggregate_by_time: nil)` - A user's TWAP slice fills in a time range (`aggregate_by_time:` as for `user_fills_by_time`)
- `user_subaccounts(user)` - A user's sub-accounts
- `sub_accounts2(user)` - A user's sub-accounts with per-dex clearinghouse and spot state
- `vault_details(vault_address, user = nil)` - Vault details, optionally with `user`'s position in it
- `user_vault_equities(user)` - A user's vault deposits
- `vault_summaries` - Vaults created less than 2 hours ago
- `user_role(user)` - A user's role (user, agent, vault, sub-account, missing)
- `portfolio(user)` - A user's portfolio history by period
- `referral(user)` - A user's referral state
- `user_fees(user)` - A user's effective fee rates and fee schedule
- `delegations(user)` - A user's staking delegations
- `delegator_summary(user)` - A user's staking summary
- `delegator_history(user)` - A user's staking history
- `delegator_rewards(user)` - A user's staking rewards
- `extra_agents(user)` - A user's authorized agent wallets
- `user_to_multi_sig_signers(user)` - Multi-sig signer configuration for a user
- `user_dex_abstraction(user)` - A user's HIP-3 dex-abstraction setting
- `user_abstraction(user)` - A user's account abstraction mode
- `pre_transfer_check(user, source)` - Destination existence, activation fee and sanctions check before a transfer from `source`
- `vip?(user)` - Whether a user is a VIP
- `liquidatable` - Addresses of currently liquidatable users
- `validator_summaries` - Validator performance summaries
- `exchange_status` - Exchange system status
- `max_market_order_ntls` - Maximum market order notional per asset
- `validator_l1_votes` - L1 governance votes cast by validators
- `gossip_root_ips` - Gossip root IPs
- `gossip_priority_auction_status` - Gossip priority auction status (previous winners and current auctions)
- `legal_check(user)` - A user's legal verification status
- `margin_table(id, dex: nil)` - Margin requirement table by id. `dex:` is `""` for the main dex; `nil` omits it
- `leading_vaults(user)` - Vaults a user leads
- `twap_history(user)` - A user's TWAP order history
- `web_data2(user)` - Combined user and market data in one response (frontend snapshot)

### Perpetuals

- `perp_dexs` - All perp dexs (`nil` entry = the canonical dex)
- `meta(dex: nil)` - Perp asset metadata (optional HIP-3 `dex:`)
- `meta_and_asset_ctxs` - Perp metadata plus asset contexts (mark price, funding, open interest)
- `all_perp_metas` - Metadata for every perp dex
- `user_state(user, dex: nil)` - A user's perp account summary (optional HIP-3 `dex:`)
- `predicted_fundings` - Predicted funding rates across venues
- `perps_at_open_interest_cap` - Perps currently at their open interest cap
- `perp_deploy_auction_status` - Perp deploy auction status
- `active_asset_data(user, coin)` - A user's leverage, max trade sizes and available margin for a coin
- `perp_dex_limits(dex)` - Limits for a builder-deployed perp dex
- `perp_dex_status(dex)` - Status (for example total net deposit) of a builder-deployed perp dex; `""` is the first dex
- `perp_categories` - Perp asset categories
- `perp_annotation(coin)` - Annotation for one perp asset
- `perp_concise_annotations` - Concise annotations for all perp assets
- `outcome_meta` - HIP-4 prediction-market outcome metadata
- `settled_outcome(outcome:)` - Settlement details of a HIP-4 outcome (`nil` if not settled)
- `outcome_templates` - HIP-4 outcome templates available to deployers
- `outcome_deployer_limits(venue)` - Deployer limits of a HIP-4 outcome venue
- `usdc_routing` - USDC deposit/withdrawal routing configuration
- `user_funding(user, start_time, end_time = nil)` - A user's funding payments
- `user_non_funding_ledger_updates(user, start_time, end_time = nil)` - A user's deposits, transfers and withdrawals
- `funding_history(coin, start_time, end_time = nil)` - Historical funding rates for a coin

### Spot

- `spot_meta` - Spot tokens and pairs
- `spot_meta_and_asset_ctxs` - Spot metadata plus asset contexts
- `spot_balances(user)` - A user's spot token balances
- `spot_deploy_state(user)` - A user's spot deploy auction state
- `spot_pair_deploy_auction_status` - Spot pair deploy auction status
- `token_details(token_id)` - Token details by 34-character hex token id
- `aligned_quote_token_info(token)` - Deprecated, to be removed in 2.0.0: the API no longer serves `alignedQuoteTokenInfo` (HTTP 422, raised as `Hyperliquid::ClientError`)

### Borrow/Lend (HIP-2)

- `borrow_lend_user_state(user)` - A user's borrow/lend positions
- `borrow_lend_reserve_state(token)` - Reserve state of one token (token index)
- `all_borrow_lend_reserve_states` - Reserve states of all tokens
- `user_borrow_lend_interest(user, start_time, end_time = nil)` - A user's interest accrual history

### Explorer RPC

Sent to the explorer RPC (`rpc.hyperliquid.xyz/explorer`, or the testnet host) instead of `/info`.

- `tx_details(hash)` - Transaction details by hash (66-character hex)
- `user_details(user)` - A user's recent transactions

## Exchange

Signed actions (`POST /exchange`). Requires `Hyperliquid.new(private_key: ...)`. Unless noted, actions are L1 actions: they honour the SDK's `expires_after` and, where the signature has `vault_address:`, act for that vault or sub-account. User-signed actions (noted below) reject `expires_after`; leave it `nil` for them. Sizes and prices accept Numeric or String.

### Orders

- `order(coin:, is_buy:, size:, limit_px:, order_type: { limit: { tif: 'Gtc' } }, reduce_only: false, cloid: nil, vault_address: nil, builder: nil)` - Place one order. See Order Types, Trigger Orders and Builder Fees below
- `bulk_orders(orders:, grouping: 'na', vault_address: nil, builder: nil)` - Place several orders. Each Hash takes the `order` keywords; `grouping:` is `'na'`, `'normalTpsl'` or `'positionTpsl'`
- `market_order(coin:, is_buy:, size:, slippage: 0.05, vault_address: nil, builder: nil)` - IoC limit order at the mid price plus `slippage`
- `twap_order(coin:, is_buy:, size:, reduce_only:, minutes:, randomize:, vault_address: nil, details: nil)` - TWAP order over `minutes` (5-1440). `details:` is passed through: `{ t: { p:, a: } | nil, s: <String> | nil }`
- `twap_cancel(coin:, twap_id:, vault_address: nil)` - Cancel a TWAP order
- `trailing_stop(coin:, is_buy:, size:, reduce_only:, retracement:, activation_px: nil, vault_address: nil)` - Trailing stop. `retracement:` is `{ pct: '1.5%' }` or `{ px: '<price>' }`; `activation_px: nil` means no activation price

### Cancels

- `cancel(coin:, oid:, vault_address: nil, fast: nil)` - Cancel by order id. `fast: true` requests fast cancel
- `cancel_by_cloid(coin:, cloid:, vault_address: nil, fast: nil)` - Cancel by client order id. `fast: true` requests fast cancel
- `bulk_cancel(cancels:, vault_address: nil)` - Cancel several orders; each Hash is `{ coin:, oid: }`
- `bulk_cancel_by_cloid(cancels:, vault_address: nil)` - Cancel several orders; each Hash is `{ coin:, cloid: }`
- `schedule_cancel(time: nil, vault_address: nil)` - Cancel all orders at `time` (ms, at least 5 s ahead); `time: nil` removes the scheduled cancel

### Modifications

- `modify_order(oid:, coin:, is_buy:, size:, limit_px:, order_type: { limit: { tif: 'Gtc' } }, reduce_only: false, cloid: nil, vault_address: nil, always_place: nil)` - Modify an order by oid or `Cloid`. `always_place: true` places the new order even if the original is gone
- `batch_modify(modifies:, vault_address: nil)` - Modify several orders; each Hash takes the `modify_order` keywords including `:always_place`

### Positions and Margin

- `update_leverage(coin:, leverage:, is_cross: true, vault_address: nil)` - Set cross or isolated leverage
- `update_isolated_margin(coin:, amount:, vault_address: nil)` - Add (positive) or remove (negative) isolated margin
- `market_close(coin:, size: nil, slippage: 0.05, cloid: nil, vault_address: nil, builder: nil)` - Close a position at market; `size: nil` closes all of it
- `top_up_isolated_only_margin(coin:, leverage:, vault_address: nil)` - Top up isolated-only margin to reach a target leverage

### Transfers

- `usd_send(amount:, destination:)` - Send USDC (user-signed)
- `spot_send(amount:, destination:, token:)` - Send a spot token; `token` is `"NAME:0x<tokenId>"` and token ids differ per network (`info.spot_meta`), e.g. PURR is `"PURR:0xc1fb593aeffbeb02f85e0308e9956a90"` on mainnet and `"PURR:0xc4bf3f870c0e9465323c0b6ed28096c2"` on testnet (user-signed)
- `usd_class_transfer(amount:, to_perp:, sub_account: nil)` - Move USDC between perp and spot; `sub_account:` targets a sub-account (user-signed)
- `withdraw_from_bridge(amount:, destination:)` - Withdraw USDC through the bridge (user-signed)
- `send_asset(destination:, source_dex:, destination_dex:, token:, amount:)` - Move an asset between dexes or users; dex `""` is the main perp dex, `"spot"` is spot (user-signed)
- `agent_send_asset(destination:, source_dex:, destination_dex:, token:, amount:, from_sub_account: '')` - Agent-signed `send_asset`; `destination` must be the agent's principal
- `send_to_evm_with_data(token:, amount:, source_dex:, destination_recipient:, address_encoding:, destination_chain_id:, gas_limit:, data: '0x')` - Send to HyperEVM with calldata for `ICoreReceiveWithData` contracts. `address_encoding:` is `'hex'` or `'base58'` (user-signed)

### Sub-Accounts

- `create_sub_account(name:)` - Create a sub-account
- `sub_account_transfer(sub_account_user:, is_deposit:, usd:)` - Move USDC to or from a sub-account
- `sub_account_spot_transfer(sub_account_user:, is_deposit:, token:, amount:)` - Move a spot token to or from a sub-account
- `sub_account_modify(sub_account_user:, name:)` - Rename a sub-account

### Vaults

- `vault_transfer(vault_address:, is_deposit:, usd:)` - Deposit to or withdraw from a vault
- `create_vault(name:, description:, initial_usd:)` - Create a vault led by this wallet (name 3-50 chars, description 10-250 chars, at least 100 USD)
- `vault_modify(vault_address:, allow_deposits: nil, always_close_on_withdraw: nil)` - Change vault settings (leader only); `nil` leaves a setting unchanged
- `vault_distribute(vault_address:, usd:)` - Distribute USD to followers (leader only); `usd: 0` closes the vault

### Referrals and Profile

- `set_referrer(code:)` - Use a referral code
- `register_referrer(code:)` - Create your own referral code
- `claim_rewards` - Claim referral rewards
- `set_display_name(display_name:)` - Set the leaderboard name; `""` removes it

### Agents and Builders

- `approve_agent(agent_address:, agent_name: nil)` - Authorize an agent wallet (user-signed)
- `approve_builder_fee(builder:, max_fee_rate:)` - Approve a builder fee, for example `max_fee_rate: '0.01%'` (user-signed)

### Staking

- `token_delegate(validator:, wei:, is_undelegate:)` - Delegate or undelegate HYPE; `wei` is HYPE x 1e8 (user-signed)
- `c_deposit(wei:)` - Move HYPE from spot into staking; `wei` is HYPE x 1e8 (user-signed)
- `c_withdraw(wei:)` - Move HYPE from staking to spot; `wei` is HYPE x 1e8 (user-signed)
- `link_staking_user(user:, is_finalize:)` - Link staking and trading accounts: the trading user calls with `is_finalize: false`, the staking user finalizes with `true`; `user` is the other account (user-signed)
- `staking_link_disable_trading_user(trading_user:)` - Permanently disable a linked trading user. Irreversible (user-signed)

### Account Modes

- `user_dex_abstraction(enabled:, user: nil)` - Enable or disable HIP-3 dex abstraction (user-signed)
- `agent_enable_dex_abstraction(vault_address: nil)` - Enable dex abstraction from an agent (enable only)
- `agent_set_abstraction(abstraction:, vault_address: nil)` - Set abstraction from an agent: `'u'` unified, `'p'` portfolio margin, `'i'` disabled
- `user_set_abstraction(user:, abstraction:)` - Set a user's abstraction: `'unifiedAccount'`, `'portfolioMargin'` or `'disabled'` (long form, unlike the agent action's short codes) (user-signed)
- `user_portfolio_margin(user:, enabled:)` - Enable or disable portfolio margin (user-signed)
- `use_big_blocks(enable:)` - Route the account's HyperEVM transactions to big blocks
- `spot_user(opt_out:)` - Opt out of (`true`) or into (`false`) spot dusting

### Multi-Sig

- `convert_to_multi_sig_user(authorized_users:, threshold:)` - Turn this account into a multi-sig user (user-signed)
- `multi_sig(multi_sig_user:, inner_action:, signatures:, nonce: nil, vault_address: nil)` - Submit `inner_action` for a multi-sig user with co-signer signatures. `nonce` must equal the nonce every co-signer signed. See Multi-Sig Co-Signing below

### Borrow/Lend (HIP-2)

- `borrow_lend(operation:, token:, amount: nil, vault_address: nil)` - `operation:` is `'supply'`, `'withdraw'`, `'repay'` or `'borrow'`; `token` is a token index; `amount: nil` uses the full position

### HIP-3

- `hip3_liquidator_transfer(dex:, ntl:, is_deposit:)` - Deposit to or withdraw from a HIP-3 dex's backstop liquidator; `ntl` is in 1e-6 quote units, multiple of 1_000_000_000

### Outcomes (HIP-4)

- `split_outcome(outcome:, amount:)` - Split quote tokens into Yes and No shares
- `merge_outcome(outcome:, amount: nil)` - Merge Yes and No shares into quote tokens; `nil` merges the maximum
- `merge_question(question:, amount: nil)` - Merge Yes shares of every outcome of a question; `nil` merges the maximum
- `negate_outcome(question:, outcome:, amount:)` - Turn No shares of one outcome into Yes shares of the question's other outcomes
- `activate_outcome_deployer(is_deactivate:)` - Activate (`false`) or deactivate (`true`) this wallet as an outcome deployer

### Tokens and HyperEVM

- `finalize_evm_contract(token:, input:)` - Finalize a spot token's ERC-20 link; `input:` is `{ create: { nonce: n } }`, `'firstStorageSlot'` or `'customStorageSlot'`
- `authorize_aqav2_role(token:, role:)` - Authorize an AQAv2 role, `'technical'` or `'treasury'`

### Rate Limits and Nonces

- `reserve_request_weight(weight:, destination: nil)` - Buy extra request weight, optionally for another existing user
- `noop(nonce: nil, vault_address: nil)` - Consume a nonce without side effects

### Validators

- `gossip_priority_bid(slot_id:, ip:, max_gas:, vault_address: nil)` - Bid for a gossip priority slot

Validator-operator L1 actions. Signed by the validator (or, for `c_signer_*`, its signer) key; no `vault_address:`; all support `expires_after`.

- `c_signer_jail_self` - Jail the signer's own validator (`CSignerAction`)
- `c_signer_unjail_self` - Unjail the signer's own validator (`CSignerAction`)
- `validator_l1_stream(risk_free_rate:)` - Validator vote on the aligned-quote-asset risk-free rate (e.g. `'0.04'` for 4%)

### Client Utilities

- `address` - The signing wallet's address
- `expires_after=(value)` - Set or clear (`nil`) the ms expiry applied to later L1 actions
- `reload_metadata!` - Clear the cached asset metadata (call after new listings)

### Order Types

- `{ limit: { tif: 'Gtc' } }` - Good-til-canceled (default)
- `{ limit: { tif: 'Ioc' } }` - Immediate-or-cancel
- `{ limit: { tif: 'Alo' } }` - Add-liquidity-only (post-only)

### Trigger Orders (Stop Loss / Take Profit)

`order_type: { trigger: { trigger_px:, is_market:, tpsl: } }`, where `tpsl:` is `'sl'` (stop loss) or `'tp'` (take profit) and `is_market:` chooses a market or limit order on trigger.

### Builder Fees

`order`, `bulk_orders`, `market_order` and `market_close` take `builder: { b: '0x...', f: 10 }`: builder address and fee in tenths of a basis point. The user must first call `approve_builder_fee`.

## Multi-Sig Co-Signing

Co-signers sign the inner action themselves and hand the signature (`{ r:, s:, v: }`) to the submitter, who calls `Exchange#multi_sig` with the same `nonce`. `signer:` is a `Hyperliquid::Signing::Signer.new(private_key:, testnet:)`.

- `Hyperliquid::Signing::MultiSig.sign_as_co_signer_l1(signer:, inner_action:, multi_sig_user:, outer_signer:, nonce:, vault_address: nil, expires_after: nil)` - Co-sign an L1 inner action (orders, cancels, leverage)
- `Hyperliquid::Signing::MultiSig.sign_as_co_signer_user_signed(signer:, inner_action:, multi_sig_user:, outer_signer:, primary_type:, sign_types:)` - Co-sign a user-signed inner action; `primary_type:`/`sign_types:` are the inner action's EIP-712 type name and `Signing::EIP712` constant

## Client Order IDs (Cloid)

A client order id is 16 bytes, `0x` + 32 hex characters.

- `Hyperliquid::Cloid.from_int(value)` - From an integer (zero-padded)
- `Hyperliquid::Cloid.from_str(value)` - From a hex string
- `Hyperliquid::Cloid.from_uuid(uuid)` - From a UUID
- `Hyperliquid::Cloid.random` - Random id
- `to_raw` - The `0x`-prefixed hex string

## WebSocket

`sdk.ws` streams real-time data and needs no private key. It holds two independent connections: the main API WebSocket (`subscribe`) and the explorer WebSocket (`subscribe_explorer_block`, `subscribe_explorer_txs`). Each connects on first use. See [WS.md](WS.md) for threading, routing and reconnection.

- `Hyperliquid::WS::Client.new(testnet: false, max_queue_size: 1024, reconnect: true, explorer_ws_url: nil)` - Standalone client; `explorer_ws_url: nil` disables the explorer methods (the SDK passes the right URL)
- `connect` - Open the main connection (`subscribe` calls it if needed)
- `subscribe(subscription, &callback)` - Subscribe to a main-API channel (table below); the block gets each message's `data`. Returns a subscription id
- `subscribe_explorer_block(&)` - Stream new blocks; the block gets an Array of block summaries. Returns a subscription id
- `subscribe_explorer_txs(&)` - Stream new transactions; the block gets an Array of transactions. Returns a subscription id
- `unsubscribe(subscription_id)` - Remove a callback; the server unsubscribe is sent when a channel's last callback goes
- `close` - Close both connections and stop their threads
- `connected?` - Whether the main connection is open
- `explorer_connected?` - Whether the explorer connection is open
- `on(event, &callback)` - Lifecycle hook for `:open`, `:close` or `:error` on the main connection only (the explorer connection has no hooks). One callback per event; a new one replaces the old
- `dropped_message_count` - Main-connection messages dropped because the queue was full
- `explorer_dropped_message_count` - Explorer messages dropped because the queue was full

### Main API Channels

| Channel | Subscription | Description |
|---------|-------------|-------------|
| `allMids` | `{ type: 'allMids' }` | Mid prices for all coins |
| `l2Book` | `{ type: 'l2Book', coin: 'ETH' }` | Order book updates; add `fast: true` for faster, shallower snapshots |
| `trades` | `{ type: 'trades', coin: 'ETH' }` | Trades for a coin |
| `bbo` | `{ type: 'bbo', coin: 'ETH' }` | Best bid/offer for a coin |
| `candle` | `{ type: 'candle', coin: 'ETH', interval: '1m' }` | Candle updates |
| `orderUpdates` | `{ type: 'orderUpdates', user: '0x...' }` | A user's order status changes |
| `userEvents` | `{ type: 'userEvents', user: '0x...' }` | A user's fills, funding, liquidations and other events |
| `userFills` | `{ type: 'userFills', user: '0x...' }` | A user's fills |
| `userFundings` | `{ type: 'userFundings', user: '0x...' }` | A user's funding payments |

Candle intervals: `1m`, `3m`, `5m`, `15m`, `30m`, `1h`, `2h`, `4h`, `8h`, `12h`, `1d`, `3d`, `1w`, `1M`

### Explorer Channels

| Channel | Method | Callback receives |
|---------|--------|-------------------|
| `explorerBlock` | `subscribe_explorer_block` | Array of blocks (`height`, `blockTime`, `hash`, `numTxs`, `proposer`) |
| `explorerTxs` | `subscribe_explorer_txs` | Array of transactions (`action`, `block`, `error`, `hash`, `time`, `user`) |
