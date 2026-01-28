# Development

## Setup

After checking out the repo, run `bin/setup` to install dependencies.

```bash
bin/setup
```

## Running Tests

```bash
# Run all unit tests
rake spec

# Run unit tests and linting together (default)
rake
```

### Integration Testing (Testnet)

Integration tests live in `scripts/` and execute real trades on testnet. No real funds are at risk. Get testnet funds from https://app.hyperliquid-testnet.xyz.

```bash
# Run all integration tests
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_all.rb

# Run a single integration test
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_08_usd_class_transfer.rb
```

The convenience wrapper `ruby test_integration.rb` also runs all tests.

Available test scripts:

| Script | Description |
|--------|-------------|
| `test_01_spot_market_roundtrip.rb` | Buy/sell PURR/USDC at market |
| `test_02_spot_limit_order.rb` | Place and cancel a spot limit order |
| `test_03_perp_market_roundtrip.rb` | Long/close BTC at market |
| `test_04_perp_limit_order.rb` | Place and cancel a perp short |
| `test_05_update_leverage.rb` | Set cross, isolated, and reset leverage |
| `test_06_modify_order.rb` | Place, modify, and cancel an order |
| `test_07_market_close.rb` | Open a position and close via `market_close` |
| `test_08_usd_class_transfer.rb` | Transfer USDC between perp and spot |
| `test_09_sub_account_lifecycle.rb` | Create sub-account, deposit, withdraw |
| `test_10_vault_transfer.rb` | Deposit/withdraw to a vault |

## Linting

```bash
rake rubocop
```

## Interactive Console

```bash
bin/console
```

This opens an interactive prompt with the SDK loaded for experimentation.

## Example Script

```bash
ruby example.rb
```
