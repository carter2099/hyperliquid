#!/usr/bin/env python3
"""
Capture L1 action-hash + signature parity fixtures for the `perpDeploy` family
(HIP-3 deployer actions). Used by the Ruby SDK plan "Perp Deploy family"
(~/agent-state/hyperliquid-sdk.md, Approved Architectural Changes).

Reference: hyperliquid-python-sdk master 2fdb18f95176 (== PyPI 0.24.0),
eth_account 0.13.7, msgpack 1.2.3.

Fixtures P1-P3 call the real Python SDK methods (`perp_deploy_register_asset`,
`perp_deploy_set_oracle`) with `_post_action` and `get_timestamp_ms` patched, so the
action dict is exactly what the official SDK signs. Fixtures D1-D14 cover variants the
Python SDK does not implement: the action dict is built by hand in the key order the plan
mandates (Python/TS order where they exist, GitBook order otherwise) and signed with the
Python SDK's own `sign_l1_action`. All string decimals are already in `float_to_wire`
normal form (no trailing zeros) so the Ruby methods produce byte-identical actions.

Run:
  tools/parity/regenerate.sh OUTDIR   # venv from tools/parity/requirements.txt;
                                      # stdout -> OUTDIR/legacy/capture_perp_deploy_signatures.txt

r/s are printed zero-padded to 32 bytes (Ruby `Signer#sign_typed_data` format); the
Python SDK's own `to_hex` would strip leading zeros.
"""
import json

import eth_account
from eth_account.messages import encode_typed_data

import hyperliquid.exchange as hl_exchange
from hyperliquid.exchange import Exchange
from hyperliquid.utils import constants
from hyperliquid.utils.signing import action_hash, construct_phantom_agent, l1_payload

PRIVATE_KEY = "0x1111111111111111111111111111111111111111111111111111111111111111"
NONCE = 1_700_000_000_000
EXPIRES_AFTER = 1_700_000_060_000
IS_MAINNET = True  # Ruby fixture signer is built with testnet: false (phantom source "a")

wallet = eth_account.Account.from_key(PRIVATE_KEY)
SIGNER_ADDR = wallet.address  # 0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A
ADDR_MIXED = "0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A"
ADDR_LOWER = ADDR_MIXED.lower()


def sign(action, expires_after=None):
    h = action_hash(action, None, NONCE, expires_after)
    data = l1_payload(construct_phantom_agent(h, IS_MAINNET))
    signed = wallet.sign_message(encode_typed_data(full_message=data))
    return (
        "0x" + h.hex(),
        {
            "r": "0x" + signed.r.to_bytes(32, "big").hex(),
            "s": "0x" + signed.s.to_bytes(32, "big").hex(),
            "v": signed.v,
        },
    )


# --- Real Python SDK methods (P1-P3) -------------------------------------------------
captured = []
hl_exchange.get_timestamp_ms = lambda: NONCE
ex = Exchange(
    wallet,
    constants.MAINNET_API_URL,
    meta={"universe": []},
    spot_meta={"universe": [], "tokens": []},
    perp_dexs=[],
)
ex._post_action = lambda action, signature, nonce: captured.append((action, signature, nonce))

ex.perp_deploy_register_asset(
    dex="test", max_gas=1_000_000_000_000, coin="test:TEST0", sz_decimals=2,
    oracle_px="10", margin_table_id=10, only_isolated=False, schema=None,
)
ex.perp_deploy_register_asset(
    dex="test", max_gas=None, coin="test:TEST0", sz_decimals=2,
    oracle_px="10", margin_table_id=10, only_isolated=True,
    schema={"fullName": "test dex", "collateralToken": 0, "oracleUpdater": ADDR_MIXED},
)
ex.perp_deploy_set_oracle(
    "test",
    {"test:TEST1": "1", "test:TEST0": "12"},
    [{"test:TEST1": "3", "test:TEST0": "14"}],
    {"test:TEST0": "12.1", "test:TEST1": "1.1"},
)

FIXTURES = [
    ("P1 registerAsset (Python SDK method, no schema)", captured[0][0], None, captured[0][1]),
    ("P2 registerAsset (Python SDK method, schema + mixed-case oracleUpdater)", captured[1][0], None, captured[1][1]),
    ("P3 setOracle (Python SDK method, unsorted input dicts)", captured[2][0], None, captured[2][1]),
]

