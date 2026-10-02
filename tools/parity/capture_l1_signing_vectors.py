#!/usr/bin/env python3
"""L1 (phantom-agent) signing vectors -> OUTDIR/l1_signing_vectors.json.

Rows tagged `upstream_test` are the published vectors from hyperliquid-python-sdk tests/signing_test.py at
0.24.0 / 2fdb18f95176; this script recomputes them with the SDK's own primitives and aborts if any differs from
the published literal (so a regenerate also proves upstream still produces them). Rows with `upstream_test: null`
are captured here (expires_after layout `\\x00 + u64be` after the vault flag) with the same primitives.

Usage: tools/parity/regenerate.sh OUTDIR   (or: python capture_l1_signing_vectors.py OUTDIR inside the venv)
Consumer: spec/hyperliquid/signing/python_vectors_spec.rb
"""
import eth_account
from eth_utils import to_hex

from hyperliquid.utils.signing import (
    action_hash,
    construct_phantom_agent,
    float_to_int_for_hashing,
    order_request_to_order_wire,
    order_wires_to_order_action,
    sign_l1_action,
)
from parity_common import PARITY_KEY, PYTHON_SDK, compact, outdir_from_argv, pad_sig, write_fixture

wallet = eth_account.Account.from_key(PARITY_KEY)
VAULT = "0x1719884eb866cb12b2287399b15f7db5e7d775ea"
EXPIRES_AFTER = 1_700_000_060_000

# --- test_phantom_agent_creation_matches_production -------------------------------------------------------------
PHANTOM_NONCE = 1677777606040
phantom_request = {
    "coin": "ETH",
    "is_buy": True,
    "sz": 0.0147,
    "limit_px": 1670.1,
    "reduce_only": False,
    "order_type": {"limit": {"tif": "Ioc"}},
    "cloid": None,
}
phantom_action = order_wires_to_order_action([order_request_to_order_wire(phantom_request, 4)])
phantom_hash = to_hex(construct_phantom_agent(action_hash(phantom_action, None, PHANTOM_NONCE, None), True)["connectionId"])
assert phantom_hash == "0x0fcbeda5ae3c4950a548021552a4fea2226858c4453571bf3f24ba017eac2908", phantom_hash

phantom = {
    "upstream_test": "test_phantom_agent_creation_matches_production",
    "coin": "ETH",
    "asset": 4,
    "is_buy": True,
    "sz": phantom_request["sz"],
    "limit_px": phantom_request["limit_px"],
    "tif": "Ioc",
    "nonce": PHANTOM_NONCE,
    "mainnet": True,
    "action_json": compact(phantom_action),
    "connection_id": phantom_hash,
}

# --- signature vectors --------------------------------------------------------------------------------------------
dummy = {"type": "dummy", "num": float_to_int_for_hashing(1000)}
tpsl_request = {
    "coin": "ETH",
    "is_buy": True,
    "sz": 100,
    "limit_px": 100,
    "reduce_only": False,
    "order_type": {"trigger": {"triggerPx": 103, "isMarket": True, "tpsl": "sl"}},
    "cloid": None,
}
tpsl = order_wires_to_order_action([order_request_to_order_wire(tpsl_request, 1)])
schedule_cancel = {"type": "scheduleCancel"}
schedule_cancel_time = {"type": "scheduleCancel", "time": 123456789}

