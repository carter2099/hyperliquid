#!/usr/bin/env python3
"""EIP-712 user-signed vectors for every `Hyperliquid::Signing::EIP712::*_TYPES` table
-> OUTDIR/eip712_user_signed_vectors.json.

`source: python-sdk` rows call the Python SDK's own `sign_*` function (or `sign_user_signed_action` with the SDK's
table constant for SendMultiSig); the type table is read back from the typed-data payload the SDK actually signed
(spy on `user_signed_payload`), so nothing here re-types a Python table.
`source: ts-sdk` rows cover tables the Python SDK 0.24.0 does not implement; their field lists are copied from
@nktkas/hyperliquid 0.33.1 (`esm/api/exchange/_methods/<method>.js`, exported `<Name>Types`) and signed with the
Python SDK's generic `sign_user_signed_action` (eth_account 0.13.7).

Each table is signed for Mainnet and Testnet with the upstream signing_test.py key. Field `message` holds every
signed field except hyperliquidChain (given by `chain`); `signatureChainId` is always 0x66eee.

Usage: tools/parity/regenerate.sh OUTDIR
Consumer: spec/hyperliquid/signing/eip712_vectors_spec.rb
"""
import eth_account

import hyperliquid.utils.signing as S
from hyperliquid.utils.signing import action_hash
from parity_common import PARITY_KEY, PYTHON_SDK, outdir_from_argv, pad_sig, write_fixture

wallet = eth_account.Account.from_key(PARITY_KEY)
NONCE = 1_700_000_000_000
DEST = "0x5e9ee1089755c3435139848e47e6635505d5a13a"
OTHER = "0x0000000000000000000000000000000000000abc"

_signed_payloads = []
_original_payload = S.user_signed_payload


def _spy(primary_type, payload_types, action):
    data = _original_payload(primary_type, payload_types, action)
    _signed_payloads.append(data)
    return data


S.user_signed_payload = _spy

TS_SOURCE = "ts-sdk @nktkas/hyperliquid 0.33.1 esm/api/exchange/_methods/{}.js"
TS_TABLES = {
    "LinkStakingUser": [
        {"name": "hyperliquidChain", "type": "string"},
        {"name": "user", "type": "address"},
        {"name": "isFinalize", "type": "bool"},
        {"name": "nonce", "type": "uint64"},
    ],
    "StakingLinkDisableTradingUser": [
        {"name": "hyperliquidChain", "type": "string"},
        {"name": "tradingUser", "type": "address"},
        {"name": "nonce", "type": "uint64"},
    ],
    "UserPortfolioMargin": [
        {"name": "hyperliquidChain", "type": "string"},
        {"name": "user", "type": "address"},
        {"name": "enabled", "type": "bool"},
        {"name": "nonce", "type": "uint64"},
    ],
    "CDeposit": [
        {"name": "hyperliquidChain", "type": "string"},
        {"name": "wei", "type": "uint64"},
        {"name": "nonce", "type": "uint64"},
    ],
    "CWithdraw": [
        {"name": "hyperliquidChain", "type": "string"},
        {"name": "wei", "type": "uint64"},
        {"name": "nonce", "type": "uint64"},
    ],
    "SendToEvmWithData": [
        {"name": "hyperliquidChain", "type": "string"},
        {"name": "token", "type": "string"},
        {"name": "amount", "type": "string"},
        {"name": "sourceDex", "type": "string"},
        {"name": "destinationRecipient", "type": "string"},
        {"name": "addressEncoding", "type": "string"},
        {"name": "destinationChainId", "type": "uint32"},
        {"name": "gasLimit", "type": "uint64"},
        {"name": "data", "type": "bytes"},
        {"name": "nonce", "type": "uint64"},
    ],
}
TS_FILES = {
    "LinkStakingUser": "linkStakingUser",
    "StakingLinkDisableTradingUser": "stakingLinkDisableTradingUser",
    "UserPortfolioMargin": "userPortfolioMargin",
    "CDeposit": "cDeposit",
    "CWithdraw": "cWithdraw",
    "SendToEvmWithData": "sendToEvmWithData",
}


def python_sign(fn):
    return lambda action, mainnet: fn(wallet, action, mainnet)


def generic_sign(types, primary_type):
    return lambda action, mainnet: S.sign_user_signed_action(wallet, action, types, primary_type, mainnet)


multi_sig_hash = action_hash({"type": "noop"}, None, NONCE, None)

