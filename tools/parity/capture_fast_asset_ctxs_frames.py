#!/usr/bin/env python3
"""Read-only capture of real `fastAssetCtxs` WS frames (public subscription, no keys, no /exchange).

Usage: <venv from tools/parity/requirements.txt>/bin/python tools/parity/capture_fast_asset_ctxs_frames.py \
  [mainnet|testnet] [n_frames]
Live network probe: NOT run by regenerate.sh (output depends on live market data).

Prints, per frame: raw envelope (truncated), channel, data type, base64 length,
decompressed length, number of coins, sample entries, and inter-frame timing.
Also prints the subscriptionResponse / unsubscribe ack envelopes verbatim and
writes the first data frame + a small update frame to /tmp/fast_asset_ctxs_frames.json.
"""
import base64
import json
import sys
import time
import zlib

import websocket

URLS = {
    "mainnet": "wss://api.hyperliquid.xyz/ws",
    "testnet": "wss://api.hyperliquid-testnet.xyz/ws",
}


def decode(b64):
    raw = base64.b64decode(b64)
    return zlib.decompress(raw, wbits=-15)


def main():
    net = sys.argv[1] if len(sys.argv) > 1 else "mainnet"
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    ws = websocket.create_connection(URLS[net], timeout=20)
    ws.send(json.dumps({"method": "subscribe", "subscription": {"type": "fastAssetCtxs"}}))
    frames = []
    t0 = time.time()
    while len(frames) < n:
        msg = ws.recv()
        env = json.loads(msg)
        ch = env.get("channel")
        if ch != "fastAssetCtxs":
            print(f"[{time.time()-t0:6.3f}s] non-data envelope: {msg[:400]}")
            continue
        data = env["data"]
        plain = decode(data)
        obj = json.loads(plain)
        print(
            f"[{time.time()-t0:6.3f}s] keys={list(env.keys())} data_type={type(data).__name__} "
            f"b64_len={len(data)} raw_len={len(plain)} coins={len(obj)} type={type(obj).__name__}"
        )
        sample = dict(list(obj.items())[:4])
        print("   sample:", json.dumps(sample))
        frames.append({"t": time.time() - t0, "raw_envelope": msg, "decoded": obj})
    ws.send(json.dumps({"method": "unsubscribe", "subscription": {"type": "fastAssetCtxs"}}))
    ws.settimeout(5)
    try:
        for _ in range(20):
            msg = ws.recv()
            if '"subscriptionResponse"' in msg:
                print("unsubscribe ack:", msg[:400])
                break
    except Exception as e:  # noqa: BLE001
        print("no unsub ack:", e)
    ws.close()
    with open("/tmp/fast_asset_ctxs_frames.json", "w") as f:
        json.dump(frames, f)
    # key/value type census across all frames
    kinds = {}
    for fr in frames:
        for coin, ctx in fr["decoded"].items():
            for k, v in ctx.items():
                kinds.setdefault(k, set()).add(type(v).__name__)
    print("field type census:", {k: sorted(v) for k, v in kinds.items()})


if __name__ == "__main__":
    main()
