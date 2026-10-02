# Examples

## Info API

### General Info

```ruby
# Retrieve mids for all coins
mids = sdk.info.all_mids
# => { "BTC" => "50000", "ETH" => "3000", ... }

# Retrieve mids for a HIP-3 perp dex (e.g., xyz)
hip3_mids = sdk.info.all_mids(dex: 'xyz')
# => { "xyz:GOLD" => "2500", "xyz:SILVER" => "30", ... }

user_address = "0x..."

# Retrieve a user's open orders
orders = sdk.info.open_orders(user_address)
# => [{ "coin" => "BTC", "sz" => "0.1", "px" => "50000", "side" => "A" }]

# Retrieve a user's open orders on a HIP-3 dex
hip3_orders = sdk.info.open_orders(user_address, dex: 'xyz')
# => [{ "coin" => "xyz:GOLD", "sz" => "1.0", ... }]

# Retrieve a user's open orders with additional frontend info
frontend_orders = sdk.info.frontend_open_orders(user_address)
# => [{ "coin" => "BTC", "isTrigger" => false, ... }]

# Retrieve a user's fills
fills = sdk.info.user_fills(user_address)
# => [{ "coin" => "BTC", "sz" => "0.1", "px" => "50000", "side" => "A", "time" => 1234567890 }]

# Retrieve a user's fills by time
start_time_ms = 1_700_000_000_000
end_time_ms = start_time_ms + 86_400_000
fills_by_time = sdk.info.user_fills_by_time(user_address, start_time_ms, end_time_ms)
# => [{ "coin" => "ETH", "px" => "3000", "time" => start_time_ms }, ...]

# Query user rate limits
rate_limit = sdk.info.user_rate_limit(user_address)
# => { "nRequestsUsed" => 100, "nRequestsCap" => 10000 }

# Query order status by oid
order_id = 12345
status_by_oid = sdk.info.order_status(user_address, order_id)
# => { "status" => "filled", ... }

# Query order status by cloid
cloid = "client-order-id-123"
status_by_cloid = sdk.info.order_status_by_cloid(user_address, cloid)
# => { "status" => "cancelled", ... }

# L2 order book snapshot
book = sdk.info.l2_book("BTC")
# => { "coin" => "BTC", "levels" => [[asks], [bids]], "time" => ... }

# Candle snapshot
candles = sdk.info.candles_snapshot("BTC", "1h", start_time_ms, end_time_ms)
# => [{ "t" => ..., "o" => "50000", "h" => "51000", "l" => "49000", "c" => "50500", "v" => "100" }]

# Check builder fee approval
builder_address = "0x..."
fee_approval = sdk.info.max_builder_fee(user_address, builder_address)
# => { "approved" => true, ... }

# Retrieve a user's historical orders
hist_orders = sdk.info.historical_orders(user_address)
# => [{ "oid" => 123, "coin" => "BTC", ... }]
hist_orders_ranged = sdk.info.historical_orders(user_address, start_time_ms, end_time_ms)
# => []

# Retrieve a user's TWAP slice fills
twap_fills = sdk.info.user_twap_slice_fills(user_address)
# => [{ "sliceId" => 1, "coin" => "ETH", "sz" => "1.0" }, ...]
twap_fills_ranged = sdk.info.user_twap_slice_fills(user_address, start_time_ms, end_time_ms)
# => []

# Retrieve a user's subaccounts
subaccounts = sdk.info.user_subaccounts(user_address)
# => ["0x1111...", ...]

# Retrieve details for a vault
vault_addr = "0x..."
vault = sdk.info.vault_details(vault_addr)
# => { "vaultAddress" => vault_addr, ... }
vault_with_user = sdk.info.vault_details(vault_addr, user_address)
# => { "vaultAddress" => vault_addr, "user" => user_address, ... }

# Retrieve a user's vault deposits
vault_deposits = sdk.info.user_vault_equities(user_address)
# => [{ "vaultAddress" => "0x...", "equity" => "123.45" }, ...]

# Query a user's role
role = sdk.info.user_role(user_address)
# => { "role" => "tradingUser" }

# Query a user's portfolio
portfolio = sdk.info.portfolio(user_address)
# => [["day", { "pnlHistory" => [...], "vlm" => "0.0" }], ...]

# Query a user's referral information
referral = sdk.info.referral(user_address)
# => { "referredBy" => { "referrer" => "0x..." }, ... }

# Query a user's fees
fees = sdk.info.user_fees(user_address)
# => { "userAddRate" => "0.0001", "feeSchedule" => { ... } }

# Query a user's staking delegations
delegations = sdk.info.delegations(user_address)
# => [{ "validator" => "0x...", "amount" => "100.0" }, ...]

# Query a user's staking summary
summary = sdk.info.delegator_summary(user_address)
# => { "delegated" => "12060.16529862", ... }

# Query a user's staking history
history = sdk.info.delegator_history(user_address)
# => [{ "time" => 1_736_726_400_073, "delta" => { ... } }, ...]

# Query a user's staking rewards
rewards = sdk.info.delegator_rewards(user_address)
# => [{ "time" => 1_736_726_400_073, "source" => "delegation", "totalAmount" => "0.123" }, ...]

# Get authorized agent addresses for a user
agents = sdk.info.extra_agents(user_address)
# => [{ "address" => "0x...", "name" => "agent1" }, ...]

# Get multi-sig signer mappings for a user
signers = sdk.info.user_to_multi_sig_signers(user_address)
# => { "signers" => ["0x...", "0x..."], "threshold" => 2 }

# Get dex abstraction config for a user
dex_abstraction = sdk.info.user_dex_abstraction(user_address)
# => { "enabled" => true }

# Fills in a time range, newest first, with partial fills of one crossing order merged
fills = sdk.info.user_fills_by_time(user_address, start_time_ms, nil, aggregate_by_time: true, reversed: true)

# Recent trades and a block by height
sdk.info.recent_trades('BTC')
sdk.info.block_details(123_456)

# Vaults created in the last 2 hours, and vaults a user leads
sdk.info.vault_summaries
sdk.info.leading_vaults(user_address)

# Margin table (dex: '' is the main dex)
sdk.info.margin_table(1, dex: '')
```