# (Ruby constant, source, signer(action, mainnet), action fields without hyperliquidChain/signatureChainId)
CASES = [
    ("USD_SEND_TYPES", "python-sdk sign_usd_transfer_action", python_sign(S.sign_usd_transfer_action),
     {"type": "usdSend", "destination": DEST, "amount": "1.5", "time": NONCE}),
    ("SPOT_SEND_TYPES", "python-sdk sign_spot_transfer_action", python_sign(S.sign_spot_transfer_action),
     {"type": "spotSend", "destination": DEST, "token": "PURR:0xc4bf3f870c0e9465323c0b6ed28096c2",
      "amount": "100", "time": NONCE}),
    ("USD_CLASS_TRANSFER_TYPES", "python-sdk sign_usd_class_transfer_action",
     python_sign(S.sign_usd_class_transfer_action),
     {"type": "usdClassTransfer", "amount": "2.25", "toPerp": True, "nonce": NONCE}),
    ("WITHDRAW_TYPES", "python-sdk sign_withdraw_from_bridge_action", python_sign(S.sign_withdraw_from_bridge_action),
     {"type": "withdraw3", "destination": DEST, "amount": "10", "time": NONCE}),
    ("SEND_ASSET_TYPES", "python-sdk sign_send_asset_action", python_sign(S.sign_send_asset_action),
     {"type": "sendAsset", "destination": DEST, "sourceDex": "", "destinationDex": "spot", "token": "USDC",
      "amount": "3", "fromSubAccount": "", "nonce": NONCE}),
    ("APPROVE_AGENT_TYPES", "python-sdk sign_agent", python_sign(S.sign_agent),
     {"type": "approveAgent", "agentAddress": OTHER, "agentName": "parity", "nonce": NONCE}),
    ("APPROVE_BUILDER_FEE_TYPES", "python-sdk sign_approve_builder_fee", python_sign(S.sign_approve_builder_fee),
     {"type": "approveBuilderFee", "maxFeeRate": "0.001%", "builder": OTHER, "nonce": NONCE}),
    ("TOKEN_DELEGATE_TYPES", "python-sdk sign_token_delegate_action", python_sign(S.sign_token_delegate_action),
     {"type": "tokenDelegate", "validator": OTHER, "wei": 100_000_000, "isUndelegate": False, "nonce": NONCE}),
    ("USER_DEX_ABSTRACTION_TYPES", "python-sdk sign_user_dex_abstraction_action",
     python_sign(S.sign_user_dex_abstraction_action),
     {"type": "userDexAbstraction", "user": DEST, "enabled": True, "nonce": NONCE}),
    ("CONVERT_TO_MULTI_SIG_USER_TYPES", "python-sdk sign_convert_to_multi_sig_user_action",
     python_sign(S.sign_convert_to_multi_sig_user_action),
     {"type": "convertToMultiSigUser",
      "signers": '{"authorizedUsers":["0x0000000000000000000000000000000000000abc","%s"],"threshold":1}' % DEST,
      "nonce": NONCE}),
    ("USER_SET_ABSTRACTION_TYPES", "python-sdk sign_user_set_abstraction_action",
     python_sign(S.sign_user_set_abstraction_action),
     {"type": "userSetAbstraction", "user": DEST, "abstraction": "unifiedAccount", "nonce": NONCE}),
    ("MULTI_SIG_TYPES", "python-sdk sign_user_signed_action(MULTI_SIG_ENVELOPE_SIGN_TYPES)",
     generic_sign(S.MULTI_SIG_ENVELOPE_SIGN_TYPES, "HyperliquidTransaction:SendMultiSig"),
     {"multiSigActionHash": multi_sig_hash, "nonce": NONCE}),
    ("LINK_STAKING_USER_TYPES", "LinkStakingUser", None,
     {"user": DEST, "isFinalize": True, "nonce": NONCE}),
    ("STAKING_LINK_DISABLE_TRADING_USER_TYPES", "StakingLinkDisableTradingUser", None,
     {"tradingUser": DEST, "nonce": NONCE}),
    ("USER_PORTFOLIO_MARGIN_TYPES", "UserPortfolioMargin", None,
     {"user": DEST, "enabled": False, "nonce": NONCE}),
    ("C_DEPOSIT_TYPES", "CDeposit", None, {"wei": 250_000_000, "nonce": NONCE}),
    ("C_WITHDRAW_TYPES", "CWithdraw", None, {"wei": 125_000_000, "nonce": NONCE}),
    ("SEND_TO_EVM_WITH_DATA_TYPES", "SendToEvmWithData", None,
     {"token": "USDC", "amount": "1", "sourceDex": "spot", "destinationRecipient": OTHER,
      "addressEncoding": "hex", "destinationChainId": 998, "gasLimit": 200000, "data": "0xdeadbeef",
      "nonce": NONCE}),
]


def to_json_value(value):
    return "0x" + value.hex() if isinstance(value, (bytes, bytearray)) else value


vectors = []
for constant, source, signer, action in CASES:
    if signer is None:
        primary_type = "HyperliquidTransaction:" + source
        signer = generic_sign(TS_TABLES[source], primary_type)
        source = TS_SOURCE.format(TS_FILES[source])
    for mainnet in (True, False):
        del _signed_payloads[:]
        sig = signer(dict(action), mainnet)
        (payload,) = _signed_payloads
        primary_type = payload["primaryType"]
        types = payload["types"][primary_type]
        chain = payload["message"]["hyperliquidChain"]
        message = {f["name"]: to_json_value(payload["message"][f["name"]]) for f in types
                   if f["name"] != "hyperliquidChain"}
        vectors.append(
            {
                "constant": constant,
                "source": source,
                "primary_type": primary_type,
                "types": types,
                "message": message,
                "chain": chain,
                "signature_chain_id": payload["message"]["signatureChainId"],
                **pad_sig(sig),
            }
        )

write_fixture(
    outdir_from_argv(),
    "eip712_user_signed_vectors.json",
    {"source": PYTHON_SDK, "private_key": PARITY_KEY, "vectors": vectors},
)
