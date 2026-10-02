# CLAUDE.md

This file provides guidance to AI coding agents working with this repository. It is the canonical source of truth — keep it in sync as the SDK evolves.

## Overview

Ruby SDK for the Hyperliquid decentralized exchange API. Three API surfaces: **Info** (read-only market data), **Exchange** (authenticated trading), and **WebSocket** (real-time streaming). Built on Faraday for HTTP, the `eth` gem for EIP-712 signing, `msgpack` for action serialization, and `ws_lite` for WebSocket connections.

Version is the single source of truth in `lib/hyperliquid/version.rb`; required Ruby version is in the gemspec.

## Commands

```bash
bin/setup                  # install dependencies
rake                       # default gate (CI runs this): spec + rubocop + rubocop:scripts
rake spec                  # tests only (random order; rerun a failure with `bundle exec rspec --seed N`)
rake rubocop               # lint lib/, spec/, and config files
rake rubocop:scripts       # Lint + Security cops only, on scripts/ and example.rb
rake verify                # default, then verify:head: `bundle exec rake` in a fresh `git clone --local` of HEAD with BUNDLE_FROZEN=true
rake verify:docs_only      # prints DOCS_ONLY=yes (exit 0) iff every uncommitted change is docs-only, else DOCS_ONLY=no path=<first offender> (exit 1)
rake integration           # live testnet gate (scripts/test_all.rb); exits 2 when HYPERLIQUID_PRIVATE_KEY is unset
rake parity:check          # regenerate the Python-SDK parity fixtures into a temp dir and diff them (needs python3 + network; not in default)
RBENV_VERSION=3.3.12 bundle exec rake   # reproduce the Ruby 3.3 CI leg locally
bundle exec rspec spec/hyperliquid/cloid_spec.rb       # single file
bundle exec rspec spec/hyperliquid/cloid_spec.rb:62    # single test by line
bin/console                # IRB with SDK loaded
ruby example.rb            # example usage script
```

`rake build` builds the gem into `pkg/`. `rake release` (and `release:*`) is disabled on purpose: releases go through `/hyperliquid-release` (gem push first, tag after).

`rake verify:docs_only` looks at every changed path, tracked and untracked. It treats as docs-only: `docs/`, `README.md`, `CLAUDE.md`, `example.rb` and `spec/docs_coverage_spec.rb`, plus any `lib/**/*.rb` or `scripts/**/*.rb` file tracked in HEAD whose Ripper token stream is unchanged once comments and whitespace are dropped, and whose magic comments are also unchanged. A new file, a deleted file or any other path makes the change not docs-only.

### Integration Tests (Testnet)

Integration scripts live in `scripts/` as standalone files (`test_NN_<name>.rb`). They need a real testnet private key and hit the live testnet API.

```bash
HYPERLIQUID_PRIVATE_KEY=0x... rake integration                                              # the gate: every script + wallet pre/post-flight
HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/test_all.rb                      # same runner without rake
HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/test_08_usd_class_transfer.rb    # single script
HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/testnet_wallet_check.rb --assert # read-only precondition check (exit 1 + one line per violation)
HYPERLIQUID_PRIVATE_KEY=0x... ruby -rbundler/setup scripts/testnet_wallet_check.rb --fix    # switch to standard abstraction + rebalance (manual only, never from a runner)
```

**Runner.** `scripts/test_all.rb` is the only runner. `scripts/test_automated.rb` and the root `test_integration.rb` no longer exist. The runner works like this:
- **Discovery.** It discovers `scripts/test_[0-9][0-9]_*.rb` by glob, sorted (27 scripts today), so a new script is picked up automatically. Deliberate exclusions go in its `OPT_OUT` hash (`'test_NN_x.rb' => 'reason'`) and are printed when present.
- **Lock.** It holds an exclusive `flock` on `tmp/integration.lock`, so a second concurrent run exits 1 at once.
- **Pre-flight.** Before any script it runs `testnet_wallet_check.rb --assert`. If that fails, nothing runs and the gate is FAIL (`precondition`).
- **Post-flight.** The same assert runs after the last script. Any violation (a leaked order or position, or a changed balance or mode) makes the gate FAIL (`leak`).
- **Process.** Each script runs as `ruby -rbundler/setup <script>` in its own process group. Output is streamed. ANSI codes are stripped when stdout is not a TTY. The private key (with and without `0x`) is replaced by `[REDACTED]`.
- **Timeouts.** Each script gets `HL_SCRIPT_TIMEOUT` seconds (default 300). On timeout the runner sends TERM to the group, waits 5 s, then KILL, and the status is TIMEOUT. The whole run gets `HL_GATE_BUDGET` seconds (default 2400). Scripts still waiting when the budget runs out are NOT_RUN.

