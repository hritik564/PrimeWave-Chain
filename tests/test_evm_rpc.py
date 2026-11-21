"""Offline regression tests. Run: python3 -m unittest discover -s tests -p 'test_*.py'."""
import ast
import base64
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("rpc", ROOT / "scripts/check-evm-rpc.py")
rpc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rpc)
APIS = ["eth", "eth-filter", "internal-blockchain", "net", "web3"]


class RpcTests(unittest.TestCase):
    def run_check(self, overrides=None):
        results = {"eth_chainId": "0x11f63", "eth_blockNumber": "0x0",
                   "eth_getBlockByNumber": {"number": "0x0", "hash": "0x" + "ab" * 32},
                   "eth_getBalance": "0x0"}
        seen = []

        def respond(request, timeout):
            body = json.loads(request.data)
            method = body["method"]
            seen.append((method, body["params"]))
            reply = dict(jsonrpc="2.0", id=1, result=results[method])
            reply.update((overrides or {}).get(method, {}))
            return io.BytesIO(json.dumps(reply).encode())

        with patch.object(rpc.urllib.request, "urlopen", side_effect=respond):
            self.assertEqual(rpc.check("http://127.0.0.1:9656/ext/bc/test/rpc"), "0x0")
        return seen

    def test_genesis_and_zero_balance_are_valid(self):
        self.assertEqual(self.run_check(), [
            ("eth_chainId", []), ("eth_blockNumber", []),
            ("eth_getBlockByNumber", ["0x0", False]),
            ("eth_getBalance", ["0x" + "0" * 40, "0x0"])])

    def test_json_rpc_errors_even_with_http_success(self):
        for method in ("eth_chainId", "eth_blockNumber", "eth_getBlockByNumber", "eth_getBalance"):
            with self.subTest(method=method), self.assertRaises(ValueError):
                self.run_check({method: {"error": {"code": -32601, "message": "not available"}}})

    def test_bad_results_and_envelopes(self):
        for method, reply in [
            ("eth_chainId", {"result": "0x4d"}),
            ("eth_blockNumber", {"result": "0x"}),
            ("eth_getBlockByNumber", {"result": None}),
            ("eth_getBlockByNumber", {"result": {"number": "0x1", "hash": "0x" + "ab" * 32}}),
            ("eth_getBalance", {"result": None}),
            ("eth_chainId", {"id": 2}),
            ("eth_chainId", {"jsonrpc": "1.0"}),
        ]:
            with self.subTest(method=method, reply=reply), self.assertRaises(ValueError):
                self.run_check({method: reply})

    def test_transport_failure(self):
        with patch.object(rpc.urllib.request, "urlopen", side_effect=OSError("offline")):
            with self.assertRaises(OSError):
                rpc.check("http://127.0.0.1:1")


class GeneratorTests(unittest.TestCase):
    def test_actual_flags_generator_preserves_other_chains(self):
        source = (ROOT / "scripts/start-local.sh").read_text()
        code = source.split("python3 << PYEOF\n", 1)[1].split("\nPYEOF", 1)[0]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "flags.json"
            other = {"other-chain": {"Config": "untouched", "Upgrade": None}}
            path.write_text(json.dumps({"chain-config-content": base64.b64encode(json.dumps(other).encode()).decode()}))
            for name, value in {"$PRIMEWAVE_SUBNET_ID": "test-subnet", "$PRIMEWAVE_BLOCKCHAIN_ID": "test-chain",
                                "$FLAGS_JSON_PENDING": str(path)}.items():
                code = code.replace(name, value)
            with patch.dict("os.environ", {"PRIMEWAVE_ISOLATION_ROOT": ""}):
                exec(compile(code, "flags-generator", "exec"), {})
            flags = json.loads(path.read_text())
            chains = json.loads(base64.b64decode(flags["chain-config-content"]))
            self.assertEqual(chains["other-chain"], other["other-chain"])
            config = json.loads(base64.b64decode(chains["test-chain"]["Config"]))
            self.assertEqual(config["eth-apis"], APIS)
            self.assertEqual(json.loads((ROOT / "chain/config/chain-config.json").read_text())["eth-apis"], APIS)

    def test_startup_python_compiles(self):
        source = (ROOT / "scripts/start-local.sh").read_text()
        code = source.split("python3 << PYEOF2\n", 1)[1].split("\nPYEOF2", 1)[0]
        ast.parse(code)


if __name__ == "__main__":
    unittest.main()
