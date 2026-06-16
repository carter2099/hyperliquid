# CLAUDE.md

This file provides guidance to AI coding agents working with this repository. It is the canonical source of truth — keep it in sync as the SDK evolves.

## Overview

Ruby SDK for the Hyperliquid decentralized exchange API. Three API surfaces: **Info** (read-only market data), **Exchange** (authenticated trading), and **WebSocket** (real-time streaming). Built on Faraday for HTTP, the `eth` gem for EIP-712 signing, `msgpack` for action serialization, and `ws_lite` for WebSocket connections.

Version is the single source of truth in `lib/hyperliquid/version.rb`; required Ruby version is in the gemspec.

## Commands

```bash
bin/setup                  # install dependencies
rake                       # run tests + linting (CI default)
rake spec                  # tests only
rake rubocop               # linting only
bundle exec rspec spec/hyperliquid/cloid_spec.rb       # single file
bundle exec rspec spec/hyperliquid/cloid_spec.rb:62    # single test by line
bin/console                # IRB with SDK loaded
ruby example.rb            # example usage script
```

### Integration Tests (Testnet)

Integration scripts live in `scripts/` as standalone files (`test_NN_<name>.rb`). They require a real testnet private key and hit the live testnet API.

```bash
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_all.rb              # all 20
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_automated.rb        # CI-friendly subset (13)
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_08_usd_class_transfer.rb  # single
```

`test_automated.rb` is the unattended runner — same as `test_all.rb` but excludes scripts that require manual testnet preconditions (e.g. `test_09_sub_account_lifecycle` needs $100k traded volume; `test_12_staking` needs HYPE balance; `test_20_explorer_ws` is new and not yet in automated). Some included tests (e.g. `test_08`, `test_11`) are also coded to skip-with-warning when known testnet preconditions aren't met, so the suite stays green on a stable wallet.

`test_integration.rb` at the project root is a thin convenience wrapper.

## Architecture

### Request Flow

All three API surfaces are reached through `Hyperliquid::SDK` (`lib/hyperliquid.rb`):

```
Hyperliquid.new(...)
  ├── sdk.info     → Info       → Client → POST /info     (always available)
  ├── sdk.exchange → Exchange   → Client → POST /exchange  (requires private_key)
  └── sdk.ws       → WS::Client → WSS /ws                 (real-time streaming)
```

- **Info path**: method builds `{ type: 'someType', ... }` body → `Client` POSTs to `/info` → parsed JSON returned.
- **Exchange path**: method builds action payload → `Signer` generates EIP-712 signature over msgpack-encoded action → `Client` POSTs signed payload to `/exchange` → parsed JSON returned.
- **Explorer RPC path** (`tx_details`, `user_details`): a separate base URL (`rpc.hyperliquid.xyz` / `rpc.hyperliquid-testnet.xyz`) with endpoint `/explorer`. `Client` holds a second Faraday connection for this, built lazily on first use; methods opt in via `client.post(EXPLORER_ENDPOINT, body, target: :explorer)`. The SDK wires this up automatically based on `testnet:`. Calling `target: :explorer` on a `Client` constructed without `explorer_base_url:` raises `ConfigurationError`. Don't add a public connection accessor — `target:` is the contract.
- **WebSocket path**: `WS::Client` manages two independent WebSocket connections:
  - **Main API WS** (`wss://api.hyperliquid.xyz/ws`): subscribes to market data channels (`l2Book`, `trades`, `candle`, etc.). Messages arrive as `{channel, data}` envelopes; `compute_identifier` extracts routing keys (e.g. `l2Book:eth`, `candle:btc:1h`). Callbacks are dispatched via a bounded queue (1024, drops on overflow) on a dedicated thread.
  - **Explorer WS** (`wss://rpc.hyperliquid.xyz/ws`): subscribes to block/transaction streams (`explorerBlock`, `explorerTxs`). Messages arrive as **bare arrays** (no envelope), so `identify_explorer_array` duck-types by field presence (`blockTime`/`height` for blocks, `action`/`hash` for txs). Uses a separate queue, dispatch thread, and subscription ID namespace to avoid cross-contamination with main-API WS. Both connections share the same 50s ping keepalive, automatic reconnection (exp backoff, 30s cap), and lifecycle hooks (`on(:open)`, `on(:close)`, `on(:error)`).

### Signing (Python SDK Parity)

The signing chain in `lib/hyperliquid/signing/` must exactly match the official Python SDK:

1. **Action hash**: `keccak256(msgpack(action) + nonce(8B big-endian) + vault_flag + [vault_addr] + [expires_flag + expires_after])`
2. **Phantom agent**: `{ source: 'a'|'b', connectionId: action_hash }` (`a`=mainnet, `b`=testnet)
3. **EIP-712 signature** over phantom agent with Exchange domain (chain ID 1337)

Any change to signing must maintain parity with the Python SDK or transactions will be rejected by the exchange.