**Note:** `l2_book` and `candles_snapshot` work for both Perpetuals and Spot. For spot, use `"{BASE}/USDC"` when available (e.g., `"PURR/USDC"`). Otherwise, use the index alias `"@{index}"` from `spot_meta["universe"]`.

### Perpetuals

```ruby
# Retrieve all perpetual DEXs
perp_dexs = sdk.info.perp_dexs
# => [nil, { "name" => "test", "full_name" => "test dex", ... }]

# Retrieve perpetuals metadata (optionally for a specific perp dex)
meta = sdk.info.meta
# => { "universe" => [...] }
meta = sdk.info.meta(dex: "perp-dex-name")
# => { "universe" => [...] }

# Retrieve perpetuals asset contexts (includes mark price, current funding, open interest, etc.)
meta_ctxs = sdk.info.meta_and_asset_ctxs
# => { "universe" => [...], "assetCtxs" => [...] }

# Retrieve user's perpetuals account summary (optionally for a specific perp dex)
state = sdk.info.user_state(user_address)
# => { "assetPositions" => [...], "marginSummary" => {...} }
state = sdk.info.user_state(user_address, dex: "perp-dex-name")
# => { "assetPositions" => [...], "marginSummary" => {...} }

# Retrieve a user's funding history or non-funding ledger updates (optional end_time)
funding = sdk.info.user_funding(user_address, start_time)
# => [{ "delta" => { "type" => "funding", ... }, "time" => ... }]
funding = sdk.info.user_funding(user_address, start_time, end_time)
# => [{ "delta" => { "type" => "funding", ... }, "time" => ... }]

# Retrieve historical funding rates
hist = sdk.info.funding_history("ETH", start_time)
# => [{ "coin" => "ETH", "fundingRate" => "...", "time" => ... }]

# Retrieve predicted funding rates for different venues
pred = sdk.info.predicted_fundings
# => [["AVAX", [["HlPerp", { "fundingRate" => "0.0000125", "nextFundingTime" => ... }], ...]], ...]

# Query perps at open interest caps
oi_capped = sdk.info.perps_at_open_interest_cap
# => ["BADGER", "CANTO", ...]

# Retrieve information about the Perp Deploy Auction
auction = sdk.info.perp_deploy_auction_status
# => { "startTimeSeconds" => ..., "durationSeconds" => ..., "startGas" => "500.0", ... }

# Deploy a HIP-3 perp dex (deployer wallet only; mirrors the Python SDK's examples/perp_deploy.py).
# The first registration on a new dex passes `schema:` and pays the deploy-auction gas.
# `auction` comes from perp_deploy_auction_status above; `max_gas: nil` bids its currentGas.
sdk.exchange.perp_deploy_register_asset2(
  dex: "test", coin: "test:TEST0", sz_decimals: 2, oracle_px: "10.0", margin_table_id: 10,
  margin_mode: "noCross",
  max_gas: 1_000_000_000_000, # native-token wei: 10k HYPE
  schema: { full_name: "test dex", collateral_token: 0, oracle_updater: sdk.exchange.address }
)
# => { "status" => "ok", "response" => { "type" => "default" } }

# Push oracle prices (at most once every 2.5s); coins are full "dex:COIN" names.
# A real oracle updater runs this continuously.
3.times do
  sdk.exchange.perp_deploy_set_oracle(
    dex: "test",
    oracle_pxs: { "test:TEST0" => "12.0" },
    all_mark_pxs: [{ "test:TEST0" => "12.1" }],
    external_perp_pxs: { "test:TEST0" => "12.0" }
  )
  sleep 3
end

# Retrieve User's Active Asset Data
aad = sdk.info.active_asset_data(user_address, "APT")
# => { "user" => user_address, "coin" => "APT", "leverage" => { "type" => "cross", "value" => 3 }, ... }

# Retrieve Builder-Deployed Perp Market Limits
limits = sdk.info.perp_dex_limits("builder-dex")
# => { "totalOiCap" => "10000000.0", "oiSzCapPerPerp" => "...", ... }
```