# --- Hand-built variants (D1-D14) ----------------------------------------------------
HAND = [
    ("D1 registerAsset2 (no schema, maxGas null)", {
        "type": "perpDeploy",
        "registerAsset2": {
            "maxGas": None,
            "assetRequest": {"coin": "test:TEST1", "szDecimals": 3, "oraclePx": "2.5",
                             "marginTableId": 20, "marginMode": "strictIsolated"},
            "dex": "test",
            "schema": None,
        },
    }, None),
    ("D2 registerAsset2 (schema, oracleUpdater null)", {
        "type": "perpDeploy",
        "registerAsset2": {
            "maxGas": 500_000_000,
            "assetRequest": {"coin": "test:TEST1", "szDecimals": 3, "oraclePx": "2.5",
                             "marginTableId": 20, "marginMode": "noCross"},
            "dex": "test",
            "schema": {"fullName": "test dex", "collateralToken": 0, "oracleUpdater": None},
        },
    }, None),
    ("D3 setFundingMultipliers", {
        "type": "perpDeploy",
        "setFundingMultipliers": [["test:A", "0.5"], ["test:B", "2"]],
    }, None),
    ("D4 setFundingInterestRates", {
        "type": "perpDeploy",
        "setFundingInterestRates": [["test:A", "-0.0001"], ["test:B", "0.00005"]],
    }, None),
    ("D5 setFundingClamps", {
        "type": "perpDeploy",
        "setFundingClamps": [["test:A", "0.0003"], ["test:B", "0.01"]],
    }, None),
    ("D6 haltTrading", {
        "type": "perpDeploy",
        "haltTrading": {"coin": "test:A", "isHalted": True},
    }, None),
    ("D7 insertMarginTable", {
        "type": "perpDeploy",
        "insertMarginTable": {
            "dex": "test",
            "marginTable": {
                "description": "tiered",
                "marginTiers": [
                    {"lowerBound": 0, "maxLeverage": 20},
                    {"lowerBound": 1_000_000, "maxLeverage": 10},
                ],
            },
        },
    }, None),
    ("D8 setMarginTableIds", {
        "type": "perpDeploy",
        "setMarginTableIds": [["test:A", 10], ["test:B", 20]],
    }, None),
    ("D9 setFeeRecipient (address lowercased)", {
        "type": "perpDeploy",
        "setFeeRecipient": {"dex": "test", "feeRecipient": ADDR_LOWER},
    }, None),
    ("D10 setOpenInterestCaps (null removes cap)", {
        "type": "perpDeploy",
        "setOpenInterestCaps": [["test:A", 1_000_000], ["test:B", None]],
    }, None),
    ("D11 setSubDeployers (user lowercased)", {
        "type": "perpDeploy",
        "setSubDeployers": {
            "dex": "test",
            "subDeployers": [
                {"variant": "setOracle", "user": ADDR_LOWER, "allowed": True},
                {"variant": "haltTrading", "user": ADDR_LOWER, "allowed": False},
            ],
        },
    }, None),
    ("D12 setMarginModes", {
        "type": "perpDeploy",
        "setMarginModes": [["test:A", "noCross"], ["test:B", "strictIsolated"]],
    }, None),
    ("D13 setDeployerFees", {
        "type": "perpDeploy",
        "setDeployerFees": [
            ["test:A", {"scale": "0.5", "growthMode": False}],
            ["test:B", {"scale": "3.01", "growthMode": True}],
        ],
    }, None),
    ("D14 setPerpAnnotation (displayName null)", {
        "type": "perpDeploy",
        "setPerpAnnotation": {
            "coin": "test:A", "category": "stocks", "description": "Test asset",
            "displayName": None, "keywords": ["test", "demo"],
        },
    }, None),
    ("D15 disableDex", {"type": "perpDeploy", "disableDex": "test"}, None),
    ("D16 haltTrading with expires_after", {
        "type": "perpDeploy",
        "haltTrading": {"coin": "test:A", "isHalted": False},
    }, EXPIRES_AFTER),
]

print("Signer address (sanity check, must match Ruby):", SIGNER_ADDR)
print(f"nonce={NONCE} mainnet={IS_MAINNET}")
print()

for name, action, expires_after, py_sig in FIXTURES:
    h, sig = sign(action, expires_after)
    # Cross-check our re-signing against the Python SDK's own signature (to_hex strips zeros)
    assert int(py_sig["r"], 16) == int(sig["r"], 16) and int(py_sig["s"], 16) == int(sig["s"], 16)
    assert py_sig["v"] == sig["v"]
    print(f"=== {name} ===")
    print("  action:", json.dumps(action, separators=(",", ":")))
    print("  action_hash:", h)
    print("  r:", sig["r"])
    print("  s:", sig["s"])
    print("  v:", sig["v"])
    print()

for name, action, expires_after in HAND:
    h, sig = sign(action, expires_after)
    print(f"=== {name} ===")
    print("  action:", json.dumps(action, separators=(",", ":")))
    if expires_after is not None:
        print("  expires_after:", expires_after)
    print("  action_hash:", h)
    print("  r:", sig["r"])
    print("  s:", sig["s"])
    print("  v:", sig["v"])
    print()
