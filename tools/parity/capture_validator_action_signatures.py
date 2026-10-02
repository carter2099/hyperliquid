#!/usr/bin/env python3
"""
Capture L1 action-hash + signature fixtures for the validator-operator action family
(CSignerAction, CValidatorAction, validatorL1Stream) from the official Python SDK.

Drives the REAL Python SDK `Exchange.c_signer_*` / `c_validator_*` methods end to end
(action construction + sign_l1_action), with `_post_action` intercepted so nothing is
sent. `validatorL1Stream` is not implemented in the Python SDK, so its action is built
by hand per TS `validatorL1Stream.ts` / GitBook docs and signed with Python's
`sign_l1_action` (the L1 hash reference).

Reference: hyperliquid-python-sdk master 2fdb18f95176 (PyPI 0.24.0).
Usage:
    tools/parity/regenerate.sh OUTDIR   # stdout -> OUTDIR/legacy/capture_validator_action_signatures.txt
"""
import eth_account
import hyperliquid.exchange as hl_exchange
from hyperliquid.exchange import Exchange
from hyperliquid.utils.constants import MAINNET_API_URL, TESTNET_API_URL
from hyperliquid.utils.signing import action_hash, sign_l1_action

PRIVATE_KEY = "0x1111111111111111111111111111111111111111111111111111111111111111"
NONCE = 1_700_000_000_000
EXPIRES_AFTER = 1_700_000_060_000

wallet = eth_account.Account.from_key(PRIVATE_KEY)

# Pin the nonce used inside the SDK methods.
hl_exchange.get_timestamp_ms = lambda: NONCE


def make_exchange(base_url, expires_after=None):
    ex = Exchange.__new__(Exchange)  # skip __init__ (it fetches meta over the network)
    ex.wallet = wallet
    ex.base_url = base_url
    ex.vault_address = None
    ex.account_address = None
    ex.expires_after = expires_after
    ex._post_action = lambda action, signature, nonce: {"action": action, "signature": signature, "nonce": nonce}
    return ex


def report(label, captured, expires_after=None):
    h = action_hash(captured["action"], None, captured["nonce"], expires_after)
    sig = captured["signature"]
    print(f"=== {label} ===")
    print(f"  action:     {captured['action']}")
    print(f"  actionHash: 0x{h.hex()}")
    print(f"  r: {sig['r']}")
    print(f"  s: {sig['s']}")
    print(f"  v: {sig['v']}")
    print()


main = make_exchange(MAINNET_API_URL)
test = make_exchange(TESTNET_API_URL)
main_exp = make_exchange(MAINNET_API_URL, EXPIRES_AFTER)

print("Signer address (sanity check, must match Ruby):", wallet.address)
print()

report("F1 c_signer_jail_self (mainnet)", main.c_signer_jail_self())
report("F2 c_signer_unjail_self (mainnet)", main.c_signer_unjail_self())
report("F3 c_signer_jail_self (testnet)", test.c_signer_jail_self())
report("F4 c_signer_jail_self (mainnet, expires_after)", main_exp.c_signer_jail_self(), EXPIRES_AFTER)
report(
    "F5 c_validator_register (mainnet)",
    main.c_validator_register(
        node_ip="1.2.3.4",
        name="TestValidator",
        description="A test validator",
        delegations_disabled=True,
        commission_bps=500,
        signer="0x0000000000000000000000000000000000000001",
        unjailed=False,
        initial_wei=1_000_000_000_000,
    ),
)
report(
    "F6 c_validator_change_profile all-nil except unjailed (mainnet)",
    main.c_validator_change_profile(
        node_ip=None,
        name=None,
        description=None,
        unjailed=True,
        disable_delegations=None,
        commission_bps=None,
        signer=None,
    ),
)
report(
    "F7 c_validator_change_profile all set (mainnet)",
    main.c_validator_change_profile(
        node_ip="5.6.7.8",
        name="Renamed",
        description="Updated description",
        unjailed=False,
        disable_delegations=False,
        commission_bps=250,
        signer="0x0000000000000000000000000000000000000002",
    ),
)
report("F8 c_validator_unregister (mainnet)", main.c_validator_unregister())

# validatorL1Stream: not in the Python SDK. Hand-built per TS schema / docs, signed with
# Python's sign_l1_action (same primitive the SDK uses for every L1 action).
l1_stream_action = {"type": "validatorL1Stream", "riskFreeRate": "0.05"}
l1_stream_sig = sign_l1_action(wallet, l1_stream_action, None, NONCE, None, True)
report("F9 validatorL1Stream riskFreeRate 0.05 (mainnet)", {"action": l1_stream_action, "signature": l1_stream_sig, "nonce": NONCE})