### Spot

```ruby
# Retrieve spot metadata
spot_meta = sdk.info.spot_meta
# => { "tokens" => [...], "universe" => [...] }

# Retrieve spot asset contexts
spot_meta_ctxs = sdk.info.spot_meta_and_asset_ctxs
# => [ { "tokens" => [...], "universe" => [...] }, [ { "midPx" => "...", ... } ] ]

# Retrieve a user's token balances
balances = sdk.info.spot_balances(user_address)
# => { "balances" => [{ "coin" => "USDC", "token" => 0, "total" => "..." }, ...] }

# Retrieve information about the Spot Deploy Auction
deploy_state = sdk.info.spot_deploy_state(user_address)
# => { "states" => [...], "gasAuction" => { ... } }

# Retrieve information about the Spot Pair Deploy Auction
pair_status = sdk.info.spot_pair_deploy_auction_status
# => { "startTimeSeconds" => ..., "durationSeconds" => ..., "startGas" => "...", ... }

# Retrieve information about a token by onchain id in 34-character hexadecimal format
details = sdk.info.token_details("0x00000000000000000000000000000000")
# => { "name" => "TEST", "maxSupply" => "...", "midPx" => "...", ... }
```

### HIP-2 Borrow/Lend

```ruby
sdk.info.all_borrow_lend_reserve_states
sdk.info.borrow_lend_reserve_state(0)               # token index 0 = USDC
sdk.info.borrow_lend_user_state(user_address)
sdk.info.user_borrow_lend_interest(user_address, start_time_ms)
```

### HIP-4 Outcomes

```ruby
sdk.info.outcome_meta
sdk.info.outcome_templates
sdk.info.settled_outcome(outcome: 5)                # nil until settled
```

### Explorer RPC

```ruby
# Routed to rpc.hyperliquid.xyz/explorer (rpc.hyperliquid-testnet.xyz with testnet: true)
txs = sdk.info.user_details(user_address)
sdk.info.tx_details('0x' + 'ab' * 32)               # a 66-character transaction hash
```

## Exchange API (Trading)

### Basic Orders

```ruby
# Initialize SDK with private key for trading
sdk = Hyperliquid.new(
  testnet: true,
  private_key: ENV['HYPERLIQUID_PRIVATE_KEY']
)

# Get wallet address
address = sdk.exchange.address
# => "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Place a limit buy order
result = sdk.exchange.order(
  coin: 'BTC',
  is_buy: true,
  size: '0.01',
  limit_px: '95000',
  order_type: { limit: { tif: 'Gtc' } }  # Good-til-canceled (default)
)
# => { "status" => "ok", "response" => { "type" => "order", "data" => { "statuses" => [...] } } }

# Place a limit sell order with client order ID
cloid = Hyperliquid::Cloid.from_int(123)  # Or Cloid.random
result = sdk.exchange.order(
  coin: 'ETH',
  is_buy: false,
  size: '0.5',
  limit_px: '3500',
  cloid: cloid
)

# Place a market order (IoC with slippage)
result = sdk.exchange.market_order(
  coin: 'BTC',
  is_buy: true,
  size: '0.01',
  slippage: 0.03  # 3% slippage tolerance (default: 5%)
)

# Place multiple orders at once
orders = [
  { coin: 'BTC', is_buy: true, size: '0.01', limit_px: '94000' },
  { coin: 'BTC', is_buy: false, size: '0.01', limit_px: '96000' }
]
result = sdk.exchange.bulk_orders(orders: orders)
```