User-signed actions (`usd_send`, `withdraw_from_bridge`, `send_to_evm_with_data`, etc.) use direct EIP-712 typed-data signing with the `HyperliquidSignTransaction` domain (chain ID 421614) — not the phantom-agent flow. Each has a typed-data spec in `Signing::EIP712`. The `eth` gem's typed-data signer handles primitive types (`string`, `uint*`, `address`, `bool`) and dynamic `bytes` correctly — `send_to_evm_with_data` was the first to use `bytes`, and its spec includes a fixture-based signature parity test against `eth_account` to lock that in. When adding new user-signed actions with non-string types, add a similar fixture to catch eth-gem regressions.

Multi-sig actions (`Exchange#multi_sig`) wrap any inner action with N co-signer signatures. The submitter's outer signature uses `MULTI_SIG_TYPES` over `{hyperliquidChain, multiSigActionHash, nonce}`; the `multiSigActionHash` is `Signer.compute_action_hash` of the multi-sig envelope (with `:type` stripped). Co-signer signing is exposed via `Signing::MultiSig.sign_as_co_signer_l1` (for L1 inner actions — signs `[multi_sig_user, outer_signer, action]` via phantom-agent) and `Signing::MultiSig.sign_as_co_signer_user_signed` (enriches the inner action's typed-data spec with `payloadMultiSigUser`+`outerSigner` address fields). Both mirror the Python SDK byte-for-byte; specs include fixture-based parity tests captured against `eth_account`+`msgpack`. Co-signature *collection* is the caller's responsibility — the SDK does not coordinate signing rooms.

### Numeric Conversion

- **`float_to_wire`** (in Exchange): converts to string with 8-decimal precision, validates rounding tolerance (`1e-12`), normalizes trailing zeros. No scientific notation.
- **Market order pricing** (`_slippage_price`): apply slippage (default 5%) to mid price → round to 5 significant figures → round to `(6 for perp, 8 for spot) - szDecimals` decimal places.
- **Spot vs perp**: assets with index `>= 10_000` are spot (`SPOT_ASSET_THRESHOLD` in Exchange). This affects decimal place calculations.

### HIP-3 (Builder-Deployed Perps)

Many Info methods accept a `dex:` kwarg (e.g. `meta(dex: 'foo')`, `user_state(user, dex: 'foo')`) to query a builder-deployed perp dex rather than the canonical perp market. `Info#perp_dexs` enumerates available dexes; `Info#perp_dex_limits(dex)` returns per-dex risk parameters.

### Testing

- **Unit tests** (`spec/`): RSpec + WebMock. WebMock resets between tests. Monkey-patching disabled. Test files mirror `lib/` structure. No live HTTP calls in unit tests. The WS client spec (`spec/hyperliquid/ws/client_spec.rb`) includes comprehensive isolation tests verifying that explorer WS messages never route to main-API callbacks and vice versa — this is critical because the two transports share the same `WS::Client` class.
- **Integration tests** (`scripts/`): run against testnet with a real private key. Each script is self-contained. Helpers (separators, status dumping, retry-on-oracle-bounce) live in `scripts/test_helpers.rb`. `test_20_explorer_ws.rb` subscribes to `explorerBlock` on testnet and collects 3 block events (60s timeout) to verify the explorer WS transport works end-to-end.
- **`dump_status` / `check_result` helpers** in `test_helpers.rb` must guard against `result['response']` *itself* being a String for transfer-style actions (`usdClassTransfer`, `approveBuilderFee`) — not just `result['response']['data']`. This was a real bug fixed in 1.1.0; preserve the guards if refactoring those helpers.

### Code Style

RuboCop targets Ruby 3.3. Key relaxations: methods up to 50 lines, no class length limit (Info/Exchange are large by design), no block length limit in specs, no parameter list limit in Exchange, empty blocks allowed in specs (intentional no-op callbacks). `scripts/`, `test_*.rb`, `local/`, and `vendor/` are excluded from linting. The WS client's `initialize` method was refactored to extract `init_main_ws_state` and `init_explorer_ws_state` helpers to reduce ABC size (33 assignments across two transports).

Predicate methods follow Ruby style (`vip?`, `connected?`, `testnet?`) — not `is_vip` / `is_connected`. RuboCop's `Naming/PredicateName` enforces this.

### CI

GitHub Actions (`.github/workflows/main.yml`): runs `bundle exec rake` (tests + lint) on the Ruby matrix defined in that workflow, for pushes to `main` and on all PRs. The release workflow creates GitHub releases from `CHANGELOG.md` on version tags.

## Release Flow

Releases happen from `main`. Day-to-day work lands on `dev`, then `dev` is merged into `main` and tagged at release time. `CHANGELOG.md` follows Keep-a-Changelog conventions; `lib/hyperliquid/version.rb` is the single source of version truth (gemspec reads it). Tags push automatically trigger the GitHub release workflow.

## Additional Docs

Detailed API reference, examples, WebSocket guide, configuration, and error handling in `docs/` (`API.md`, `EXAMPLES.md`, `WS.md`, `CONFIGURATION.md`, `ERRORS.md`, `DEVELOPMENT.md`).