**Statuses.** A script's exit code sets its status. Any other non-zero code counts as FAIL:

| Status | Exit | Meaning |
|---|---|---|
| PASS | 0 | Verified, including a script whose default mode is a rejection wire check and that got its pinned rejection |
| FAIL | 1 | Anything wrong. A missing mid price is a FAIL, never a skip |
| INCONCLUSIVE | 75 | The environment gave no evidence either way (e.g. no testnet ETH trades in the window) |
| SKIPPED | 77 | The script deliberately tested nothing (e.g. no explorer txs to look up) |
| GUARDED | 78 | The wallet or testnet state made the happy path impossible, so a weaker check that still proves the signature ran instead (e.g. `test_08` on a unified wallet) |

**Gate output.** The last stdout line is always exactly `INTEGRATION GATE: PASS|FAIL total=N pass=a guarded=b skipped=c inconclusive=d fail=e timeout=f not_run=g`. A JSON summary goes to `HL_GATE_SUMMARY`, default `tmp/integration-summary.json`. It holds `gate`, `started_at`, `finished_at`, `preflight`, `postflight`, and per script `name`, `status`, `exit_code`, `seconds`, `result_line`.

**Gate exit code.** The runner exits 0 only when fail + timeout + not_run is 0 and both pre-flight and post-flight passed. With `HL_GATE_STRICT=1` (the release flow sets it), any SKIPPED, INCONCLUSIVE or GUARDED also makes the gate FAIL.

**Script contract.** Every script uses the helpers in `scripts/test_helpers.rb` and ends through one of them:
- `test_passed(name)` prints `RESULT PASS <name>`. It prints `RESULT FAIL` instead if `fail!` was called earlier.
- `fail!(msg)` records a failure and lets the script continue.
- `finish_inconclusive`, `finish_skipped` and `finish_guarded(name, reason)` end the script with that status.
- `build_sdk` and the key-less `build_public_sdk` abort unless the base URL is testnet.
- `throwaway_sdk` signs with a fresh, never-funded key. `assert_signer_dependent(label, agent_text, control_text)` uses it to prove that a rejection depended on the recovered signer.
- `require_flat!(sdk, coin)` fails when a position or open order exists on that coin.

**Adding a script.** A new script's default mode must be automated-safe: read-only, or rejection-only with a fail-closed guard. It must also restore any state it changes in an `ensure`.

**Opt-in variants.** Destructive or locking variants are per-script CLI arguments and never run from the runner:
- `test_10_vault.rb deposit|withdraw`
- `test_12_staking.rb delegate|undelegate`
- `test_16_send_to_evm_with_data.rb live` burns 1 USDC.
- `test_17_create_vault.rb live` locks $100 in a new vault.

**Rejection wire checks.** Several scripts check the wire through a structured rejection: `test_09` volume gate, `test_12` undelegate, `test_16`, `test_17`, `test_18` portfolio-margin threshold, `test_22`, `test_24`, `test_25`, `test_26` and `test_27`.
- The server can only produce a balance, volume or mode-class `err` after it has recovered the signer to this wallet. That is why such a rejection proves signing end to end.
- Each of these scripts also sends the same call with a throwaway key as a control.

## Verification

This is the definition of done for any change, whether made by a human or an agent:

1. **`rake` is green.** Unit, lint and script-lint failures are never waived, and never labelled flaky or unrelated without evidence. A red baseline means the only job is to fix it.
2. **`rake verify` is green after committing.** It reruns the gate in a fresh clone of HEAD with a frozen bundle. That catches files never `git add`ed and lockfile drift.
3. **`rake integration` ends with `INTEGRATION GATE: PASS`.** The only exception is when `rake verify:docs_only` prints `DOCS_ONLY=yes`. In that case record the line and skip integration.
   - FAIL, TIMEOUT and NOT_RUN block the change. So do a failed pre-flight or post-flight.
   - INCONCLUSIVE, SKIPPED and GUARDED do not block. Report each one by script name with its `RESULT` line. Never fold them into a pass count.
   - Take the numbers you report from the gate line and `tmp/integration-summary.json`. Never retype them.
4. **New `Exchange` methods.** The signature verifier in `spec/support/` covers every request a spec posts to `/exchange`, with no extra work. When the Python SDK has the action, also add a Python-parity vector, generated by `tools/parity/` into `spec/fixtures/parity/`.
5. **New public methods** need an entry in `docs/API.md`, which `spec/docs_coverage_spec.rb` enforces. They also need a spec that calls them, which the method-coverage gate enforces.
6. **New integration scripts** follow the result contract above and are automated-safe in their default mode. They also need a row in `docs/DEVELOPMENT.md`'s script table, which `spec/call_surface_spec.rb` enforces.

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
  - **Main API WS** (`wss://api.hyperliquid.xyz/ws`): subscribes to market data channels (`l2Book`, `trades`, `candle`, etc.). Messages arrive as `{channel, data}` envelopes; `compute_identifier` extracts routing keys (e.g. `l2Book:eth`, `candle:btc:1h`). Callbacks are dispatched via a bounded queue (1024, drops on overflow) on a dedicated thread. Routing identifiers come from the `ROUTING_KEYS` table (`[type, *fields].join(':')`); server channels that differ from the subscription type go through `CHANNEL_ALIASES` (`user`→`userEvents`, `activeSpotAssetCtx`→`activeAssetCtx`); channels whose payload omits a subscription field are guarded by `EXCLUSIVE_FIELDS` (raise on conflicting subscription). `fastAssetCtxs` is the one compressed channel: its `data` is base64 + raw DEFLATE (RFC 1951) JSON, decoded in `handle_message` via `decode_compressed_payload` (stdlib `zlib` + `unpack1('m0')`, no `base64` gem) before routing; decode errors warn and drop the frame.
  - **Explorer WS** (`wss://rpc.hyperliquid.xyz/ws`): subscribes to block/transaction streams (`explorerBlock`, `explorerTxs`). Messages arrive as **bare arrays** (no envelope), so `identify_explorer_array` duck-types by field presence (`blockTime`/`height` for blocks, `action`/`hash` for txs). Uses a separate queue and dispatch thread; subscription ids come from the same counter as main-API subscriptions, so `unsubscribe(id)` is unambiguous. Both connections use the same 50s ping keepalive and automatic reconnection (exp backoff, 30s cap). Lifecycle hooks (`on(:open)`, `on(:close)`, `on(:error)`) fire for the main-API connection only; explorer errors are printed as warnings.

### Signing (Python SDK Parity)

The signing chain in `lib/hyperliquid/signing/` must exactly match the official Python SDK:

1. **Action hash**: `keccak256(msgpack(action) + nonce(8B big-endian) + vault_flag + [vault_addr] + [expires_flag + expires_after])`
2. **Phantom agent**: `{ source: 'a'|'b', connectionId: action_hash }` (`a`=mainnet, `b`=testnet)
3. **EIP-712 signature** over phantom agent with Exchange domain (chain ID 1337)

Any change to signing must maintain parity with the Python SDK or transactions will be rejected by the exchange. Explorer `userDetails` echoes submitted action JSON verbatim — use it to confirm live wire shapes of docs-only actions. Caveat: spot-deploy aligned-quote txs echo as `[token]`, yet `/exchange` rejected both `[token]` and the documented `{token}` with HTTP 422 "Failed to deserialize" (testnet, 2026-10-02), so those two variants are not shipped.