### Canceling Orders

```ruby
# Cancel an order by order ID
oid = result.dig('response', 'data', 'statuses', 0, 'resting', 'oid')
sdk.exchange.cancel(coin: 'BTC', oid: oid)

# Cancel an order by client order ID
sdk.exchange.cancel_by_cloid(coin: 'ETH', cloid: cloid)

# Cancel multiple orders by order ID
cancels = [
  { coin: 'BTC', oid: 12345 },
  { coin: 'ETH', oid: 12346 }
]
sdk.exchange.bulk_cancel(cancels: cancels)

# Cancel multiple orders by client order ID
cloid_cancels = [
  { coin: 'BTC', cloid: Hyperliquid::Cloid.from_int(1) },
  { coin: 'ETH', cloid: Hyperliquid::Cloid.from_int(2) }
]
sdk.exchange.bulk_cancel_by_cloid(cancels: cloid_cancels)
```

### Modifying Orders

```ruby
# Modify an existing order by order ID
oid = result.dig('response', 'data', 'statuses', 0, 'resting', 'oid')
sdk.exchange.modify_order(
  oid: oid,
  coin: 'BTC',
  is_buy: true,
  size: '0.02',
  limit_px: '96000'
)

# Modify an order by client order ID
cloid = Hyperliquid::Cloid.from_int(123)
sdk.exchange.modify_order(
  oid: cloid,
  coin: 'BTC',
  is_buy: true,
  size: '0.02',
  limit_px: '96000'
)

# Modify multiple orders at once
modifies = [
  { oid: 12345, coin: 'BTC', is_buy: true, size: '0.01', limit_px: '95000' },
  { oid: 12346, coin: 'ETH', is_buy: false, size: '0.5', limit_px: '3200' }
]
sdk.exchange.batch_modify(modifies: modifies)
```

### Position Management

```ruby
# Set cross leverage (default)
sdk.exchange.update_leverage(coin: 'BTC', leverage: 5)

# Set isolated leverage
sdk.exchange.update_leverage(coin: 'BTC', leverage: 10, is_cross: false)

# Add isolated margin to a position (positive amount)
sdk.exchange.update_isolated_margin(coin: 'BTC', amount: 100.0)

# Remove isolated margin from a position (negative amount)
sdk.exchange.update_isolated_margin(coin: 'BTC', amount: -50.0)

# Close an entire position at market price (auto-detects size and direction)
sdk.exchange.market_close(coin: 'BTC')

# Close a partial position with custom slippage
sdk.exchange.market_close(coin: 'BTC', size: 0.01, slippage: 0.03)
```

### Schedule Cancel

```ruby
# Schedule auto-cancel of all orders at a specific time
cancel_time = (Time.now.to_f * 1000).to_i + 60_000  # 60 seconds from now
sdk.exchange.schedule_cancel(time: cancel_time)

# Remove the scheduled cancel
sdk.exchange.schedule_cancel
```

### Vault Trading

```ruby
# Vault trading (trade on behalf of a vault)
vault_address = '0x...'
sdk.exchange.order(
  coin: 'BTC',
  is_buy: true,
  size: '1.0',
  limit_px: '95000',
  vault_address: vault_address
)
```

### Trigger Orders (Stop Loss / Take Profit)

```ruby
# Stop loss: Sell when price drops to trigger level
sdk.exchange.order(
  coin: 'BTC',
  is_buy: false,
  size: '0.1',
  limit_px: '89900',
  order_type: {
    trigger: {
      trigger_px: 90_000,
      is_market: true,  # Execute as market order when triggered
      tpsl: 'sl'        # Stop loss
    }
  }
)

# Take profit: Sell when price rises to trigger level
sdk.exchange.order(
  coin: 'BTC',
  is_buy: false,
  size: '0.1',
  limit_px: '100100',
  order_type: {
    trigger: {
      trigger_px: 100_000,
      is_market: false,  # Execute as limit order when triggered
      tpsl: 'tp'         # Take profit
    }
  }
)
```

