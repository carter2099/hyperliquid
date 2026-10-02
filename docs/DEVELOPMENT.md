# Development

## Setup

After checking out the repo, run `bin/setup` to install dependencies.

```bash
bin/setup
```

## Running Tests

```bash
# Default gate (what CI runs): unit tests, RuboCop, and Lint+Security on scripts/ and example.rb
rake

# Unit tests only (random order; reproduce a failure with its printed seed)
rake spec
bundle exec rspec --seed 1234

# Default gate again inside a fresh clone of HEAD with a frozen bundle (run after committing)
rake verify

# Exit 0 and print DOCS_ONLY=yes iff every uncommitted change is docs-only
rake verify:docs_only

# Regenerate the Python-SDK parity fixtures and diff them against spec/fixtures/parity (python3 + network)
rake parity:check

# Run the Ruby 3.3 CI leg locally
RBENV_VERSION=3.3.12 bundle exec rake
```

A change is done when `rake` is green, `rake verify` is green on the commit, and `rake integration` reports `INTEGRATION GATE: PASS`. You can skip `rake integration` only when `rake verify:docs_only` prints `DOCS_ONLY=yes`. Unit and lint failures are never waived. See `CLAUDE.md` → Verification.

### Integration Testing (Testnet)

Integration tests live in `scripts/` and execute real trades on testnet. No real funds are at risk. Get testnet funds from https://app.hyperliquid-testnet.xyz.

```bash
# Run the integration gate (exits 2 when HYPERLIQUID_PRIVATE_KEY is unset)
HYPERLIQUID_PRIVATE_KEY=0x... rake integration

# Same runner without rake
HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/test_all.rb

# Run a single integration test
HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/test_08_usd_class_transfer.rb

# Read-only wallet precondition check (the runner's pre-flight and post-flight)
HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/testnet_wallet_check.rb --assert

# Switch to standard abstraction and rebalance (manual only, never from a runner)
HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/testnet_wallet_check.rb --fix
```

`scripts/test_all.rb` is the only runner.
- **Discovery.** It runs every `scripts/test_[0-9][0-9]_*.rb` it finds by glob, in sorted order, so a new script is picked up automatically. Deliberate exclusions go in its `OPT_OUT` hash, with a reason.
- **Lock.** It holds a `flock` on `tmp/integration.lock`, so only one gate runs at a time.
- **Wallet checks.** It runs `testnet_wallet_check.rb --assert` before the first script and after the last. A violation fails the gate as `precondition` or `leak`.
- **Process.** Each script runs under `ruby -rbundler/setup`, against the locked gems, in its own process group. The private key is redacted from the output.
- **Timeouts.** Each script has a timeout of `HL_SCRIPT_TIMEOUT` seconds (default 300) and is then killed (TIMEOUT). The whole run has a budget of `HL_GATE_BUDGET` seconds (default 2400); scripts left when it runs out are NOT_RUN.

Each script reports its result through its exit code:

| Status | Exit | Meaning | Blocks the gate |
|--------|------|---------|-----------------|
| PASS | 0 | Verified (for a rejection wire check: the pinned rejection arrived) | no |
| FAIL | 1 (or any other unlisted code) | Something is wrong | yes |
| INCONCLUSIVE | 75 | The environment gave no evidence either way | no (yes with `HL_GATE_STRICT=1`) |
| SKIPPED | 77 | The script deliberately tested nothing | no (yes with `HL_GATE_STRICT=1`) |
| GUARDED | 78 | Wallet/testnet state forced a weaker check that still proves signing | no (yes with `HL_GATE_STRICT=1`) |
| TIMEOUT | — | Exceeded `HL_SCRIPT_TIMEOUT` and was killed | yes |
| NOT_RUN | — | `HL_GATE_BUDGET` ran out before the script started | yes |

The runner's last stdout line is always:

```text
INTEGRATION GATE: PASS|FAIL total=N pass=a guarded=b skipped=c inconclusive=d fail=e timeout=f not_run=g
```

A JSON summary with per-script status, exit code, duration and `RESULT` line goes to `HL_GATE_SUMMARY`, default `tmp/integration-summary.json`. Report every INCONCLUSIVE, SKIPPED and GUARDED script by name.

Every script is safe to run unattended in its default mode, and a new script must be too: read-only, or rejection-only with a fail-closed guard. Destructive or locking variants are opt-in CLI args on individual scripts and are never run by the runner:

