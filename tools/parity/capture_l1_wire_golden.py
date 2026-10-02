#!/usr/bin/env python3
"""Wire golden for the L1 Exchange methods both SDKs implement -> OUTDIR/l1_wire_golden.json.

Drives the real Python `Exchange` methods with `_post_action` intercepted, `get_timestamp_ms` pinned and
`Info` built from the fixed meta/spotMeta below (no network). Each row records the posted action as compact JSON
(insertion order == msgpack order == the bytes the signature covers), the nonce, the posted vaultAddress /
expiresAfter, and the zero-padded signature. Market rows feed the mid through `px` (Python) and the
`info_responses.allMids` stub (Ruby); market_close reads `info_responses.clearinghouseState`.

HIP-3 deploy (spotDeploy/perpDeploy/star/outcomeDeploy) and validator (CSigner/CValidator) actions are already
pinned through Ruby Exchange methods by the legacy capture scripts in this directory.

Usage: tools/parity/regenerate.sh OUTDIR
Consumer: spec/hyperliquid/exchange_wire_golden_spec.rb (maps every `name` to the equivalent Ruby call)
"""
import eth_account

import hyperliquid.exchange as hl_exchange
from hyperliquid.exchange import Exchange
from hyperliquid.utils.constants import MAINNET_API_URL, TESTNET_API_URL
from hyperliquid.utils.types import Cloid
from parity_common import PARITY_KEY, PYTHON_SDK, compact, outdir_from_argv, pad_sig, write_fixture

NONCE = 1_700_000_000_000
EXPIRES_AFTER = 1_700_000_060_000
VAULT = "0x1719884EB866cb12b2287399b15f7db5e7d775ea"  # mixed case: posted verbatim, hashed lowercased
SUB_ACCOUNT = "0x1d9470d4b963f552e6f671a81619d395877bf409"
BUILDER = "0xAbCdEf0123456789aBcDeF0123456789AbCdEf01"
CLOID_A = "0x0000000000000000000000000000abcd"
CLOID_B = "0x00000000000000000000000000001234"
PURR = "PURR:0xc4bf3f870c0e9465323c0b6ed28096c2"

META = {
    "universe": [
        {"name": "BTC", "szDecimals": 5, "maxLeverage": 40},
        {"name": "ETH", "szDecimals": 4, "maxLeverage": 25},
        {"name": "SOL", "szDecimals": 2, "maxLeverage": 20},
        {"name": "DOGE", "szDecimals": 0, "maxLeverage": 10},
    ]
}
# Real /info spotMeta shape: szDecimals live on the tokens, not on the universe pairs.
SPOT_META = {
    "universe": [
        {"tokens": [1, 0], "name": "PURR/USDC", "index": 0, "isCanonical": True},
        {"tokens": [2, 0], "name": "@1", "index": 1, "isCanonical": False},
    ],
    "tokens": [
        {"name": "USDC", "szDecimals": 8, "weiDecimals": 8, "index": 0, "isCanonical": True},
        {"name": "PURR", "szDecimals": 0, "weiDecimals": 5, "index": 1, "isCanonical": True},
        {"name": "TKN", "szDecimals": 2, "weiDecimals": 8, "index": 2, "isCanonical": False},
    ],
}
ALL_MIDS = {"BTC": "96123.4", "ETH": "3012.37", "SOL": "187.645", "DOGE": "0.123456", "PURR/USDC": "0.18765",
            "@1": "0.001234"}
SIGNER_ADDRESS = eth_account.Account.from_key(PARITY_KEY).address
CLEARINGHOUSE_STATE = {
    "assetPositions": [{"type": "oneWay", "position": {"coin": "ETH", "szi": "-0.25"}}],
}

hl_exchange.get_timestamp_ms = lambda: NONCE

_posted = []


def _capture(self, action, signature, nonce):
    payload = {
        "action": action,
        "nonce": nonce,
        "signature": signature,
        "vaultAddress": self.vault_address if action["type"] not in ["usdClassTransfer", "sendAsset"] else None,
        "expiresAfter": self.expires_after,
    }
    _posted.append(payload)
    return {"status": "ok"}


Exchange._post_action = _capture


def exchange(mainnet, vault=None, expires_after=None):
    ex = Exchange(
        eth_account.Account.from_key(PARITY_KEY),
        MAINNET_API_URL if mainnet else TESTNET_API_URL,
        meta=META,
        vault_address=vault,
        spot_meta=SPOT_META,
    )
    ex.info.user_state = lambda address, dex="": CLEARINGHOUSE_STATE
    ex.set_expires_after(expires_after)
    return ex


def gtc(tif="Gtc"):
    return {"limit": {"tif": tif}}


def mid(coin):
    return float(ALL_MIDS[coin])


