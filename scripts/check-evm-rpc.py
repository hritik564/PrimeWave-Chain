#!/usr/bin/env python3
"""Read-only Subnet-EVM API smoke check; no keys or third-party dependencies."""
import argparse
import json
import re
import sys
import urllib.request


def quantity(value):
    if not isinstance(value, str) or not re.fullmatch(r"0x(?:0|[1-9a-fA-F][0-9a-fA-F]*)", value):
        raise ValueError("invalid RPC hex quantity")
    return int(value, 16)


def check(url, chain_id=73571):
    def call(method, params):
        request = urllib.request.Request(
            url, json.dumps(dict(jsonrpc="2.0", id=1, method=method, params=params)).encode(),
            {"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            reply = json.load(response)
        if (not isinstance(reply, dict) or reply.get("jsonrpc") != "2.0"
                or type(reply.get("id")) is not int or reply["id"] != 1
                or "error" in reply or "result" not in reply):
            raise ValueError(f"{method}: invalid or error JSON-RPC response")
        return reply["result"]

    if quantity(call("eth_chainId", [])) != chain_id:
        raise ValueError("eth_chainId: unexpected chain identity")
    height = call("eth_blockNumber", [])
    quantity(height)
    block = call("eth_getBlockByNumber", [height, False])
    if (not isinstance(block, dict) or quantity(block.get("number")) != quantity(height)
            or not isinstance(block.get("hash"), str)
            or not re.fullmatch(r"0x[0-9a-fA-F]{64}", block["hash"])):
        raise ValueError("eth_getBlockByNumber: invalid block")
    quantity(call("eth_getBalance", ["0x0000000000000000000000000000000000000000", height]))
    return height


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rpc_url", help="Explicit endpoint for the existing blockchain")
    args = parser.parse_args()
    try:
        height = check(args.rpc_url)
        print(f"PASS: all four Ethereum RPC methods; Chain ID 73571; block {height}")
    except (ValueError, OSError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
