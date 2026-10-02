# Python-SDK parity fixtures

The official Python SDK is the reference for action bytes and signatures. The scripts here regenerate every
fixture under `spec/fixtures/parity/` from it. `tools/` is not packaged into the gem.

## Regenerate / check

```sh
tools/parity/regenerate.sh OUTDIR   # writes OUTDIR/<same relative paths as spec/fixtures/parity/>
rake parity:check                   # regenerate into a temp dir, then diff -r against spec/fixtures/parity
```

`regenerate.sh` creates the venv at `$HL_PARITY_VENV` (default `tmp/parity-venv`) and installs
`requirements.txt` into it. It reinstalls whenever that file changes. You need `python3`, and network access
for the first install. Output is deterministic: fixed keys, fixed nonces, pinned clocks, and sorted JSON keys.
Payloads where key order matters are stored as compact JSON strings.

To update a fixture, change the capture script, run `tools/parity/regenerate.sh spec/fixtures/parity`, and
commit the scripts and the regenerated files together. Never hand-edit a fixture.

## Upstream references

- `hyperliquid-python-sdk==0.24.0` (git `2fdb18f9517675ea03695a0962bd19eece9c83f0`), `eth-account==0.13.7`,
  `msgpack==1.2.3`. The transitive dependencies are pinned in `requirements.txt`.
- The published vectors come from upstream `tests/signing_test.py` at that SHA.
  `capture_l1_signing_vectors.py` aborts if the SDK no longer reproduces them.
- The Python SDK has no EIP-712 tables for LinkStakingUser, StakingLinkDisableTradingUser,
  UserPortfolioMargin, CDeposit, CWithdraw and SendToEvmWithData. These are copied from the TS SDK
  `@nktkas/hyperliquid` 0.33.1 (`esm/api/exchange/_methods/<method>.js`) and signed with eth_account.

## Scripts → fixtures → specs

| Script | Fixture | Spec |
|---|---|---|
| `capture_l1_signing_vectors.py` | `l1_signing_vectors.json` | `spec/hyperliquid/signing/python_vectors_spec.rb` |
| `capture_eip712_user_signed_vectors.py` | `eip712_user_signed_vectors.json` | `spec/hyperliquid/signing/eip712_vectors_spec.rb` |
| `capture_l1_wire_golden.py` | `l1_wire_golden.json` | `spec/hyperliquid/exchange_wire_golden_spec.rb` |
| `capture_numerics.py` | `numerics.json` | `spec/hyperliquid/signing/wire_numerics_vectors_spec.rb` |
| `capture_{multi_sig,outcome_deploy,perp_deploy,send_to_evm_with_data,spot_deploy,star,validator_action}_signatures.py` | `legacy/<script>.txt` (stdout transcript) | literals in `exchange_spec.rb` / `multi_sig_spec.rb` that cite the script |

`parity_common.py` holds the helpers these scripts share. `capture_fast_asset_ctxs_frames.py` is a live,
read-only WebSocket probe whose output depends on the market, so `regenerate.sh` does not run it.

## Adding a vector

When you add a new L1 or user-signed action, add a row to the matching capture script. For an L1 action that
both SDKs implement, also add the equivalent Ruby call to the `calls` table in
`exchange_wire_golden_spec.rb`; the spec fails if a fixture row has no mapped call, or a call has no row.
Then regenerate and commit.