HIP-4 deployer actions (`activateOutcomeDeployer` enum and `outcomeDeploy {type, venue, operation}`) are L1; key order is pinned by Python-SDK parity fixtures; `keywordToValue` pairs are sorted by the SDK, `setSubDeployers`/named-outcome lists keep caller order.

User-signed actions (`usd_send`, `withdraw_from_bridge`, `send_to_evm_with_data`, etc.) use direct EIP-712 typed-data signing with the `HyperliquidSignTransaction` domain (chain ID 421614) — not the phantom-agent flow. Each has a typed-data spec in `Signing::EIP712`. The `eth` gem's typed-data signer handles primitive types (`string`, `uint*`, `address`, `bool`) and dynamic `bytes` correctly — `send_to_evm_with_data` was the first to use `bytes`, and its spec includes a fixture-based signature parity test against `eth_account` to lock that in. When adding new user-signed actions with non-string types, add a similar fixture to catch eth-gem regressions.

Multi-sig actions (`Exchange#multi_sig`) wrap any inner action with N co-signer signatures. The submitter's outer signature uses `MULTI_SIG_TYPES` over `{hyperliquidChain, multiSigActionHash, nonce}`; the `multiSigActionHash` is `Signer.compute_action_hash` of the multi-sig envelope (with `:type` stripped). Co-signer signing is exposed via `Signing::MultiSig.sign_as_co_signer_l1` (for L1 inner actions — signs `[multi_sig_user, outer_signer, action]` via phantom-agent) and `Signing::MultiSig.sign_as_co_signer_user_signed` (enriches the inner action's typed-data spec with `payloadMultiSigUser`+`outerSigner` address fields). Both mirror the Python SDK byte-for-byte; specs include fixture-based parity tests captured against `eth_account`+`msgpack`. Co-signature *collection* is the caller's responsibility — the SDK does not coordinate signing rooms.

Validator-operator actions (`c_signer_*`, `c_validator_*`, `validator_l1_stream`) are L1 actions. `CValidatorAction` uses protocol-literal snake_case wire keys (`node_ip: { Ip: … }`, `commission_bps`, `delegations_disabled` vs `disable_delegations`, `initial_wei`) and sends every nullable `changeProfile` field as JSON null rather than omitting it — key order, null-vs-omit, and int types are part of the action hash; parity fixtures in `exchange_spec.rb` lock them.

### Numeric Conversion

- **`float_to_wire`** (in Exchange): converts to string with 8-decimal precision, validates rounding tolerance (`1e-12`), normalizes trailing zeros. No scientific notation.
- **`wei_to_wire`** (Exchange, private): integer-wei string fields (spot-deploy `maxSupply`, genesis amounts): Integer→`to_s`, String verbatim, anything else (notably Float) raises. Deployer-action integer fields are coerced with `Integer()` (raises on garbage; Floats truncate) because a stringly-typed int changes the msgpack hash.
- **Market order pricing** (`_slippage_price`): apply slippage (default 5%) to mid price → round to 5 significant figures → round to `(6 for perp, 8 for spot) - szDecimals` decimal places.
- **Spot vs perp**: assets with index `>= 10_000` are spot (`SPOT_ASSET_THRESHOLD` in Exchange). This affects decimal place calculations.

### HIP-3 (Builder-Deployed Perps)

Many Info methods accept a `dex:` kwarg (e.g. `meta(dex: 'foo')`, `user_state(user, dex: 'foo')`) to query a builder-deployed perp dex rather than the canonical perp market. `Info#perp_dexs` enumerates available dexes; `Info#perp_dex_limits(dex)` returns per-dex risk parameters.

