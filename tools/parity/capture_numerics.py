#!/usr/bin/env python3
"""Slippage-price and float_to_wire tables -> OUTDIR/numerics.json.

slippage: `Exchange._slippage_price(name, is_buy, slippage, px=mid)` (5 significant figures, then
round(px, (6 perp | 8 spot) - szDecimals) with Python's correctly rounded, half-even `round`), plus the order
wire string `float_to_wire(px)`. sz_decimals/is_spot are what the Python Info derived from META/SPOT_META
(spot szDecimals come from the base token). Rows with slippage 0 isolate the rounding step (exact binary ties).
float_to_wire: `hyperliquid.utils.signing.float_to_wire(x)`; `wire: null` means it raised ValueError.

Usage: tools/parity/regenerate.sh OUTDIR
Consumer: spec/hyperliquid/signing/wire_numerics_vectors_spec.rb
"""
import eth_account

from hyperliquid.exchange import Exchange
from hyperliquid.utils.constants import TESTNET_API_URL
from hyperliquid.utils.signing import float_to_wire
from parity_common import PARITY_KEY, PYTHON_SDK, outdir_from_argv, write_fixture

META = {
    "universe": [
        {"name": "BTC", "szDecimals": 5},
        {"name": "ETH", "szDecimals": 4},
        {"name": "X3", "szDecimals": 3},
        {"name": "SOL", "szDecimals": 2},
        {"name": "X1", "szDecimals": 1},
        {"name": "kPEPE", "szDecimals": 0},
    ]
}
SPOT_META = {
    "universe": [
        {"tokens": [1, 0], "name": "PURR/USDC", "index": 0, "isCanonical": True},
        {"tokens": [2, 0], "name": "@1", "index": 1, "isCanonical": False},
        {"tokens": [3, 0], "name": "@2", "index": 2, "isCanonical": False},
    ],
    "tokens": [
        {"name": "USDC", "szDecimals": 8, "weiDecimals": 8, "index": 0},
        {"name": "PURR", "szDecimals": 0, "weiDecimals": 5, "index": 1},
        {"name": "TKN", "szDecimals": 2, "weiDecimals": 8, "index": 2},
        {"name": "FIVE", "szDecimals": 5, "weiDecimals": 8, "index": 3},
    ],
}

ex = Exchange(eth_account.Account.from_key(PARITY_KEY), TESTNET_API_URL, meta=META, spot_meta=SPOT_META)

# (coin, mid, is_buy, slippage)
SLIPPAGE_CASES = [
    ("BTC", 96000.0, True, 0.05),
    ("BTC", 96000.0, False, 0.05),
    ("BTC", 96123.4, True, 0.01),
    ("BTC", 96123.4, False, 0.01),
    ("ETH", 3012.37, True, 0.05),
    ("ETH", 3012.37, False, 0.05),
    ("ETH", 1670.1, True, 0.003),
    ("X3", 0.98765, True, 0.05),
    ("X3", 0.98765, False, 0.05),
    ("SOL", 187.645, True, 0.05),
    ("SOL", 187.645, False, 0.05),
    ("X1", 12.3456, True, 0.02),
    ("kPEPE", 0.0123456, True, 0.05),
    ("kPEPE", 0.0123456, False, 0.05),
    ("PURR/USDC", 0.18765, True, 0.05),
    ("PURR/USDC", 0.18765, False, 0.05),
    ("@1", 0.001234, True, 0.05),
    ("@1", 0.001234, False, 0.05),
    ("@2", 1.23456, False, 0.05),
    ("@2", 0.000123456, True, 0.05),
    # slippage 0: exact binary ties / near-ties at the decimal-places rounding step
    ("BTC", 0.25, True, 0.0),
    ("BTC", 12.25, False, 0.0),
    ("ETH", 1.125, True, 0.0),
    ("ETH", 0.625, False, 0.0),
    ("ETH", 2.675, True, 0.0),
    ("@2", 0.0625, True, 0.0),
    ("BTC", 12344.5, True, 0.0),
    ("BTC", 12345.5, True, 0.0),
]

slippage = []
for coin, mid, is_buy, slip in SLIPPAGE_CASES:
    asset = ex.info.coin_to_asset[ex.info.name_to_coin[coin]]
    px = ex._slippage_price(coin, is_buy, slip, mid)
    slippage.append(
        {
            "coin": coin,
            "mid": mid,
            "is_buy": is_buy,
            "slippage": slip,
            "sz_decimals": ex.info.asset_to_sz_decimals[asset],
            "is_spot": asset >= 10_000,
            "px": px,
            "wire": float_to_wire(px),
        }
    )

FLOAT_TO_WIRE_CASES = [
    1670.1, 0.0147, 100, 100.0, 95000.0, 0.1 + 0.2, 1e-8, 0.00000001 * 3, 1.23456789, 123456789.12345678,
    1e20, -1.5, -0.00012345, 0.0, -0.0, -1e-13, 1e-13, 1.0000000000009, 1.000000000001, 1e-9, 5e-9,
    0.123456789, 0.000000015, 3163.0, 0.001296,
]

wire = []
for x in FLOAT_TO_WIRE_CASES:
    try:
        result = float_to_wire(x)
    except ValueError:
        result = None
    wire.append({"x": x, "wire": result})

write_fixture(outdir_from_argv(), "numerics.json", {"source": PYTHON_SDK, "slippage": slippage, "float_to_wire": wire})