```bash
ruby -rbundler/setup scripts/test_10_vault.rb deposit|withdraw            # move $10 into / out of the test vault
ruby -rbundler/setup scripts/test_12_staking.rb delegate|undelegate       # 0.1 HYPE, 1-day delegation lockup
ruby -rbundler/setup scripts/test_16_send_to_evm_with_data.rb live        # burns 1 testnet USDC
ruby -rbundler/setup scripts/test_17_create_vault.rb live                 # locks $100 in a new vault
```

Available test scripts (every `scripts/test_NN_*.rb` has exactly one row here; `spec/call_surface_spec.rb` enforces it):

| Script | Description |
|--------|-------------|
| `test_01_spot_market_roundtrip.rb` | Buy/sell PURR/USDC at market |
| `test_02_spot_limit_order.rb` | Place a resting spot limit buy below market and cancel it |
| `test_03_perp_market_roundtrip.rb` | Long/close BTC at market |
| `test_04_perp_limit_order.rb` | Place a resting perp limit short above market and cancel it |
| `test_05_update_leverage.rb` | Set cross, isolated, and reset BTC leverage (requires no BTC position or orders) |
| `test_06_modify_order.rb` | Place, modify, and cancel an order |
| `test_07_market_close.rb` | Open a position and close via `market_close` |
| `test_08_usd_class_transfer.rb` | Transfer USDC perp → spot → perp (GUARDED rejection wire check on a unified wallet) |
| `test_09_sub_account_lifecycle.rb` | Create (or reuse) a sub-account, deposit, withdraw (volume-gate rejection is a wire check) |
| `test_10_vault.rb` | Vault status (`deposit`/`withdraw` opt-in) |
| `test_11_builder_fee.rb` | Approve a builder fee, place an order with a builder, cancel (GUARDED if the builder is ineligible) |
| `test_12_staking.rb` | Staking status and undelegate rejection wire check (`delegate`/`undelegate` opt-in) |
| `test_13_ws_l2_book.rb` | WebSocket `l2Book` subscription (top of book; no key) |
| `test_14_ws_candle.rb` | WebSocket `candle` subscriptions with coin/interval routing checks (INCONCLUSIVE when testnet ETH has no trades) |
| `test_15_explorer.rb` | Explorer RPC `user_details` and `tx_details` (SKIPPED when the wallet has no txs) |
| `test_16_send_to_evm_with_data.rb` | Send USDC to HyperEVM with calldata (default: rejection wire check; `live` sends 1 USDC) |
| `test_17_create_vault.rb` | Create a vault (default: rejection wire check; `live` seeds a real vault with $100) |
| `test_18_user_portfolio_margin.rb` | Portfolio-margin toggle (rejection wire check; restores the original mode) |
| `test_19_spot_user.rb` | Opt out of then back into spot dusting |
| `test_20_explorer_ws.rb` | Explorer WebSocket block stream (3 blocks; INCONCLUSIVE on 1–2) |
| `test_21_ws_channel_parity.rb` | Subscribe to the parity WS channels (read-only) and check each delivers its own user/dex/coin |
| `test_22_outcome_deploy.rb` | HIP-4 outcome deployer actions (structured-rejection wire check) |
| `test_23_ws_fast_asset_ctxs.rb` | Subscribe to the compressed `fastAssetCtxs` channel (read-only) and check the decoded snapshot + deltas |
| `test_24_perp_deploy_wire.rb` | Send `perpDeploy` actions to a nonexistent dex; expect a structured rejection (proves signing) |
| `test_25_hip3_star.rb` | Read `user_star_state`; send a HIP-3* `star` action to a live star dex; expect a structured rejection (proves signing; SKIPPED when no star dex exists) |
| `test_26_spot_deploy_rejection.rb` | spotDeploy structured-rejection wire check on token 0 with a throwaway-key control (no state change) |
| `test_27_validator_actions.rb` | Validator-operator actions (`validator_l1_stream`, `c_signer_*`, `c_validator_change_profile`, `c_validator_unregister`) — rejection-only wire check behind a fail-closed non-validator safety guard; `c_validator_register` is never sent |

Each rejection wire check (`test_09`, `test_12`, `test_16`–`test_18`, `test_22`, `test_24`–`test_27`) also sends the same call with a never-funded throwaway key. It passes only when the wallet's rejection differs from that control's "does not exist" / "must deposit" rejection, which proves the server recovered this wallet as the signer.

## Linting

```bash
rake rubocop           # lib/, spec/, config files
rake rubocop:scripts   # Lint + Security departments only, on scripts/ and example.rb
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
