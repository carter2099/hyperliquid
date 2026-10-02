#!/usr/bin/env python3
"""
Capture L1 action-hash + phantom-agent signature fixtures for the HIP-3* `star`
operations of the `perpDeploy` action (GitBook hip-3-deployer-actions page,
"HIP-3* (testnet-only)" section). Neither the Python nor the TS SDK implements
these operations, so the official Python SDK's generic L1 signing primitives
(`hyperliquid.utils.signing.action_hash` / `sign_l1_action`) are the reference:
Python `perp_deploy_*` methods sign every `perpDeploy` action with
`sign_l1_action(wallet, action, None, nonce, expires_after, is_mainnet)`.

Run via tools/parity/regenerate.sh OUTDIR (venv from tools/parity/requirements.txt: hyperliquid-python-sdk
0.24.0, eth-account 0.13.7, msgpack 1.2.3); stdout -> OUTDIR/legacy/capture_star_signatures.txt.

All fixtures sign for TESTNET (phantom source "b") because HIP-3* is testnet-only.
Ruby spec equivalent: Signer.new(private_key: PRIVATE_KEY, testnet: true).
"""
from eth_account import Account

from hyperliquid.utils.signing import action_hash, sign_l1_action

PRIVATE_KEY = "0x1111111111111111111111111111111111111111111111111111111111111111"
NONCE = 1_700_000_000_000
EXPIRES_AFTER = 1_700_000_060_000
IS_MAINNET = False

wallet = Account.from_key(PRIVATE_KEY)
SIGNER = wallet.address  # 0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A
USER = SIGNER.lower()  # proxied user (Ruby spec passes the checksummed form; SDK lowercases)
DEST = "0x00000000000000000000000000000000000000bb"
DEX = "test"
# Ruby spec stubs perpDexs => [nil, {name: 'test'}] and meta(dex: 'test') universe
# [test:BTC (szDecimals 5), test:ETH (szDecimals 4)], so asset ids are 110000 / 110001.
BTC = 110000
ETH = 110001


def star(operation):
    return {"type": "perpDeploy", "star": {"dex": DEX, "operation": operation}}


def proxy(op):
    return star({"proxy": [USER, op]})


FIXTURES = [
    ("F1 modifyApproval true", proxy({"modifyApproval": True}), None),
    ("F2 modifyBackstopLiquidatorApproval true", proxy({"modifyBackstopLiquidatorApproval": True}), None),
    ("F3 setReduceOnly true", proxy({"setReduceOnly": True}), None),
    ("F4 cancel", proxy({"cancel": {"cancels": [{"a": BTC, "o": 12345}]}}), None),
    ("F5 cancelAll null", proxy({"cancelAll": {"assets": None}}), None),
    ("F6 cancelAll [BTC, ETH]", proxy({"cancelAll": {"assets": [BTC, ETH]}}), None),
    (
        "F7 order (reduce-only limit Gtc)",
        proxy(
            {
                "order": {
                    "orders": [
                        {"a": BTC, "b": False, "p": "95000", "s": "0.01", "r": True, "t": {"limit": {"tif": "Gtc"}}}
                    ],
                    "grouping": "na",
                }
            }
        ),
        None,
    ),
    ("F8 sendAsset", proxy({"sendAsset": {"destination": DEST, "amount": "100.0"}}), None),
    # Ruby converts prices with perp_deploy_decimal (the perp-deploy plan's setOracle
    # convention: String verbatim, Numeric via float_to_wire), so the Ruby spec passes
    # {'test:ETH' => '4000.0', 'test:BTC' => 100_000} and the wire carries the strings
    # below, sorted by key ("4000.0" stays verbatim; 100_000 normalizes to "100000").
    (
        "F9 setOracle (sorted; String verbatim, Numeric float_to_wire)",
        star({"setOracle": {"oraclePxs": sorted({"test:ETH": "4000.0", "test:BTC": "100000"}.items())}}),
        None,
    ),
    ("F10 modifyApproval false + expires_after", proxy({"modifyApproval": False}), EXPIRES_AFTER),
]

print("Signer address (sanity check, must match Ruby):", SIGNER)
for name, action, expires_after in FIXTURES:
    # sorted(dict.items()) yields tuples; msgpack packs tuples and lists identically (array)
    h = action_hash(action, None, NONCE, expires_after)
    sig = sign_l1_action(wallet, action, None, NONCE, expires_after, IS_MAINNET)
    print()
    print(f"=== {name} ===")
    print(f"  action: {action}")
    print(f"  expires_after: {expires_after}")
    print(f"  action_hash: 0x{h.hex()}")
    print(f"  r: {sig['r']}")
    print(f"  s: {sig['s']}")
    print(f"  v: {sig['v']}")
