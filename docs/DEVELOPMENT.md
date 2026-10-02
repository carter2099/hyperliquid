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

# Scheduled-run entry point (loads test_all.rb; same 20 scripts)
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_automated.rb

# Wallet preconditions report; --fix switches to standard abstraction and rebalances (never from a runner)
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/testnet_wallet_check.rb [--fix]
```

The convenience wrapper `ruby test_integration.rb` also runs all tests.

Every script is safe to run unattended in its default mode. Destructive or locking variants are opt-in CLI args on individual scripts and are never run by a runner:

```bash
ruby scripts/test_10_vault.rb deposit|withdraw            # move $10 into / out of the test vault
ruby scripts/test_12_staking.rb delegate|undelegate       # 0.1 HYPE, 1-day delegation lockup
ruby scripts/test_16_send_to_evm_with_data.rb live        # burns 1 testnet USDC
ruby scripts/test_17_create_vault.rb live                 # locks $100 in a new vault
```

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
| `test_09_sub_account_lifecycle.rb` | Create (or reuse) a sub-account, deposit, withdraw (volume-gate rejection is a wire check) |
| `test_10_vault.rb` | Vault status, deposit and withdraw |
| `test_11_builder_fee.rb` | Approve a builder fee, place an order with a builder, cancel |
| `test_12_staking.rb` | Staking status and undelegate rejection wire check (`delegate`/`undelegate` opt-in) |
| `test_13_ws_l2_book.rb` | WebSocket `l2Book` subscription (top of book) |
| `test_14_ws_candle.rb` | WebSocket `candle` subscription (OHLCV) |
| `test_15_explorer.rb` | Explorer RPC `user_details` and `tx_details` |
| `test_16_send_to_evm_with_data.rb` | Send USDC to HyperEVM with calldata (default: rejection wire check; `live` sends 1 USDC) |
| `test_17_create_vault.rb` | Create a vault (default: rejection wire check; `live` seeds a real vault with $100) |
| `test_18_user_portfolio_margin.rb` | Enable then disable portfolio margin |
| `test_19_spot_user.rb` | Opt out of then back into spot dusting |
| `test_20_explorer_ws.rb` | Explorer WebSocket block stream |
| `test_22_outcome_deploy.rb` | HIP-4 outcome deployer actions (structured-rejection wire check) |
| `test_24_perp_deploy_wire.rb` | Send `perpDeploy` actions to a nonexistent dex; expect a structured rejection (proves signing) |
| `test_26_spot_deploy_rejection.rb` | spotDeploy structured-rejection wire check on token 0 with a throwaway-key control (no state change) |
| `test_27_validator_actions.rb` | Validator-operator actions (`validator_l1_stream`, `c_signer_*`, `c_validator_change_profile`, `c_validator_unregister`) — rejection-only wire check behind a fail-closed non-validator safety guard; `c_validator_register` is never sent |

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