### TWAP and Trailing Stop Orders

```ruby
# Buy 1 ETH over 30 minutes
result = sdk.exchange.twap_order(coin: 'ETH', is_buy: true, size: 1, reduce_only: false,
                                 minutes: 30, randomize: true)
twap_id = result.dig('response', 'data', 'status', 'running', 'twapId')
sdk.exchange.twap_cancel(coin: 'ETH', twap_id: twap_id)

# Reduce-only trailing sell of 0.01 BTC, 1.5% retracement, active once the price reaches 100000
sdk.exchange.trailing_stop(coin: 'BTC', is_buy: false, size: 0.01, reduce_only: true,
                           retracement: { pct: '1.5%' }, activation_px: '100000')
```

### Fast Cancel, Always-Place Modify, Order Expiry

```ruby
sdk.exchange.cancel(coin: 'BTC', oid: 123, fast: true)
sdk.exchange.modify_order(oid: 123, coin: 'BTC', is_buy: true, size: 0.01, limit_px: 95_000,
                          always_place: true)

# Reject L1 actions that reach the exchange after this time (ms); nil clears it.
# Leave it nil around user-signed actions such as usd_send.
sdk.exchange.expires_after = (Time.now.to_f * 1000).to_i + 10_000
sdk.exchange.order(coin: 'BTC', is_buy: true, size: 0.01, limit_px: 90_000)
sdk.exchange.expires_after = nil
```

### Transfers & Account Management

```ruby
# Transfer USDC to another address
sdk.exchange.usd_send(
  amount: '100',
  destination: '0x...'
)

# Transfer a spot token to another address
sdk.exchange.spot_send(
  amount: '50',
  destination: '0x...',
  token: 'PURR:0xc4bf3f870c0e9465323c0b6ed28096c2' # testnet PURR; mainnet is PURR:0xc1fb593aeffbeb02f85e0308e9956a90 (see info.spot_meta)
)

# Move USDC between perp and spot accounts
sdk.exchange.usd_class_transfer(amount: '100', to_perp: false)   # perp -> spot
sdk.exchange.usd_class_transfer(amount: '100', to_perp: true)    # spot -> perp

# Withdraw USDC via the bridge
sdk.exchange.withdraw_from_bridge(
  amount: '100',
  destination: '0x...'
)

# Move assets between DEX instances
sdk.exchange.send_asset(
  destination: '0x...',
  source_dex: 'dex1',
  destination_dex: 'dex2',
  token: 'USDC',
  amount: '100'
)

# Move USDC between perp and spot for a sub-account
sdk.exchange.usd_class_transfer(amount: 10, to_perp: true, sub_account: '0x...')

# Send USDC to HyperEVM with calldata for an ICoreReceiveWithData contract
sdk.exchange.send_to_evm_with_data(
  token: 'USDC', amount: '5', source_dex: 'spot',
  destination_recipient: '0x...', address_encoding: 'hex',
  destination_chain_id: 998, gas_limit: 200_000, data: '0x'
)
```

### Sub-Account Management

```ruby
# Create a sub-account
result = sdk.exchange.create_sub_account(name: 'my-sub-account')
sub_address = result.dig('response', 'data', 'subAccountUser')

# Deposit USDC into a sub-account
sdk.exchange.sub_account_transfer(
  sub_account_user: sub_address,
  is_deposit: true,
  usd: 100
)

# Withdraw USDC from a sub-account
sdk.exchange.sub_account_transfer(
  sub_account_user: sub_address,
  is_deposit: false,
  usd: 50
)

# Transfer spot tokens to a sub-account
sdk.exchange.sub_account_spot_transfer(
  sub_account_user: sub_address,
  is_deposit: true,
  token: 'PURR',
  amount: '10'
)
```

### Vault Operations

```ruby
# Deposit USDC into a vault
sdk.exchange.vault_transfer(
  vault_address: '0x...',
  is_deposit: true,
  usd: 100
)

# Withdraw USDC from a vault
sdk.exchange.vault_transfer(
  vault_address: '0x...',
  is_deposit: false,
  usd: 50
)

# Create a vault (at least 100 USD), then manage it as leader
sdk.exchange.create_vault(name: 'My Vault', description: 'Trend following on BTC', initial_usd: 100)
sdk.exchange.vault_modify(vault_address: '0x...', allow_deposits: false)
sdk.exchange.vault_distribute(vault_address: '0x...', usd: 25)
```

