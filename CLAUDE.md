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
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_all.rb              # all 14
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_automated.rb        # CI-friendly subset
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_08_usd_class_transfer.rb  # single
```

`test_automated.rb` is the unattended runner — same as `test_all.rb` but excludes scripts that require manual testnet preconditions (e.g. `test_09_sub_account_lifecycle` needs $100k traded volume; `test_12_staking` needs HYPE balance). Some included tests (e.g. `test_08`, `test_11`) are also coded to skip-with-warning when known testnet preconditions aren't met, so the suite stays green on a stable wallet.

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
- **WebSocket path**: `WS::Client` manages a persistent WSS connection with subscription tracking, automatic reconnection (exp backoff, 30s cap), 50s ping keepalive, and a bounded message queue (1024, drops oldest on overflow). Subscriptions are identified by a canonical key and dispatched via callbacks on a dedicated thread.

### Signing (Python SDK Parity)

The signing chain in `lib/hyperliquid/signing/` must exactly match the official Python SDK:

1. **Action hash**: `keccak256(msgpack(action) + nonce(8B big-endian) + vault_flag + [vault_addr] + [expires_flag + expires_after])`
2. **Phantom agent**: `{ source: 'a'|'b', connectionId: action_hash }` (`a`=mainnet, `b`=testnet)
3. **EIP-712 signature** over phantom agent with Exchange domain (chain ID 1337)

Any change to signing must maintain parity with the Python SDK or transactions will be rejected by the exchange.

### Numeric Conversion

- **`float_to_wire`** (in Exchange): converts to string with 8-decimal precision, validates rounding tolerance (`1e-12`), normalizes trailing zeros. No scientific notation.
- **Market order pricing** (`_slippage_price`): apply slippage (default 5%) to mid price → round to 5 significant figures → round to `(6 for perp, 8 for spot) - szDecimals` decimal places.
- **Spot vs perp**: assets with index `>= 10_000` are spot (`SPOT_ASSET_THRESHOLD` in Exchange). This affects decimal place calculations.

### HIP-3 (Builder-Deployed Perps)

Many Info methods accept a `dex:` kwarg (e.g. `meta(dex: 'foo')`, `user_state(user, dex: 'foo')`) to query a builder-deployed perp dex rather than the canonical perp market. `Info#perp_dexs` enumerates available dexes; `Info#perp_dex_limits(dex)` returns per-dex risk parameters.

### Testing

- **Unit tests** (`spec/`): RSpec + WebMock. WebMock resets between tests. Monkey-patching disabled. Test files mirror `lib/` structure. No live HTTP calls in unit tests.
- **Integration tests** (`scripts/`): run against testnet with a real private key. Each script is self-contained. Helpers (separators, status dumping, retry-on-oracle-bounce) live in `scripts/test_helpers.rb`.
- **`dump_status` / `check_result` helpers** in `test_helpers.rb` must guard against `result['response']` *itself* being a String for transfer-style actions (`usdClassTransfer`, `approveBuilderFee`) — not just `result['response']['data']`. This was a real bug fixed in 1.1.0; preserve the guards if refactoring those helpers.

### Code Style

RuboCop targets Ruby 3.3. Key relaxations: methods up to 50 lines, no class length limit (Info/Exchange are large by design), no block length limit in specs, no parameter list limit in Exchange. `scripts/`, `test_*.rb`, `local/`, and `vendor/` are excluded from linting.

Predicate methods follow Ruby style (`vip?`, `connected?`, `testnet?`) — not `is_vip` / `is_connected`. RuboCop's `Naming/PredicateName` enforces this.

### CI

GitHub Actions (`.github/workflows/main.yml`): runs `bundle exec rake` (tests + lint) on the Ruby matrix defined in that workflow, for pushes to `main` and on all PRs. The release workflow creates GitHub releases from `CHANGELOG.md` on version tags.

## Release Flow

Releases happen from `main`. Day-to-day work lands on `dev`, then `dev` is merged into `main` and tagged at release time. `CHANGELOG.md` follows Keep-a-Changelog conventions; `lib/hyperliquid/version.rb` is the single source of version truth (gemspec reads it). Tags push automatically trigger the GitHub release workflow.

## Additional Docs

Detailed API reference, examples, WebSocket guide, configuration, and error handling in `docs/` (`API.md`, `EXAMPLES.md`, `WS.md`, `CONFIGURATION.md`, `ERRORS.md`, `DEVELOPMENT.md`).
