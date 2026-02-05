# AGENTS.md

This file provides guidance to AI coding agents working with this repository.

## Overview

Ruby SDK (v1.0.1) for the Hyperliquid decentralized exchange API. Three API surfaces: **Info** (read-only market data), **Exchange** (authenticated trading), and **WebSocket** (real-time streaming). Built on Faraday for HTTP, the `eth` gem for EIP-712 signing, `msgpack` for action serialization, and `ws_lite` for WebSocket connections.

**Ruby**: >= 3.3.0 (CI tests 3.3, 3.4)

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
```bash
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_all.rb              # all
HYPERLIQUID_PRIVATE_KEY=0x... ruby scripts/test_08_usd_class_transfer.rb  # single
```
Integration tests live in `scripts/` as standalone files. `test_integration.rb` at project root is a convenience wrapper.

## Architecture

### Request Flow

The SDK has three parallel API surfaces, all routed through `Hyperliquid::SDK` (`lib/hyperliquid.rb`):

```
Hyperliquid.new(...)
  ├── sdk.info     → Info       → Client → POST /info     (always available)
  ├── sdk.exchange → Exchange   → Client → POST /exchange  (requires private_key)
  └── sdk.ws       → WS::Client → WSS /ws                 (real-time streaming)
```

**Info path**: Method builds `{ type: 'someType' }` body → `Client` POSTs to `/info` → parsed JSON returned.

**Exchange path**: Method builds action payload → `Signer` generates EIP-712 signature over msgpack-encoded action → `Client` POSTs signed payload to `/exchange` → parsed JSON returned.

**WebSocket path**: `WS::Client` manages a persistent WSS connection with subscription tracking, automatic reconnection, ping keepalive (50s), and a bounded message queue (1024 max, drops oldest on overflow). Subscriptions are identified by a canonical key and dispatched via callbacks on a dedicated thread.

### Signing (Python SDK Parity)

The signing chain in `lib/hyperliquid/signing/` must exactly match the official Python SDK:

1. **Action hash**: `keccak256(msgpack(action) + nonce(8B big-endian) + vault_flag + [vault_addr] + [expires_flag + expires_after])`
2. **Phantom agent**: `{ source: 'a'|'b', connectionId: action_hash }` (a=mainnet, b=testnet)
3. **EIP-712 signature** over phantom agent with Exchange domain (chain ID 1337)

Any change to signing must maintain parity with the Python SDK or transactions will be rejected.

### Numeric Conversion

**float_to_wire** (in Exchange): Converts to string with 8 decimal precision, validates rounding tolerance (1e-12), normalizes trailing zeros. No scientific notation.

**Market order pricing** (_slippage_price): Apply slippage (default 5%) to mid price → round to 5 significant figures → round to `(6 for perp, 8 for spot) - szDecimals` decimal places.

**Spot vs Perp**: Assets with index >= 10,000 are spot (`SPOT_ASSET_THRESHOLD` in Exchange). This affects decimal place calculations.

### Testing

- **Unit tests** (`spec/`): RSpec + WebMock. WebMock resets between tests. Monkey-patching disabled. Test files mirror `lib/` structure.
- **Integration tests** (`scripts/`): Run against testnet with a real private key. Each script is self-contained.

### Code Style

RuboCop targets Ruby 3.3. Key relaxations: methods up to 50 lines, no class length limit (Info/Exchange are large by design), no block length limit in specs, no parameter list limit in Exchange. `scripts/`, `test_*.rb`, `local/`, and `vendor/` are excluded from linting.

### CI

GitHub Actions (`.github/workflows/main.yml`): runs `bundle exec rake` (tests + lint) on Ruby 3.3 and 3.4 for pushes to main and all PRs. Release workflow creates GitHub releases from CHANGELOG.md on version tags.

## Additional Docs

Detailed API reference, examples, WebSocket guide, configuration, and error handling in `docs/`.