### HIP-2 Borrow/Lend and HIP-4 Outcomes

```ruby
sdk.exchange.borrow_lend(operation: 'supply', token: 0, amount: '100')
sdk.exchange.borrow_lend(operation: 'withdraw', token: 0)          # amount nil = full position

sdk.exchange.split_outcome(outcome: 5, amount: '10')               # 10 quote -> 10 Yes + 10 No
sdk.exchange.merge_outcome(outcome: 5)                             # merge the maximum back
```

### Multi-Sig

```ruby
# 1. Once: turn the multi-sig account into a 2-of-3 multi-sig user
owner = Hyperliquid.new(testnet: true, private_key: ENV['MULTI_SIG_OWNER_KEY'])
owner.exchange.convert_to_multi_sig_user(authorized_users: [addr_a, addr_b, addr_c], threshold: 2)

# 2. Each co-signer signs the same inner action and nonce, with the submitter as outer_signer
multi_sig_user = owner.exchange.address
submitter = Hyperliquid.new(testnet: true, private_key: ENV['SIGNER_A_KEY'])
nonce = (Time.now.to_f * 1000).to_i
inner_action = {
  type: 'order',
  orders: [{ a: 4, b: true, p: '1100', s: '0.2', r: false, t: { limit: { tif: 'Gtc' } } }],
  grouping: 'na'
}
signatures = [ENV['SIGNER_A_KEY'], ENV['SIGNER_B_KEY']].map do |key|
  Hyperliquid::Signing::MultiSig.sign_as_co_signer_l1(
    signer: Hyperliquid::Signing::Signer.new(private_key: key, testnet: true),
    inner_action: inner_action, multi_sig_user: multi_sig_user,
    outer_signer: submitter.exchange.address, nonce: nonce
  )
end

# 3. The submitter posts the envelope with the same nonce
submitter.exchange.multi_sig(multi_sig_user: multi_sig_user, inner_action: inner_action,
                             signatures: signatures, nonce: nonce)
```

The inner action is the wire-format action body (here an order for asset 4). For a user-signed inner action, co-signers call `sign_as_co_signer_user_signed` with its EIP-712 primary type and type constant, e.g. `primary_type: 'HyperliquidTransaction:SendAsset', sign_types: Hyperliquid::Signing::EIP712::SEND_ASSET_TYPES`.

### Referral

```ruby
# Set a referral code
sdk.exchange.set_referrer(code: 'MY_REFERRAL_CODE')
```

### Agent, Builder & Delegation

```ruby
# Authorize an agent wallet to trade on your behalf
agent_key = Eth::Key.new
result = sdk.exchange.approve_agent(
  agent_address: agent_key.address.to_s,
  agent_name: 'my-trading-bot'       # optional
)

# Approve a builder fee (required before placing orders with that builder)
sdk.exchange.approve_builder_fee(
  builder: '0x250F311Ae04D3CEA03443C76340069eD26C47D7D',
  max_fee_rate: '0.01%'   # 1 basis point
)

# Place an order with a builder fee
sdk.exchange.order(
  coin: 'BTC',
  is_buy: true,
  size: '0.01',
  limit_px: '95000',
  builder: { b: '0x250F311Ae04D3CEA03443C76340069eD26C47D7D', f: 10 }  # f=10 means 1bp
)

# Builder works with all order methods
sdk.exchange.bulk_orders(
  orders: [
    { coin: 'BTC', is_buy: true, size: '0.01', limit_px: '94000' },
    { coin: 'BTC', is_buy: false, size: '0.01', limit_px: '96000' }
  ],
  builder: { b: '0x250F311Ae04D3CEA03443C76340069eD26C47D7D', f: 10 }
)

sdk.exchange.market_order(
  coin: 'BTC',
  is_buy: true,
  size: '0.01',
  builder: { b: '0x250F311Ae04D3CEA03443C76340069eD26C47D7D', f: 10 }
)

# Delegate HYPE tokens to a validator (wei = float * 1e8)
sdk.exchange.token_delegate(
  validator: '0x...',
  wei: 100_000_000,  # 1 HYPE
  is_undelegate: false
)

# Undelegate HYPE tokens
sdk.exchange.token_delegate(
  validator: '0x...',
  wei: 10_000_000,   # 0.1 HYPE
  is_undelegate: true
)
```

### HIP-3 DEX Abstraction

