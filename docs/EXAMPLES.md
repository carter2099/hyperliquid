# Examples

## Info API

### General Info

```ruby
# Retrieve mids for all coins
mids = sdk.info.all_mids
# => { "BTC" => "50000", "ETH" => "3000", ... }

user_address = "0x..."

# Retrieve a user's open orders
orders = sdk.info.open_orders(user_address)
# => [{ "coin" => "BTC", "sz" => "0.1", "px" => "50000", "side" => "A" }]

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

# Activate schedule cancel without specifying a time (server default)
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