# (name, upstream test or None, action, vault, expires_after, mainnet, published (r, s, v) or None)
CASES = [
    ("dummy_mainnet", "test_l1_action_signing_matches", dummy, None, None, True,
     ("0x53749d5b30552aeb2fca34b530185976545bb22d0b3ce6f62e31be961a59298",
      "0x755c40ba9bf05223521753995abb2f73ab3229be8ec921f350cb447e384d8ed8", 27)),
    ("dummy_testnet", "test_l1_action_signing_matches", dummy, None, None, False,
     ("0x542af61ef1f429707e3c76c5293c80d01f74ef853e34b76efffcb57e574f9510",
      "0x17b8b32f086e8cdede991f1e2c529f5dd5297cbe8128500e00cbaf766204a613", 28)),
    ("dummy_vault_mainnet", "test_l1_action_signing_matches_with_vault", dummy, VAULT, None, True,
     ("0x3c548db75e479f8012acf3000ca3a6b05606bc2ec0c29c50c515066a326239",
      "0x4d402be7396ce74fbba3795769cda45aec00dc3125a984f2a9f23177b190da2c", 28)),
    ("dummy_vault_testnet", "test_l1_action_signing_matches_with_vault", dummy, VAULT, None, False,
     ("0xe281d2fb5c6e25ca01601f878e4d69c965bb598b88fac58e475dd1f5e56c362b",
      "0x7ddad27e9a238d045c035bc606349d075d5c5cd00a6cd1da23ab5c39d4ef0f60", 27)),
    ("tpsl_order_mainnet", "test_l1_action_signing_tpsl_order_matches", tpsl, None, None, True,
     ("0x98343f2b5ae8e26bb2587daad3863bc70d8792b09af1841b6fdd530a2065a3f9",
      "0x6b5bb6bb0633b710aa22b721dd9dee6d083646a5f8e581a20b545be6c1feb405", 27)),
    ("tpsl_order_testnet", "test_l1_action_signing_tpsl_order_matches", tpsl, None, None, False,
     ("0x971c554d917c44e0e1b6cc45d8f9404f32172a9d3b3566262347d0302896a2e4",
      "0x206257b104788f80450f8e786c329daa589aa0b32ba96948201ae556d5637eac", 28)),
    ("schedule_cancel_mainnet", "test_schedule_cancel_action", schedule_cancel, None, None, True,
     ("0x6cdfb286702f5917e76cd9b3b8bf678fcc49aec194c02a73e6d4f16891195df9",
      "0x6557ac307fa05d25b8d61f21fb8a938e703b3d9bf575f6717ba21ec61261b2a0", 27)),
    ("schedule_cancel_testnet", "test_schedule_cancel_action", schedule_cancel, None, None, False,
     ("0xc75bb195c3f6a4e06b7d395acc20bbb224f6d23ccff7c6a26d327304e6efaeed",
      "0x342f8ede109a29f2c0723bd5efb9e9100e3bbb493f8fb5164ee3d385908233df", 28)),
    ("schedule_cancel_time_mainnet", "test_schedule_cancel_action", schedule_cancel_time, None, None, True,
     ("0x609cb20c737945d070716dcc696ba030e9976fcf5edad87afa7d877493109d55",
      "0x16c685d63b5c7a04512d73f183b3d7a00da5406ff1f8aad33f8ae2163bab758b", 28)),
    ("schedule_cancel_time_testnet", "test_schedule_cancel_action", schedule_cancel_time, None, None, False,
     ("0x4e4f2dbd4107c69783e251b7e1057d9f2b9d11cee213441ccfa2be63516dc5bc",
      "0x706c656b23428c8ba356d68db207e11139ede1670481a9e01ae2dfcdb0e1a678", 27)),
    ("dummy_expires_mainnet", None, dummy, None, EXPIRES_AFTER, True, None),
    ("dummy_expires_testnet", None, dummy, None, EXPIRES_AFTER, False, None),
    ("dummy_vault_expires_testnet", None, dummy, VAULT, EXPIRES_AFTER, False, None),
]

vectors = []
for name, upstream, action, vault, expires_after, mainnet, published in CASES:
    nonce = 0
    sig = sign_l1_action(wallet, action, vault, nonce, expires_after, mainnet)
    if published is not None:
        got = (sig["r"], sig["s"], sig["v"])
        assert got == published, f"{name}: upstream vector drifted: {got} != {published}"
    vectors.append(
        {
            "name": name,
            "upstream_test": upstream,
            "action_json": compact(action),
            "nonce": nonce,
            "vault_address": vault,
            "expires_after": expires_after,
            "mainnet": mainnet,
            "action_hash": to_hex(action_hash(action, vault, nonce, expires_after)),
            **pad_sig(sig),
        }
    )

write_fixture(
    outdir_from_argv(),
    "l1_signing_vectors.json",
    {"source": PYTHON_SDK, "private_key": PARITY_KEY, "phantom_agent": phantom, "vectors": vectors},
)