HIP-3 DEX abstraction allows automatic collateral transfers when trading on builder-deployed perpetual DEXs.

```ruby
# Enable DEX abstraction for your account (user-signed action)
sdk.exchange.user_dex_abstraction(enabled: true)

# Disable DEX abstraction
sdk.exchange.user_dex_abstraction(enabled: false)

# Enable for a specific user address
sdk.exchange.user_dex_abstraction(enabled: true, user: '0x...')

# Enable DEX abstraction via agent (L1 action, enable only)
# Use this when trading as an agent on behalf of another account
sdk.exchange.agent_enable_dex_abstraction

# Enable DEX abstraction for a vault via agent
sdk.exchange.agent_enable_dex_abstraction(vault_address: '0x...')

# Check current DEX abstraction status
status = sdk.info.user_dex_abstraction(sdk.exchange.address)
# => { "enabled" => true }
```

### HIP-4 Outcome Deployment

For an activated outcome deployer (or a sub-deployer acting for its venue). Responses come back unmodified, so check `status`.

```ruby
venue = 'abc'

# How many outcomes can this venue still deploy?
limits = sdk.info.outcome_deployer_limits(venue)
# => { "nDailyOutcomesRemaining" => 10, "nActiveOutcomesRemaining" => 90 }

# Deploy a standalone Yes/No outcome; keywords are sorted by the SDK
result = sdk.exchange.register_standalone_outcome_from_template(
  venue: venue,
  template_id: 'binaryPrice',
  keyword_to_value: { perp: 'BTC', priceDescription: 'the Hyperliquid BTC perp trade',
                      seconds: 90, threshold: 84_793, time: '20261002-1900' },
  deployer_fee_scale: '1'
)
raise result['response'].to_s unless result['status'] == 'ok'

# Settle it later: name, description and side names must match outcome_meta exactly
outcome = sdk.info.outcome_meta['outcomes'].reverse.find { |o| o['venue'] == venue }
sdk.exchange.settle_outcome(
  venue: venue,
  outcome: outcome['outcome'],
  settle_fraction: '1', # first side (Yes) pays out in full
  name: outcome['name'],
  description: outcome['description'],
  side_names: outcome['sideSpecs'].map { |s| s['name'] }
)
```

## WebSocket

### l2Book (Order Book)

```ruby
sdk = Hyperliquid.new(testnet: true)

sdk.ws.on(:open) { puts 'Connected!' }

sub_id = sdk.ws.subscribe({ type: 'l2Book', coin: 'ETH' }) do |data|
  levels = data['levels']
  best_bid = levels[0]&.first
  best_ask = levels[1]&.first
  puts "ETH  bid=#{best_bid['px']}  ask=#{best_ask['px']}"
end

sleep 10
sdk.ws.unsubscribe(sub_id)
sdk.ws.close
```

### allMids (Mid Prices)

```ruby
sdk = Hyperliquid.new(testnet: true)

sdk.ws.subscribe({ type: 'allMids' }) do |data|
  puts "BTC mid: #{data['mids']['BTC']}"
  puts "ETH mid: #{data['mids']['ETH']}"
end

sleep 10
sdk.ws.close
```

### trades

```ruby
sdk = Hyperliquid.new(testnet: true)

sdk.ws.subscribe({ type: 'trades', coin: 'ETH' }) do |trades|
  trades.each do |t|
    side = t['side'] == 'B' ? 'BUY' : 'SELL'
    puts "#{side} #{t['sz']} ETH @ #{t['px']}"
  end
end

sleep 30
sdk.ws.close
```

### bbo (Best Bid/Offer)

```ruby
sdk = Hyperliquid.new(testnet: true)

sdk.ws.subscribe({ type: 'bbo', coin: 'BTC' }) do |data|
  puts "BTC  bid=#{data['bid']}  ask=#{data['ask']}"
end

sleep 10
sdk.ws.close
```

### candle (Candlesticks)

```ruby
sdk = Hyperliquid.new(testnet: true)

sdk.ws.subscribe({ type: 'candle', coin: 'ETH', interval: '1m' }) do |data|
  puts "ETH 1m candle  o=#{data['o']} h=#{data['h']} l=#{data['l']} c=#{data['c']}"
end

sleep 120
sdk.ws.close
```

### User Channels