`Exchange#perp_deploy_*` wraps the `perpDeploy` L1 action (one variant key per method) via the private `perp_deploy_action(variant_key, payload)`; none take `vault_address:`, and `expires_after` propagates. Tuple-list variants take a `{ coin => value }` Hash that `sorted_coin_pairs` turns into `[coin, value]` pairs sorted by coin (the server requires sorted tuples). `perp_deploy_decimal` passes Strings verbatim (Python parity) and normalizes Numerics via `float_to_wire`. Nullable keys (`maxGas`, `schema`, `oracleUpdater`, …) are always sent as null, never omitted — msgpack hashes nil and absence differently. Key order is verified against live explorer echoes: explorer `userDetails` returns accepted txs, so each echoed key order is known to produce a valid signature, making it a reusable oracle for L1 key order (capped at the 300 most recent txs per user). `setFeeScale`/`setGrowthModes` are intentionally omitted (superseded by `setDeployerFees`). `scripts/test_24_perp_deploy_wire.rb` checks the wire live by sending actions to a nonexistent dex and requiring a structured server rejection (which proves signer recovery).

HIP-3\* (testnet-only) venues add `Exchange#star_*` deployer/proxy operations (L1 `perpDeploy` action, `star` variant — Python-parity fixtures in `exchange_spec.rb`) and `Info#user_star_state`, whose `dexToState` is an Array of `[dex, state]` pairs despite the docs showing an object.

### Testing

- **Unit tests** (`spec/`): RSpec + WebMock, with no live HTTP (`WebMock.disable_net_connect!`). Test files mirror the `lib/` structure. `spec/spec_helper.rb` loads every `spec/support/**/*.rb`. Settings:
  - Examples run in random order. The seed is printed; reproduce a failure with `bundle exec rspec --seed N`.
  - Partial doubles are verified, deprecations raise, and monkey-patching is disabled.
  - Committed focus tags (`fit`, `fdescribe`, `fcontext`, `focus: true`) fail `spec/no_focus_spec.rb`.
  - Threaded WS specs synchronise with `wait_until` (`spec/support/wait_until.rb`), never with `sleep`.
- **Signature verifier** (`spec/support/exchange_signature_verifier.rb`): after every example it recovers the signer of each request posted to `/exchange` from the posted body, and fails unless the signer is the example's key.
  - L1 actions: action hash plus phantom agent. User-signed actions: the `Signing::EIP712` typed data.
  - New `Exchange` methods are covered with no extra code.
  - Only specs that deliberately post a bad signature may opt out, with `skip_signature_verification: '<reason>'`.
- **Method-coverage gate** (`spec/support/method_coverage.rb`): `Coverage` starts before `require 'hyperliquid'`. A full-suite run fails if any public SDK method defined under `lib/` was never executed by a spec. It covers `Info`, `Exchange`, `WS::Client`, `Cloid`, `Signer`, `MultiSig`, `SDK` and `Client`. Filtered runs (single file or line) skip the check.
- **Static specs:**
  - `spec/call_surface_spec.rb` parses every `sdk.info` / `sdk.exchange` / `sdk.ws` call with Prism and checks it against the real method signature: method exists and is public, keywords accepted, required keywords present, positional arity. It scans `scripts/`, the commented block in `example.rb`, and the ruby fences in `README.md` and `docs/*.md`. It also requires exactly one `docs/DEVELOPMENT.md` table row per integration script.
  - `spec/package_spec.rb` checks the gemspec file list: every tracked `lib/**/*.rb` is packaged, nothing from `scripts/`, `spec/`, `tools/` and the like is, and every `require_relative` target resolves.
  - `spec/warnings_spec.rb` loads the SDK under `ruby -w` and fails on any warning that points into `lib/`.
- **Python-SDK parity:**
  - Machine-readable fixtures live in `spec/fixtures/parity/`. Examples: L1 signing vectors, EIP-712 user-signed vectors for every `Signing::EIP712` table, L1 wire goldens, and slippage/`float_to_wire` numerics.
  - The pinned Python SDK (`tools/parity/requirements.txt`, `hyperliquid-python-sdk==0.24.0`) generates them through `tools/parity/capture_*.py` and `tools/parity/regenerate.sh OUTDIR`.
  - Specs read the fixtures; never hand-edit them. Regenerate instead; `rake parity:check` proves the committed files match.
- **WebSocket:**
  - `spec/hyperliquid/ws/client_spec.rb` includes isolation tests proving that explorer WS messages never route to main-API callbacks and vice versa. This matters because the two transports share one `WS::Client` class.
  - `spec/hyperliquid/ws/loopback_spec.rb` runs the real `ws_lite` client against a local `TCPServer` WebSocket on 127.0.0.1. It covers exact subscribe frames, inbound dispatch, and reconnect with re-subscribe.
