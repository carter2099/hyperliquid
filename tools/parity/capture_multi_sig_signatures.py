#!/usr/bin/env python3
"""
Capture multi_sig signature fixtures for the Ruby SDK byte-parity regression tests.

Run with: tools/parity/regenerate.sh OUTDIR (stdout -> OUTDIR/legacy/capture_multi_sig_signatures.txt)

Outputs:
  - multiSigActionHash for two inner actions (L1 'noop' and a more complex order)
  - Outer (submitter) signature for each
  - Co-signer L1 signature for the order action
  - Co-signer user-signed signature for a sendAsset inner action
"""
import json

import msgpack
from eth_account import Account
from eth_account.messages import encode_typed_data
from eth_utils import keccak


PRIVATE_KEY = "0x1111111111111111111111111111111111111111111111111111111111111111"
NONCE = 1_700_000_000_000
HYPERLIQUID_CHAIN = "Mainnet"  # mainnet for fixtures (testnet only differs in this string)
SIGNATURE_CHAIN_ID = "0x66eee"

acct = Account.from_key(PRIVATE_KEY)
SIGNER_ADDR = acct.address  # 0x19E7E376E7C213B7E7e7e46cc70A5dD086DAff2A
MULTI_SIG_USER = "0x0000000000000000000000000000000000000005"
OUTER_SIGNER = SIGNER_ADDR.lower()  # submitter


# Domain for user-signed actions (matches Signing::EIP712.user_signed_domain)
USER_DOMAIN = {
    "name": "HyperliquidSignTransaction",
    "version": "1",
    "chainId": 421_614,
    "verifyingContract": "0x0000000000000000000000000000000000000000",
}

# Domain for L1 actions
L1_DOMAIN = {
    "name": "Exchange",
    "version": "1",
    "chainId": 1337,
    "verifyingContract": "0x0000000000000000000000000000000000000000",
}


def action_hash(action, vault_address, nonce, expires_after):
    """Mirror of Python SDK signing.py action_hash."""
    data = msgpack.packb(action)
    data += nonce.to_bytes(8, "big")
    if vault_address is None:
        data += b"\x00"
    else:
        data += b"\x01"
        data += bytes.fromhex(vault_address[2:] if vault_address.startswith("0x") else vault_address)
    if expires_after is not None:
        data += b"\x00"
        data += expires_after.to_bytes(8, "big")
    return keccak(data)


def sig_to_dict(signed):
    return {
        "r": "0x" + format(signed.r, "064x"),
        "s": "0x" + format(signed.s, "064x"),
        "v": signed.v,
    }


def sign_outer_envelope(envelope, nonce, vault_address=None, expires_after=None):
    """Submitter's outer signature over multi-sig envelope."""
    without_type = {k: v for k, v in envelope.items() if k != "type"}
    msg_hash = action_hash(without_type, vault_address, nonce, expires_after)
    typed = {
        "domain": USER_DOMAIN,
        "types": {
            "HyperliquidTransaction:SendMultiSig": [
                {"name": "hyperliquidChain",   "type": "string"},
                {"name": "multiSigActionHash", "type": "bytes32"},
                {"name": "nonce",              "type": "uint64"},
            ],
        },
        "primaryType": "HyperliquidTransaction:SendMultiSig",
        "message": {
            "hyperliquidChain": HYPERLIQUID_CHAIN,
            "multiSigActionHash": msg_hash,
            "nonce": nonce,
        },
    }
    encoded = encode_typed_data(full_message=typed)
    signed = acct.sign_message(encoded)
    return msg_hash, sig_to_dict(signed)


def sign_co_signer_l1(inner_action, multi_sig_user, outer_signer, nonce, vault_address=None, expires_after=None):
    """Co-signer L1 phantom-agent signature over [multi_sig_user, outer_signer, action]."""
    envelope = [multi_sig_user.lower(), outer_signer.lower(), inner_action]
    h = action_hash(envelope, vault_address, nonce, expires_after)
    phantom = {"source": "a", "connectionId": h}  # mainnet → 'a'
    typed = {
        "domain": L1_DOMAIN,
        "types": {
            "Agent": [
                {"name": "source",       "type": "string"},
                {"name": "connectionId", "type": "bytes32"},
            ],
        },
        "primaryType": "Agent",
        "message": phantom,
    }
    encoded = encode_typed_data(full_message=typed)
    signed = acct.sign_message(encoded)
    return h, sig_to_dict(signed)


