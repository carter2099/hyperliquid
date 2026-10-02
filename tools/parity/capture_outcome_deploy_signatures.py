#!/usr/bin/env python3
"""Capture L1 action-hash + signature parity fixtures for the HIP-4 deployer family
(`activateOutcomeDeployer` enum form + `outcomeDeploy` operation variants).

Neither the official Python SDK nor the TS SDK implements these actions; the
actions below are hand-built in the exact key order observed in accepted
mainnet/testnet transactions (explorer `userDetails`) and in the GitBook
hip-4-deployer-actions examples. The Python SDK is used only as the reference
implementation of the L1 signing primitive (`action_hash` + `sign_l1_action`).

Recreate:
    tools/parity/regenerate.sh OUTDIR   # venv from tools/parity/requirements.txt;
                                        # stdout -> OUTDIR/legacy/capture_outcome_deploy_signatures.txt

Captured 2026-10-01 with hyperliquid-python-sdk 0.24.0 (repo HEAD 2fdb18f95176).
"""

import json

import eth_account
from hyperliquid.utils.signing import action_hash, sign_l1_action

KEY = "0x1111111111111111111111111111111111111111111111111111111111111111"
NONCE = 1_700_000_000_000
EXPIRES_AFTER = 1_700_000_060_000
SUB = "0x0000000000000000000000000000000000000abc"

ACTIONS = {
    "activate": {"type": "activateOutcomeDeployer", "activate": {"venueName": "ab"}},
    "deactivate": {"type": "activateOutcomeDeployer", "deactivate": None},
    "registerStandalone": {
        "type": "outcomeDeploy",
        "venue": "ab",
        "operation": {
            "registerStandaloneOutcomeFromTemplate": {
                "id": "abc",
                "keywordToValue": [["expiry", "20260801-0600"], ["target", "100"], ["underlying", "ABC"]],
                "deployerFeeScale": "1",
            }
        },
    },
    "registerQuestion": {
        "type": "outcomeDeploy",
        "venue": "ab",
        "operation": {
            "registerQuestionFromTemplate": {
                "questionTemplateInstance": {
                    "id": "abc",
                    "keywordToValue": [["expiry", "20260801-1830"]],
                    "deployerFeeScale": "1",
                },
                "namedOutcomeTemplateInstances": [
                    {"id": "abc-outcome", "keywordToValue": [["choice", "A"]]},
                    {"id": "abc-outcome", "keywordToValue": [["choice", "B"]]},
                    {"id": "abc-other", "keywordToValue": []},
                ],
            }
        },
    },
    "registerAndAssociate": {
        "type": "outcomeDeploy",
        "venue": "ab",
        "operation": {
            "registerAndAssociateNamedOutcomeFromTemplate": {
                "question": 3,
                "namedOutcomeTemplateInstance": {"id": "abc-outcome", "keywordToValue": [["choice", "C"]]},
            }
        },
    },
    "settleOutcome": {
        "type": "outcomeDeploy",
        "venue": "ab",
        "operation": {
            "settleOutcome": {
                "outcome": 7,
                "settleFraction": "1",
                "details": "",
                "nameAndDescription": ["template:abc", "expiry:20260801-0600|target:100|underlying:ABC"],
                "sideNames": ["template:Over", "template:Under"],
            }
        },
    },
    "settleQuestion": {
        "type": "outcomeDeploy",
        "venue": "ab",
        "operation": {
            "settleQuestion2": {
                "question": 3,
                "outcomeSettlements": [
                    {
                        "outcome": 11,
                        "settleFraction": "1",
                        "details": "",
                        "nameAndDescription": ["template:abc-outcome", "choice:A"],
                        "sideNames": ["Yes", "No"],
                    },
                    {
                        "outcome": 12,
                        "settleFraction": "0",
                        "details": "",
                        "nameAndDescription": ["template:abc-outcome", "choice:B"],
                        "sideNames": ["Yes", "No"],
                    },
                ],
                "nameAndDescription": ["template:abc", "expiry:20260801-1830"],
            }
        },
    },
    "setSubDeployers": {
        "type": "outcomeDeploy",
        "venue": "ab",
        "operation": {
            "setSubDeployers": [
                {"variant": "registerStandaloneOutcomeFromTemplate", "user": SUB, "allowed": True},
                {"variant": "settleQuestion", "user": SUB, "allowed": False},
            ]
        },
    },
}


def capture(expires_after=None):
    wallet = eth_account.Account.from_key(KEY)
    out = {}
    for name, action in ACTIONS.items():
        h = action_hash(action, None, NONCE, expires_after)
        sig = sign_l1_action(wallet, action, None, NONCE, expires_after, False)  # testnet (source 'b')
        out[name] = {"actionHash": "0x" + h.hex(), "r": sig["r"], "s": sig["s"], "v": sig["v"]}
    return out


def third_party_cross_check():
    """Reproduce Outcome-xyz/hip4@c7e3b38 tests/parity/deployer-vectors.json l1ActionHash values
    (venue 'zzz', nonce 1755530000000) to prove this harness matches an independent encoder."""
    nonce = 1755530000000
    act = {"type": "activateOutcomeDeployer", "activate": {"venueName": "zzz"}}
    deact = {"type": "activateOutcomeDeployer", "deactivate": None}
    expect = {
        "activate": "0xb6527b4ba1d06d7884f85a2f0c165fde59becd3bc7f8725bc0f481e3a2c7f1cd",
        "deactivate": "0xe91d6e3ccf382a7ae37e78d8e6dadf2f168cbedee74c0f2b984b2b8561bc008f",
    }
    got = {
        "activate": "0x" + action_hash(act, None, nonce, None).hex(),
        "deactivate": "0x" + action_hash(deact, None, nonce, None).hex(),
    }
    assert got == expect, (got, expect)
    return "ok"


if __name__ == "__main__":
    wallet = eth_account.Account.from_key(KEY)
    print(json.dumps({
        "signer": wallet.address,
        "nonce": NONCE,
        "is_mainnet": False,
        "thirdPartyCrossCheck": third_party_cross_check(),
        "noExpiry": capture(),
        "withExpiresAfter": {"expiresAfter": EXPIRES_AFTER, **{"settleOutcome": capture(EXPIRES_AFTER)["settleOutcome"]}},
    }, indent=2))