- **Integration tests** (`scripts/`) run against testnet with a real private key, through the runner and result contract described under Commands. Each script is self-contained, and helpers live in `scripts/test_helpers.rb`. Script-specific behaviour:
  - `test_08_usd_class_transfer.rb` reports GUARDED on a unified wallet. `test_11_builder_fee.rb` checks its third-party builder's eligibility via Info first and reports GUARDED if that builder has become ineligible.
  - `test_14_ws_candle.rb` runs three concurrent candle subscriptions (ETH/1m, ETH/15m, BTC/1m) and checks each message's coin and interval routing. It needs 2 ETH/1m and 1 ETH/15m updates within 120s. On timeout it calls `Info#recent_trades('ETH')`: ETH trades in the window but no candle updates is a FAIL; no testnet ETH trades at all is INCONCLUSIVE.
  - `test_20_explorer_ws.rb` subscribes to `explorerBlock` on testnet and collects 3 block events within 60s, to verify the explorer WS transport end to end. 0 blocks is a FAIL and 1–2 blocks is INCONCLUSIVE.
  - `test_21_ws_channel_parity.rb` (read-only, no key) subscribes to the parity WS channels on testnet. It fails on a missing snapshot, or on a message whose user, dex or coin does not match its subscription. It also checks the local `orderUpdates` exclusivity guard.
  - `test_23_ws_fast_asset_ctxs.rb` (read-only, no key) collects 3 decoded `fastAssetCtxs` frames (a snapshot and 2 deltas) and checks their coin => `markPx`/`midPx` shape.
- **`dump_status` / `check_result` helpers** in `test_helpers.rb` must guard against `result['response']` *itself* being a String for transfer-style actions (`usdClassTransfer`, `approveBuilderFee`) — not just `result['response']['data']`. This was a real bug fixed in 1.1.0; preserve the guards if refactoring those helpers.

### Code Style

RuboCop targets Ruby 3.3. Key relaxations:
- methods up to 50 lines;
- no class length limit (Info and Exchange are large by design);
- no block length limit in specs;
- no parameter list limit in Exchange;
- empty blocks allowed in specs (intentional no-op callbacks).

`Metrics/CyclomaticComplexity` and `Metrics/PerceivedComplexity` apply at their defaults (7 and 8) everywhere, including `exchange.rb` and `ws/client.rb`. Methods that already exceeded them are wrapped individually in `# rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity` … `# rubocop:enable …`. A new method must stay under the defaults, not get a new disable.

The main `rubocop` task excludes `scripts/`, `local/` and `vendor/`. `rake rubocop:scripts` lints `scripts/` and `example.rb` with the Lint and Security departments only, so long lines are fine there but unused variables, shadowing and syntax errors fail `rake`.

The WS client's `initialize` method was refactored to extract `init_main_ws_state` and `init_explorer_ws_state` helpers to reduce ABC size (33 assignments across two transports).

Predicate methods follow Ruby style (`vip?`, `connected?`, `testnet?`) — not `is_vip` / `is_connected`. RuboCop's `Naming/PredicateName` enforces this.

### CI

GitHub Actions (`.github/workflows/main.yml`) runs on pushes to `main` and `dev`, on all PRs, and on manual dispatch. It uses a read-only token.
- One `build` job runs `bundle exec rake` (the full default gate) on Ruby 3.3 and 3.4, with `fail-fast: false` so one leg's failure never cancels the other.
- The 3.4 leg then runs a built-gem smoke test:
  - `gem build`;
  - fail if the gem contains any path outside the allowlist;
  - `gem install` into an empty temp `GEM_HOME`, so dependencies resolve from rubygems the way they do for a consumer, without the lockfile or the rbsecp256k1 fork;
  - from outside the repo, `require 'hyperliquid'`, check `Hyperliquid::VERSION` against `lib/hyperliquid/version.rb`, and run `Hyperliquid.new(testnet: true)`.