def sign_co_signer_user_signed(inner_action, primary_type, sign_types, multi_sig_user, outer_signer):
    """Co-signer user-signed: enriches inner action with payloadMultiSigUser + outerSigner."""
    enriched_action = {
        **inner_action,
        "payloadMultiSigUser": multi_sig_user.lower(),
        "outerSigner": outer_signer.lower(),
    }
    enriched_action["hyperliquidChain"] = HYPERLIQUID_CHAIN
    enriched_action["signatureChainId"] = SIGNATURE_CHAIN_ID
    enriched_types = []
    for f in sign_types:
        enriched_types.append(f)
        if f["name"] == "hyperliquidChain":
            enriched_types.append({"name": "payloadMultiSigUser", "type": "address"})
            enriched_types.append({"name": "outerSigner",         "type": "address"})
    typed = {
        "domain": USER_DOMAIN,
        "types": {primary_type: enriched_types},
        "primaryType": primary_type,
        "message": enriched_action,
    }
    encoded = encode_typed_data(full_message=typed)
    signed = acct.sign_message(encoded)
    return sig_to_dict(signed)


# --- Fixture A: outer signer over a multi-sig envelope wrapping a 'noop' L1 inner action ---
inner_noop = {"type": "noop"}
envelope_a = {
    "type": "multiSig",
    "signatureChainId": SIGNATURE_CHAIN_ID,
    "signatures": [],  # no co-signers in this fixture (just exercise the outer flow)
    "payload": {
        "multiSigUser": MULTI_SIG_USER.lower(),
        "outerSigner": OUTER_SIGNER,
        "action": inner_noop,
    },
}
hash_a, sig_a = sign_outer_envelope(envelope_a, NONCE)

# --- Fixture B: outer signer with a non-trivial inner action + one populated co-signer signature ---
inner_order = {
    "type": "order",
    "orders": [{"a": 4, "b": True, "p": "1100", "s": "0.2", "r": False, "t": {"limit": {"tif": "Gtc"}}}],
    "grouping": "na",
}
# Co-signer L1 signature over the inner order
hash_l1_b, sig_l1_b = sign_co_signer_l1(inner_order, MULTI_SIG_USER, OUTER_SIGNER, NONCE)
# Build envelope with the co-signer sig populated
envelope_b = {
    "type": "multiSig",
    "signatureChainId": SIGNATURE_CHAIN_ID,
    "signatures": [sig_l1_b],
    "payload": {
        "multiSigUser": MULTI_SIG_USER.lower(),
        "outerSigner": OUTER_SIGNER,
        "action": inner_order,
    },
}
hash_b, sig_b = sign_outer_envelope(envelope_b, NONCE)

# --- Fixture C: co-signer user-signed over a sendAsset inner action ---
send_asset_action = {
    "type": "sendAsset",
    "destination": "0x0000000000000000000000000000000000000000",
    "sourceDex": "",
    "destinationDex": "",
    "token": "USDC",
    "amount": "100.0",
    "fromSubAccount": "",
    "nonce": NONCE,
}
send_asset_types = [
    {"name": "hyperliquidChain", "type": "string"},
    {"name": "destination",      "type": "string"},
    {"name": "sourceDex",        "type": "string"},
    {"name": "destinationDex",   "type": "string"},
    {"name": "token",            "type": "string"},
    {"name": "amount",           "type": "string"},
    {"name": "fromSubAccount",   "type": "string"},
    {"name": "nonce",            "type": "uint64"},
]
sig_c = sign_co_signer_user_signed(
    send_asset_action,
    "HyperliquidTransaction:SendAsset",
    send_asset_types,
    MULTI_SIG_USER,
    OUTER_SIGNER,
)


print("Signer address (sanity check, must match Ruby):", SIGNER_ADDR)
print()
print("=== Fixture A: outer signer over noop inner action, no co-signers ===")
print(f"  multiSigActionHash: 0x{hash_a.hex()}")
print(f"  r: {sig_a['r']}")
print(f"  s: {sig_a['s']}")
print(f"  v: {sig_a['v']}")
print()
print("=== Fixture B: outer signer over order inner action, with one co-signer L1 sig populated ===")
print(f"  co-signer L1 hash:   0x{hash_l1_b.hex()}")
print(f"  co-signer L1 r: {sig_l1_b['r']}")
print(f"  co-signer L1 s: {sig_l1_b['s']}")
print(f"  co-signer L1 v: {sig_l1_b['v']}")
print(f"  outer multiSigActionHash: 0x{hash_b.hex()}")
print(f"  outer r: {sig_b['r']}")
print(f"  outer s: {sig_b['s']}")
print(f"  outer v: {sig_b['v']}")
print()
print("=== Fixture C: co-signer user-signed over sendAsset inner action ===")
print(f"  r: {sig_c['r']}")
print(f"  s: {sig_c['s']}")
print(f"  v: {sig_c['v']}")
