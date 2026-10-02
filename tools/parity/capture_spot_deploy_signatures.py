#!/usr/bin/env python3
"""
Capture spotDeploy L1 signature fixtures for the Ruby SDK byte-parity specs.

Run via tools/parity/regenerate.sh OUTDIR (venv from tools/parity/requirements.txt; hash reference = official
Python SDK 0.24.0, master SHA 2fdb18f95176); stdout -> OUTDIR/legacy/capture_spot_deploy_signatures.txt.

Two capture paths, both signing with the SDK's own `sign_l1_action` / `action_hash`:
  * "python" fixtures drive the real `Exchange.spot_deploy_*` methods (post is intercepted, nonce pinned),
    so the action dict (key order + value types) is exactly what the Python SDK builds.
  * "manual" fixtures cover variants the Python SDK lacks (TS-only / docs-only); the action dict is
    hand-built in the key order the Ruby plan prescribes (cross-checked 2026-10-01 against real txs echoed
    verbatim by the explorer `userDetails` endpoint), then signed with the same primitive.

Mainnet (`is_mainnet=True`), no vault, nonce 1_700_000_000_000, expires_after None unless stated.
r/s are zero-padded to 32 bytes (Python's to_hex drops leading zeros; Ruby always pads).
"""
import json

from eth_account import Account

import hyperliquid.exchange as hl_exchange
from hyperliquid.exchange import Exchange
from hyperliquid.utils.constants import MAINNET_API_URL
from hyperliquid.utils.signing import action_hash, sign_l1_action

PRIVATE_KEY = "0x1111111111111111111111111111111111111111111111111111111111111111"
NONCE = 1_700_000_000_000
EXPIRES_AFTER = 1_700_000_060_000

wallet = Account.from_key(PRIVATE_KEY)
hl_exchange.get_timestamp_ms = lambda: NONCE  # pin the nonce used inside Exchange methods

ex = Exchange(
    wallet,
    MAINNET_API_URL,
    meta={"universe": []},
    spot_meta={"universe": [], "tokens": []},
    perp_dexs=[],
)
captured = []
ex.post = lambda path, payload: captured.append(payload) or payload


def pad(sig):
    r = sig["r"] if isinstance(sig["r"], int) else int(sig["r"], 16)
    s = sig["s"] if isinstance(sig["s"], int) else int(sig["s"], 16)
    return {"r": "0x%064x" % r, "s": "0x%064x" % s, "v": sig["v"]}


def emit(name, action, sig, expires_after=None):
    h = action_hash(action, None, NONCE, expires_after)
    print(json.dumps({
        "name": name,
        "action": action,
        "action_hash": "0x" + h.hex(),
        "signature": pad(sig),
        "expires_after": expires_after,
    }))


def py(name, fn, *args):
    captured.clear()
    fn(*args)
    payload = captured[0]
    emit(name, payload["action"], payload["signature"])


def manual(name, action, expires_after=None):
    sig = sign_l1_action(wallet, action, None, NONCE, expires_after, True)
    emit(name, action, sig, expires_after)


print(json.dumps({"signer": wallet.address}))

# --- Python SDK methods (10) ---
py("register_token", ex.spot_deploy_register_token, "TEST0", 2, 8, 1_000_000_000_000, "Test token example")
py("user_genesis", ex.spot_deploy_user_genesis, 1234,
   [("0x0000000000000000000000000000000000000001", "100000000000000"),
    ("0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF", "100000000000000")],
   [(1, "100000000000000")])
py("genesis", ex.spot_deploy_genesis, 1234, "300000000000000", False)
py("genesis_no_hyperliquidity", ex.spot_deploy_genesis, 1234, "300000000000000", True)
py("register_spot", ex.spot_deploy_register_spot, 1234, 0)
py("register_hyperliquidity", ex.spot_deploy_register_hyperliquidity, 567, 2.5, 4.25, 100, None)
py("register_hyperliquidity_seeded", ex.spot_deploy_register_hyperliquidity, 567, 2.5, 4.25, 100, 10)
py("set_deployer_trading_fee_share", ex.spot_deploy_set_deployer_trading_fee_share, 1234, "0.012%")
py("enable_freeze_privilege", ex.spot_deploy_enable_freeze_privilege, 1234)
py("freeze_user", ex.spot_deploy_freeze_user, 1234, "0xAbCdEf0000000000000000000000000000000002", True)
py("revoke_freeze_privilege", ex.spot_deploy_revoke_freeze_privilege, 1234)
py("enable_quote_token", ex.spot_deploy_enable_quote_token, 1234)

# --- expires_after propagation (Python SDK sets Exchange.expires_after) ---
ex.expires_after = EXPIRES_AFTER
captured.clear()
ex.spot_deploy_enable_quote_token(1234)
emit("enable_quote_token_expires", captured[0]["action"], captured[0]["signature"], EXPIRES_AFTER)
ex.expires_after = None

# --- Variants absent from the Python SDK (hand-built in the plan's key order) ---
manual("register_token_no_full_name",
       {"type": "spotDeploy",
        "registerToken2": {"spec": {"name": "TEST0", "szDecimals": 2, "weiDecimals": 8}, "maxGas": 1_000_000_000_000}})
manual("user_genesis_blacklist",
       {"type": "spotDeploy",
        "userGenesis": {"token": 1234,
                        "userAndWei": [],
                        "existingTokenAndWei": [],
                        "blacklistUsers": [["0x0000000000000000000000000000000000000002", True],
                                           ["0x0000000000000000000000000000000000000003", False]]}})
manual("disable_quote_token", {"type": "spotDeploy", "disableQuoteToken": {"token": 1234}})
# Aligned-quote variants: GitBook documents `{token: n}`, but every live tx on mainnet (USDH, token 360) and
# testnet (token 1896) sends a bare one-element array `[n]` — the plan follows the live wire.
manual("enable_aligned_quote_token", {"type": "spotDeploy", "enableAlignedQuoteToken": [1234]})
manual("disable_aligned_quote_token", {"type": "spotDeploy", "disableAlignedQuoteToken": [1234]})
manual("request_evm_contract",
       {"type": "spotDeploy",
        "requestEvmContract": {"token": 1234, "address": "0x8cde56336e289c028c8f7cf5c20283ff02272182",
                               "evmExtraWeiDecimals": 13}})
manual("request_evm_contract_negative",
       {"type": "spotDeploy",
        "requestEvmContract": {"token": 1234, "address": "0x8cde56336e289c028c8f7cf5c20283ff02272182",
                               "evmExtraWeiDecimals": -2}})
manual("set_token_annotation",
       {"type": "spotDeploy",
        "setTokenAnnotation": {"token": 1234,
                               "annotation": {"category": "meme", "description": "A test token",
                                              "displayName": "TEST", "keywords": ["test", "cat"]}}})
manual("set_token_annotation_null_display_name",
       {"type": "spotDeploy",
        "setTokenAnnotation": {"token": 1234,
                               "annotation": {"category": "meme", "description": "A test token",
                                              "displayName": None, "keywords": []}}})
manual("set_deployer_label", {"type": "spotDeploy", "setDeployerLabel": {"label": "abc"}})