```ruby
sdk = Hyperliquid.new(testnet: true, private_key: ENV['HYPERLIQUID_PRIVATE_KEY'])
user = sdk.exchange.address

# Order status changes
sdk.ws.subscribe({ type: 'orderUpdates', user: user }) do |updates|
  updates.each { |u| puts "Order #{u['order']['oid']}: #{u['status']}" }
end

# Fill notifications
sdk.ws.subscribe({ type: 'userFills', user: user }) do |data|
  data['fills'].each { |f| puts "Fill: #{f['sz']} #{f['coin']} @ #{f['px']}" }
end

# Funding payments
sdk.ws.subscribe({ type: 'userFundings', user: user }) do |data|
  puts "Funding update for #{data['user']}"
end

# All user events (fills, liquidations, etc.)
sdk.ws.subscribe({ type: 'userEvents', user: user }) do |data|
  puts "User event received"
end

sleep 60
sdk.ws.close
```

### clearinghouseState (per dex)

```ruby
sdk = Hyperliquid.new(testnet: true)
user = '0x...'

# Main dex (omit dex:) and a HIP-3 dex are separate subscriptions
sdk.ws.subscribe({ type: 'clearinghouseState', user: user }) do |data|
  puts "main dex account value: #{data['clearinghouseState']['marginSummary']['accountValue']}"
end

sdk.ws.subscribe({ type: 'clearinghouseState', user: user, dex: 'xyz' }) do |data|
  puts "#{data['dex']} positions: #{data['clearinghouseState']['assetPositions'].length}"
end

sleep 10
sdk.ws.close
```

### activeAssetCtx (Asset Context)

```ruby
sdk = Hyperliquid.new(testnet: true)

# Perp, HIP-3 ('xyz:XYZ100') or spot ('PURR/USDC', '@107') coins
sdk.ws.subscribe({ type: 'activeAssetCtx', coin: 'BTC' }) do |data|
  puts "#{data['coin']} mark=#{data['ctx']['markPx']} funding=#{data['ctx']['funding']}"
end

sdk.ws.subscribe({ type: 'activeAssetCtx', coin: 'PURR/USDC' }) do |data|
  puts "#{data['coin']} mark=#{data['ctx']['markPx']}"
end

sleep 10
sdk.ws.close
```

### Multiple Subscriptions

```ruby
sdk = Hyperliquid.new(testnet: true)

sdk.ws.subscribe({ type: 'l2Book', coin: 'ETH' }) do |data|
  puts "ETH book: #{data['levels'][0]&.first&.dig('px')}"
end

sdk.ws.subscribe({ type: 'l2Book', coin: 'BTC' }) do |data|
  puts "BTC book: #{data['levels'][0]&.first&.dig('px')}"
end

sdk.ws.subscribe({ type: 'trades', coin: 'ETH' }) do |trades|
  puts "ETH trade: #{trades.first['px']}" if trades.any?
end

sleep 10
sdk.ws.close
```

### Explorer Blocks and Transactions

```ruby
sdk = Hyperliquid.new(testnet: true)

# Separate connection to rpc.hyperliquid(-testnet).xyz/ws; each message is an Array
sdk.ws.subscribe_explorer_block do |blocks|
  blocks.each { |b| puts "block #{b['height']} with #{b['numTxs']} txs" }
end

sdk.ws.subscribe_explorer_txs do |txs|
  txs.each { |tx| puts "#{tx['user']} #{tx.dig('action', 'type')} #{tx['hash']}" }
end

sleep 10
sdk.ws.close
```

### Handling Reconnection

```ruby
sdk = Hyperliquid.new(testnet: true)

sdk.ws.on(:open) { puts 'Connected (or reconnected)!' }
sdk.ws.on(:close) { puts 'Connection lost. Reconnecting...' }

# Subscriptions are automatically replayed on reconnect
sdk.ws.subscribe({ type: 'l2Book', coin: 'ETH' }) do |data|
  puts "ETH: #{data['levels'][0]&.first&.dig('px')}"
end

sleep 300
sdk.ws.close
```

### Client Order IDs (Cloid)

```ruby
# Create from integer (zero-padded to 16 bytes)
cloid = Hyperliquid::Cloid.from_int(42)
# => "0x0000000000000000000000000000002a"

# Create from hex string
cloid = Hyperliquid::Cloid.from_str('0x1234567890abcdef1234567890abcdef')

# Create from UUID
cloid = Hyperliquid::Cloid.from_uuid('550e8400-e29b-41d4-a716-446655440000')

# Generate random
cloid = Hyperliquid::Cloid.random
```
