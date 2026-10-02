"""Shared helpers for the machine-readable parity capture scripts (not a capture script itself)."""
import json
import os
import sys

# Key used by the upstream hyperliquid-python-sdk tests/signing_test.py vectors.
PARITY_KEY = "0x0123456789012345678901234567890123456789012345678901234567890123"

PYTHON_SDK = "hyperliquid-python-sdk 0.24.0 (2fdb18f9517675ea03695a0962bd19eece9c83f0)"


def pad_sig(sig):
    """Python's `to_hex` strips leading zeros from r/s; Ruby always emits 0x + 64 hex chars."""
    return {"r": "0x" + sig["r"][2:].rjust(64, "0"), "s": "0x" + sig["s"][2:].rjust(64, "0"), "v": sig["v"]}


def compact(obj):
    """Compact JSON preserving dict insertion order (== msgpack key order == bytes hashed)."""
    return json.dumps(obj, separators=(",", ":"))


def outdir_from_argv():
    if len(sys.argv) != 2:
        sys.exit(f"usage: {os.path.basename(sys.argv[0])} OUTDIR")
    return sys.argv[1]


def write_fixture(outdir, relpath, obj):
    """Deterministic pretty JSON; dict keys sorted (order-sensitive payloads are stored as compact strings)."""
    path = os.path.join(outdir, relpath)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.write("\n")
