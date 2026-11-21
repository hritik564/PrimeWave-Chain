# Existing pw-demo-04 startup and PWUSD demo

No live startup or deployment has been executed from this checkout.

## Integration handoff sequence

Run from the existing Replit checkout root. Set `HANDOFF_COMMIT` to the pushed
commit supplied with the handoff. Do not clone into, move, or clean the runtime.
This synchronization block stops on a dirty checkout, another branch, a different
remote tip, or a non-fast-forward history. It does not run repository Git hooks.

```bash
export HANDOFF_COMMIT='<pushed commit hash>'
bash <<'SYNC'
set -euo pipefail
test "$(git remote get-url origin)" = 'https://github.com/hritik564/PrimeWave-Chain'
test "$(git branch --show-current)" = main
test -z "$(git status --porcelain)"
git fetch origin main
test "$(git rev-parse origin/main)" = "$HANDOFF_COMMIT"
git -c core.hooksPath=/dev/null merge --ff-only origin/main
test "$(git rev-parse HEAD)" = "$HANDOFF_COMMIT"
python3 scripts/verify-pw-demo-04.py --dry-run --stopped
SYNC
```

Only `.local-networks/pw-demo-04` is confirmed by the handoff. Its actual flags
location, node ID, database mapping, metadata schema and HTTP port have not been
inspected in Replit. The utility discovers one flags file under the candidate
`cli-home/local/*/NodeID-*/flags.json` layout and refuses otherwise. Do not create
replacement metadata or invent historical hashes/inodes to bypass refusal.

After dry-run succeeds and existing-only startup is approved:

```bash
python3 scripts/verify-pw-demo-04.py --start-existing-and-verify --approve-start
```

Then derive the RPC URL from the same verified saved flags instead of guessing
its port, compile, and prepare disposable wallets:

```bash
bash <<'PREPARE'
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
RPC_URL=$(python3 - <<'PYRPC'
import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('demo', 'scripts/verify-pw-demo-04.py')
demo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(demo)
import json
candidates = list(Path('.local-networks/pw-demo-04/cli-home').glob('local/*/NodeID-*/flags.json'))
if len(candidates) != 1:
    raise SystemExit('Expected one existing flags file')
flags = json.loads(demo.existing(candidates[0].absolute(), Path.cwd()).read_text())
port = flags.get('http-port')
if not str(port).isdigit() or not 1024 <= int(port) <= 65535:
    raise SystemExit('Invalid saved HTTP port')
url = 'http://127.0.0.1:' + str(port) + '/ext/bc/' + demo.BLOCKCHAIN + '/rpc'
rpc_spec = importlib.util.spec_from_file_location('rpc', 'scripts/check-evm-rpc.py')
rpc = importlib.util.module_from_spec(rpc_spec)
rpc_spec.loader.exec_module(rpc)
rpc.check(url)
print(url)
PYRPC
)
forge build contracts/src/PWUSDDemo.sol
node -e "require('node:module').createRequire(process.cwd() + '/indexer/package.json')('ethers')"
node scripts/pwusd-demo.cjs prepare --chain-id 73571 --rpc-url "$RPC_URL"
PREPARE
```

**Funding checkpoint:** the owner of an already funded disposable local demo
wallet sends at least 2 PW to the printed new sender using their existing local
signer. The source wallet must be verified as a disposable EVM demo account on
73571, not a validator or treasury wallet. No private key is printed, copied into
chat, passed on a command line, or committed. This checkout does not contain or
access that funding signer; its availability is an outstanding blocker. The
recipient receives its PW from the demo runner and needs no initial funding.

After funding is confirmed and live deployment is approved, use the verified
port reported by dry-run to set `RPC_URL`, then execute the single runner command:

```bash
node scripts/pwusd-demo.cjs run --chain-id 73571 --rpc-url "$RPC_URL" --approve-live-demo
```

That command performs deployment, PWUSD transfer, native PW transfer and receipt/
balance/gas verification. Success creates `local-data/pwusd-demo/verified.json`;
three separate public receipts and the transaction journal accompany it. Never
print `sender.json` or `recipient.json`. On a partial attempt, stop and inspect
public receipts; do not delete the attempt marker or start over blindly.

## Evidence required for stopped startup

Saved public metadata in `metadata/runtime-identity.json` or `metadata/ready.json`
must contain `networkId`, `chainId`, `blockchainId`, `subnetId`, `vmId`, `nodeId`,
`stakingCertificateSha256`, `identityFiles` and `databaseEvidence`.
`identityFiles` maps the three staking-file flag names to `{device,inode,size}`.
`databaseEvidence` contains the database directory's `{device,inode}` and a `files`
map of database-relative CURRENT/MANIFEST paths to SHA-256 hashes. CURRENT must
point to the verified MANIFEST. Missing or changed evidence blocks startup.
The local Avalanche network ID is read from this metadata and compared to flags;
1337 is accepted when saved evidence says 1337. No network ID is assumed.

The utility checks database metadata, unlocked existing locks, the public
certificate, validator file inodes and the registered VM plugin. Private validator
key contents are never read. It translates only verified `/root/.avalanche-cli/`
aliases into the isolated `cli-home`. It never creates a subnet, initializes a
blockchain, resets a database, modifies genesis or deploys contracts. Startup
checks node identity, network identity, P-Chain registration and all four Ethereum
RPC methods. On failure it preserves state and does not retry/reset automatically.

PWUSD is an unbacked, nonredeemable, fixed-supply demonstration ERC-20 with no
administrator or external mint function. Deployment is restricted to local
chain 73571. Tests use Forge/Solidity 0.8.30, Python standard library and the
existing indexer's ethers v6 dependency. No new runtime dependency is introduced.