- The `Ruby 3.3` and `Ruby 3.4` job names are required status checks in the `steward-auto-merge-gate` ruleset on `main`. Never rename the job or change the versions without updating that ruleset. Any new check must be a step inside this job; a new job would not gate auto-merge.

The release workflow (`.github/workflows/release.yml`) runs on `v*` tags. It fails unless the tag equals `v` + `Hyperliquid::VERSION`, and the first versioned `CHANGELOG.md` section is headed `## [VERSION]` and is non-empty. Only then does it create the GitHub release from that section.

Dependabot checks Bundler and GitHub Actions dependencies weekly with a 14-day default cooldown. Bundler major updates use a 30-day cooldown.

### rbsecp256k1 git source

The `Gemfile` pins `rbsecp256k1` to Carter's fork (`carter2099/rbsecp256k1`, full-SHA `ref:`, version 6.1.0) because rubygems only has 6.0.0, which requires `rubyzip ~> 2.3` (GHSA-47m2-wp7j-p9vc); the fork requires `rubyzip >= 3.4, < 4` and builds libsecp256k1 0.8.0. This affects only the dev/CI lockfile — a gemspec cannot declare git sources, so consumers of the published gem still resolve rubygems rbsecp256k1 6.0.0 via `eth ~> 0.5`. Dependabot is not expected to bump a SHA-pinned git ref; a Dependabot PR touching rbsecp256k1's source/ref or moving rubyzip below 3.4 must not be applied without Carter. Never `bundle update` it or drop the declaration; moving the ref is a deliberate, reviewed change (re-run the signature-parity specs in `spec/hyperliquid/signing/`). Remove the git source once an upstream rbsecp256k1 release on rubygems allows rubyzip 3.

## Release Flow

Releases happen from `main`. Day-to-day work lands on `dev`, then `dev` is merged into `main` and the version commit is pushed. `CHANGELOG.md` follows Keep-a-Changelog conventions; `lib/hyperliquid/version.rb` is the single source of version truth (gemspec reads it). Releases are atomic: only after the `Ruby` workflow is green on main and the gem is built is the RubyGems OTP requested; `gem push` goes first and the `vX.Y.Z` tag is pushed only after it succeeds. The tag push triggers the GitHub release workflow, so a failed gem push leaves no tag and no GitHub Release. The gemspec `spec.files` is an allowlist (`lib/`, `docs/`, `README.md`, `CHANGELOG.md`, `LICENSE.txt`, `SECURITY.md`); new top-level files are not packaged unless added there. RubyGems ships file modes verbatim (1.9.2 shipped `CHANGELOG.md`, `CLAUDE.md` and `lib/hyperliquid/version.rb` as `0600`), so the release flow runs `git ls-files -z | xargs -0 chmod a+r` before `gem build` and, before requesting the OTP, checks the built gem: every entry world-readable, file list equal to the allowlist, and a consumer install into a temp `GEM_HOME` (from outside the repo) that loads, reports the release version, and reproduces a fixed signing vector. CI's 3.4 leg runs the allowlist + consumer-install smoke on every push, and `release.yml` rejects a tag that does not match `Hyperliquid::VERSION` or a missing/empty CHANGELOG section.

## Documentation

`docs/API.md` lists every public method (`- \`name(signature)\` - description`, every parameter, defaults shown) in H2 sections `SDK`, `Info`, `Exchange`, `Multi-Sig Co-Signing`, `Client Order IDs (Cloid)`, `WebSocket`; `Info` H3s mirror the `# ====` banners in `info.rb`. Every main-API WS channel has a row in API.md's `### Main API Channels` table and in `docs/WS.md`'s `## Subscription Routing` table. `spec/docs_coverage_spec.rb` fails `rake` when a public method, parameter, or channel is undocumented, so a change that adds one updates the docs in the same commit. `docs/EXAMPLES.md` gets an example only for a new workflow. `CHANGELOG.md` is written only by release commits. Other guides: `CONFIGURATION.md`, `ERRORS.md`, `DEVELOPMENT.md`, `WS.md` (threading, routing, explorer transport).
