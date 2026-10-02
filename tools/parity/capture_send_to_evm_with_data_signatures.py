"""
Capture EIP-712 signatures for two fixtures:
  Fixture A: data = '0x' (empty payload)
  Fixture B: data = '0xdeadbeef' (non-empty payload — exercises bytes hashing)

Verifies that the string '0x...' form and raw-bytes form produce identical signatures
(both are valid representations of the same bytes value to eth_account).
"""
from eth_account import Account
from eth_account.messages import encode_typed_data

PRIVATE_KEY = "0x" + "11" * 32
NONCE = 1700000000000
USER_SIGNED_CHAIN_ID = 421614

DOMAIN = {
    "name": "HyperliquidSignTransaction",
    "version": "1",
    "chainId": USER_SIGNED_CHAIN_ID,
    "verifyingContract": "0x0000000000000000000000000000000000000000",
}

TYPES = {
    "EIP712Domain": [
        {"name": "name", "type": "string"},
        {"name": "version", "type": "string"},
        {"name": "chainId", "type": "uint256"},
        {"name": "verifyingContract", "type": "address"},
    ],
    "HyperliquidTransaction:SendToEvmWithData": [
        {"name": "hyperliquidChain",     "type": "string"},
        {"name": "token",                "type": "string"},
        {"name": "amount",               "type": "string"},
        {"name": "sourceDex",            "type": "string"},
        {"name": "destinationRecipient", "type": "string"},
        {"name": "addressEncoding",      "type": "string"},
        {"name": "destinationChainId",   "type": "uint32"},
        {"name": "gasLimit",             "type": "uint64"},
        {"name": "data",                 "type": "bytes"},
        {"name": "nonce",                "type": "uint64"},
    ],
}

BASE_MESSAGE = {
    "hyperliquidChain": "Mainnet",
    "token": "USDC",
    "amount": "1",
    "sourceDex": "spot",
    "destinationRecipient": "0x0000000000000000000000000000000000000001",
    "addressEncoding": "hex",
    "destinationChainId": 998,
    "gasLimit": 200000,
    "nonce": NONCE,
}


def sign(data_value, label):
    msg = {**BASE_MESSAGE, "data": data_value}
    typed_data = {
        "types": TYPES,
        "primaryType": "HyperliquidTransaction:SendToEvmWithData",
        "domain": DOMAIN,
        "message": msg,
    }
    signable = encode_typed_data(full_message=typed_data)
    signed = Account.sign_message(signable, private_key=PRIVATE_KEY)
    print(f"--- {label} ---")
    print(f"  data input          = {data_value!r}")
    print(f"  messageHash         = 0x{signable.body.hex()}")
    print(f"  r                   = 0x{signed.r:064x}")
    print(f"  s                   = 0x{signed.s:064x}")
    print(f"  v                   = {signed.v}")
    print()


print(f"signer_address  = {Account.from_key(PRIVATE_KEY).address}")
print(f"private_key     = {PRIVATE_KEY}")
print(f"chainId         = {USER_SIGNED_CHAIN_ID} (0x{USER_SIGNED_CHAIN_ID:x})")
print(f"nonce           = {NONCE}")
print(f"base message    = {BASE_MESSAGE}")
print()

sign(b"", "Fixture A: empty bytes b''")
sign("0x", "Fixture A': string '0x' (must match Fixture A)")
sign(b"\xde\xad\xbe\xef", "Fixture B: non-empty bytes b'\\xde\\xad\\xbe\\xef'")
sign("0xdeadbeef", "Fixture B': string '0xdeadbeef' (must match Fixture B)")