# (name, mainnet, vault, expires_after, call(ex))
CASES = [
    ("order_limit_gtc_mainnet", True, None, None, lambda ex: ex.order("ETH", True, 0.0147, 1670.1, gtc())),
    ("order_limit_gtc_testnet", False, None, None, lambda ex: ex.order("ETH", True, 0.0147, 1670.1, gtc())),
    ("order_limit_alo_reduce_only", False, None, None,
     lambda ex: ex.order("BTC", False, 0.001, 95000.5, gtc("Alo"), reduce_only=True)),
    ("order_limit_ioc_spot", False, None, None, lambda ex: ex.order("PURR/USDC", True, 100, 0.12345, gtc("Ioc"))),
    ("order_trigger_tp_market", False, None, None,
     lambda ex: ex.order("ETH", False, 0.5, 3500, {"trigger": {"triggerPx": 3600, "isMarket": True, "tpsl": "tp"}},
                         reduce_only=True)),
    ("order_trigger_sl_limit", True, None, None,
     lambda ex: ex.order("SOL", False, 1.25, 150.1,
                         {"trigger": {"triggerPx": 150.25, "isMarket": False, "tpsl": "sl"}}, reduce_only=True)),
    ("order_with_cloid", False, None, None,
     lambda ex: ex.order("ETH", True, 0.1, 2000, gtc(), cloid=Cloid.from_str(CLOID_A))),
    ("order_with_builder", False, None, None,
     lambda ex: ex.order("ETH", True, 0.1, 2000, gtc(), builder={"b": BUILDER, "f": 10})),
    ("order_vault_mainnet", True, VAULT, None, lambda ex: ex.order("DOGE", True, 100, 0.12, gtc())),
    ("order_expires_testnet", False, None, EXPIRES_AFTER, lambda ex: ex.order("ETH", True, 0.1, 2000, gtc())),
    ("order_vault_expires_testnet", False, VAULT, EXPIRES_AFTER,
     lambda ex: ex.order("BTC", True, 0.002, 90000, gtc("Alo"))),
    ("bulk_orders_normal_tpsl", False, None, None,
     lambda ex: ex.bulk_orders(
         [
             {"coin": "ETH", "is_buy": True, "sz": 0.2, "limit_px": 3000, "order_type": gtc(),
              "reduce_only": False, "cloid": Cloid.from_str(CLOID_A)},
             {"coin": "ETH", "is_buy": False, "sz": 0.2, "limit_px": 2900,
              "order_type": {"trigger": {"triggerPx": 2950, "isMarket": True, "tpsl": "sl"}}, "reduce_only": True},
         ],
         grouping="normalTpsl")),
    ("bulk_orders_builder_mainnet", True, None, None,
     lambda ex: ex.bulk_orders(
         [
             {"coin": "BTC", "is_buy": True, "sz": 0.01, "limit_px": 95000, "order_type": gtc("Ioc"),
              "reduce_only": False},
             {"coin": "@1", "is_buy": False, "sz": 12.5, "limit_px": 0.0015, "order_type": gtc(),
              "reduce_only": False},
         ],
         builder={"b": BUILDER, "f": 25})),
    ("market_open_perp_buy", False, None, None, lambda ex: ex.market_open("ETH", True, 0.1, px=mid("ETH"))),
    ("market_open_perp_sell", True, None, None,
     lambda ex: ex.market_open("BTC", False, 0.01, px=mid("BTC"), slippage=0.01)),
    ("market_open_spot_buy", False, None, None, lambda ex: ex.market_open("@1", True, 100, px=mid("@1"))),
    ("market_close_short", False, None, None, lambda ex: ex.market_close("ETH", px=mid("ETH"))),
    ("cancel", False, None, None, lambda ex: ex.cancel("ETH", 123456789)),
    ("cancel_vault_mainnet", True, VAULT, None, lambda ex: ex.cancel("BTC", 42)),
    ("cancel_by_cloid", False, None, None, lambda ex: ex.cancel_by_cloid("ETH", Cloid.from_str(CLOID_A))),
    ("bulk_cancel_mainnet", True, None, None,
     lambda ex: ex.bulk_cancel([{"coin": "ETH", "oid": 1}, {"coin": "PURR/USDC", "oid": 2}])),
    ("bulk_cancel_by_cloid", False, None, None,
     lambda ex: ex.bulk_cancel_by_cloid([{"coin": "ETH", "cloid": Cloid.from_str(CLOID_A)},
                                          {"coin": "SOL", "cloid": Cloid.from_str(CLOID_B)}])),
    ("modify_order_oid", False, None, None, lambda ex: ex.modify_order(123, "ETH", True, 0.1, 2000.5, gtc())),
    ("modify_order_cloid_mainnet", True, None, None,
     lambda ex: ex.modify_order(Cloid.from_str(CLOID_A), "ETH", False, 0.3, 3100, gtc("Alo"), reduce_only=True,
                                cloid=Cloid.from_str(CLOID_B))),
    ("bulk_modify_orders", False, None, None,
     lambda ex: ex.bulk_modify_orders_new([
         {"oid": 1, "order": {"coin": "BTC", "is_buy": True, "sz": 0.001, "limit_px": 90000, "order_type": gtc(),
                              "reduce_only": False, "cloid": None}},
         {"oid": Cloid.from_str(CLOID_B),
          "order": {"coin": "ETH", "is_buy": False, "sz": 0.5, "limit_px": 3500,
                    "order_type": {"trigger": {"triggerPx": 3400, "isMarket": True, "tpsl": "tp"}},
                    "reduce_only": True, "cloid": Cloid.from_str(CLOID_B)}},
     ])),
    ("update_leverage_cross", False, None, None, lambda ex: ex.update_leverage(10, "ETH")),
    ("update_leverage_isolated_mainnet", True, None, None, lambda ex: ex.update_leverage(5, "BTC", False)),
    ("update_isolated_margin", False, None, None, lambda ex: ex.update_isolated_margin(12.5, "ETH")),
    ("update_isolated_margin_negative_mainnet", True, None, None,
     lambda ex: ex.update_isolated_margin(-3.25, "SOL")),
    ("schedule_cancel_unset", False, None, None, lambda ex: ex.schedule_cancel(None)),
    ("schedule_cancel_time_mainnet", True, None, None, lambda ex: ex.schedule_cancel(1_700_000_100_000)),
    ("schedule_cancel_vault_expires", False, VAULT, EXPIRES_AFTER,
     lambda ex: ex.schedule_cancel(1_700_000_100_000)),
    ("create_sub_account", False, None, None, lambda ex: ex.create_sub_account("parity-sub")),
    ("create_sub_account_expires", False, None, EXPIRES_AFTER, lambda ex: ex.create_sub_account("parity-sub")),
    ("sub_account_transfer", False, None, None, lambda ex: ex.sub_account_transfer(SUB_ACCOUNT, True, 1_000_000)),
    ("sub_account_transfer_expires", True, None, EXPIRES_AFTER,
     lambda ex: ex.sub_account_transfer(SUB_ACCOUNT, False, 2_500_000)),
    ("sub_account_spot_transfer", False, None, None,
     lambda ex: ex.sub_account_spot_transfer(SUB_ACCOUNT, True, PURR, 12.5)),
    ("sub_account_spot_transfer_expires", False, None, EXPIRES_AFTER,
     lambda ex: ex.sub_account_spot_transfer(SUB_ACCOUNT, False, PURR, 3)),
    ("vault_usd_transfer", False, None, None, lambda ex: ex.vault_usd_transfer(VAULT, True, 5_000_000)),
    ("vault_usd_transfer_expires", False, None, EXPIRES_AFTER,
     lambda ex: ex.vault_usd_transfer(VAULT, False, 1_000_000)),
    ("set_referrer", False, None, None, lambda ex: ex.set_referrer("PARITY")),
    ("set_referrer_expires", False, None, EXPIRES_AFTER, lambda ex: ex.set_referrer("PARITY")),
    ("use_big_blocks_enable", False, None, None, lambda ex: ex.use_big_blocks(True)),
    ("use_big_blocks_disable_expires_mainnet", True, None, EXPIRES_AFTER, lambda ex: ex.use_big_blocks(False)),
    ("noop", False, None, None, lambda ex: ex.noop(1_700_000_000_123)),
    ("noop_vault_mainnet", True, VAULT, None, lambda ex: ex.noop(1_700_000_000_123)),
    ("agent_enable_dex_abstraction", False, None, None, lambda ex: ex.agent_enable_dex_abstraction()),
    ("agent_set_abstraction", False, None, None, lambda ex: ex.agent_set_abstraction("u")),
    ("gossip_priority_bid", False, None, None, lambda ex: ex.gossip_priority_bid(7, "1.2.3.4", 1_000_000)),
]

rows = []
for name, mainnet, vault, expires_after, call in CASES:
    del _posted[:]
    call(exchange(mainnet, vault, expires_after))
    (payload,) = _posted
    rows.append(
        {
            "name": name,
            "mainnet": mainnet,
            "action_json": compact(payload["action"]),
            "nonce": payload["nonce"],
            "vault_address": payload["vaultAddress"],
            "expires_after": payload["expiresAfter"],
            **pad_sig(payload["signature"]),
        }
    )

write_fixture(
    outdir_from_argv(),
    "l1_wire_golden.json",
    {
        "source": PYTHON_SDK,
        "private_key": PARITY_KEY,
        "signer_address": SIGNER_ADDRESS,
        "info_responses": {
            "meta": META,
            "spotMeta": SPOT_META,
            "allMids": ALL_MIDS,
            "clearinghouseState": CLEARINGHOUSE_STATE,
        },
        "rows": rows,
    },
)
