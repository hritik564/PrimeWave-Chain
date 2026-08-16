# PW-C15 — TESTNET DAY-0 OPERATOR CHECKLIST

**Sprint:** PW-C15 — Pre-Infrastructure Readiness Pass
**Status:** READY FOR OPERATOR EXECUTION
**Date Created:** 2026-08-15

## HOW TO USE THIS CHECKLIST

This is a literal step-by-step operator checklist.
Execute each step in order. Do not skip phases.
Mark each step ✅ as you complete it.
If a step fails, follow the ROLLBACK instructions before proceeding.

Every step specifies:
- **COMMAND / ACTION** — exact shell command or UI action
- **EXPECTED RESULT** — what success looks like
- **FAILURE CONDITION** — when to stop
- **ROLLBACK / RECOVERY** — how to undo and retry

All commands assume the operator is on the infra control workstation
with SSH access to all provisioned servers. `$REPO` = repository root.

---

## PRE-CHECKLIST: ENVIRONMENT SETUP

```bash
export REPO=/opt/primewave
export TESTNET_SUBNET_ID=__FILL_AFTER_PHASE_6__
export TESTNET_BLOCKCHAIN_ID=__FILL_AFTER_PHASE_6__
export TESTNET_DEPLOYER_ADDR=0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60
export TESTNET_DEPLOYER_PCHAIN=P-fuji1p25rk6kz9lwg2plwmfmvkvzxsa5qd02kla0vsw
export TESTNET_RPC_URL=https://rpc.testnet.primewave.xyz
export INDEXER_URL=https://api.testnet.primewave.xyz
export PWCSCAN_URL=https://explorer.testnet.primewave.xyz
```

---

## PHASE 0 — PREREQUISITES

**Purpose:** Verify repo, toolchain, and working directory are correct.

### Step 0.1 — Clone or update repository

**COMMAND:**
```bash
git clone <repo-url> $REPO
cd $REPO
git log --oneline -5
```

**EXPECTED RESULT:** Repository at HEAD. Last commit references PW-C15 work.

**FAILURE CONDITION:** Wrong branch, wrong commit, or merge conflicts.

**ROLLBACK:** `git fetch origin && git reset --hard origin/main`

---

### Step 0.2 — Run local pre-flight

**COMMAND:**
```bash
bash $REPO/scripts/testnet/preflight-testnet.sh
```

**EXPECTED RESULT:** All `READY` items pass. Any `BLOCKED` items are documented external infra.

**FAILURE CONDITION:** Any `READY` item fails (wrong binary version, wrong Chain ID in config, etc.).

**ROLLBACK:** Fix the specific failing item and re-run. Do not proceed with `FAIL` items.

---

### Step 0.3 — Confirm Chain ID consistency

**COMMAND:**
```bash
grep -r "77777" $REPO/config/testnet/ $REPO/scripts/testnet/ $REPO/deploy/testnet/ 2>/dev/null
grep -r '"chainId"' $REPO/config/testnet/genesis-template.json
```

**EXPECTED RESULT:** Zero matches for `77777`. `chainId: 77` in genesis template.

**FAILURE CONDITION:** Any match for `77777`.

**ROLLBACK:** Do not proceed. Report to lead engineer.

---

## PHASE 1 — FUJI FUNDING

**Purpose:** Ensure testnet-deployer has enough AVAX on Fuji P-Chain to pay for CreateSubnetTx and CreateChainTx.

### Step 1.1 — Fund testnet-deployer on Fuji (browser step)

**ACTION:**
1. Open browser → https://faucet.avax.network
2. Select network: **Fuji**
3. Enter address: `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60`
4. Request AVAX (2 AVAX per request; repeat 2–3× on successive days if needed)

**EXPECTED RESULT:** C-Chain balance ≥ 2 AVAX (confirmed at faucet or via explorer)

**FAILURE CONDITION:** Faucet down; captcha blocks automation.

**ROLLBACK:** Try alternative faucets: https://core.app (faucet tab) or ask in Avalanche Discord #faucet.

---

### Step 1.2 — Export AVAX from C-Chain to P-Chain

**COMMAND:**
```bash
cd $REPO
export PATH="$REPO/local-bin:$PATH"

# Export AVAX from C-Chain to P-Chain (1.5 AVAX — keep some for gas)
avalanche key transfer \
  --key testnet-deployer \
  --fuji \
  --amount 1.5 \
  --destination-key testnet-deployer \
  --source-chain C \
  --destination-chain P
```

**EXPECTED RESULT:** P-Chain balance ≥ 1.5 AVAX on `P-fuji17c7fuusyh76r74zwge4sl0nc3458xdkv477adz`

**FAILURE CONDITION:** Balance too low; export fails.

**ROLLBACK:** Fund C-Chain again (Step 1.1) and retry. If export succeeds partially, the remaining balance should still be queryable.

---

### Step 1.3 — Verify P-Chain balance

**COMMAND:**
```bash
avalanche key list --fuji 2>&1 | grep -A2 "testnet-deployer"
```

**EXPECTED RESULT:** P-Chain balance ≥ 0.1 AVAX for testnet-deployer.

**FAILURE CONDITION:** Balance = 0 AVAX.

**ROLLBACK:** Repeat Steps 1.1–1.2.

---

## PHASE 2 — KEY CEREMONY

**Purpose:** Generate all testnet ceremony keys. Record public addresses only.

### Step 2.1 — Generate EOA ceremony keys

**COMMAND:**
```bash
TESTNET_KEY_DIR=/secure/testnet-keys bash $REPO/scripts/testnet/generate-validator-keys.sh
```

**EXPECTED RESULT:** 7 key files created in `/secure/testnet-keys/`. Public addresses printed to stdout. Private keys are in the directory.

**FAILURE CONDITION:** Output directory writable; any key generation error.

**ROLLBACK:** Delete partial output directory and retry.

> **SECURITY:** The private key files MUST NOT be committed to Git.
> `/secure/testnet-keys/` must be on encrypted storage.
> Back up with: `age -p -o testnet-keys.age /secure/testnet-keys/`

---

### Step 2.2 — Record ceremony addresses

**ACTION:** Copy the public addresses from Step 2.1 output into a secure notepad. You will need them in Phase 7 (genesis) and when filling `contracts/script/DeployTestnet.s.sol`.

**EXPECTED RESULT:** You have all 7 addresses recorded:
- testnet-deployer: `0xB518397E3D65a0E7475635F01C225E9426a76F11` (replaced 2026-08-16 — original key lost, see PW-C15-DEPLOYER-REPLACEMENT-REPORT.md)
- testnet-keeper-signer
- testnet-ems-signer-1 through testnet-ems-signer-5

**FAILURE CONDITION:** Any address is missing or address(0).

**ROLLBACK:** Re-run generate-validator-keys.sh.

---

### Step 2.3 — Update DeployTestnet.s.sol EMS signers

**ACTION:** Open `contracts/script/DeployTestnet.s.sol` and replace:
```solidity
address constant EMS_SIGNER_1 = address(0); // REPLACE
// ... etc.
```
with the actual testnet-ems-signer-1..5 addresses.

**COMMAND (verify):**
```bash
grep "EMS_SIGNER" $REPO/contracts/script/DeployTestnet.s.sol
```

**EXPECTED RESULT:** All 5 EMS_SIGNER constants are non-zero addresses.

**FAILURE CONDITION:** Any EMS_SIGNER still equals `address(0)`.

**ROLLBACK:** Do not deploy. Fix the constant and verify.

---

## PHASE 3 — CLOUD PROVISIONING

**Purpose:** Provision cloud VPS servers for validators and infrastructure.

### Step 3.1 — Provision servers

See `docs/PW-C15-INFRA-PROVISIONING-GUIDE.md §3` for full topology and specs.

**ACTION (minimum viable):**
Provision 4 dedicated L1 validator servers (separate from V2–V5 which run Fuji C-chain full sync):
- validator-01, validator-02, validator-03, validator-04: 4 vCPU / 8GB RAM / 200GB SSD each

**EXPECTED RESULT:** 4 servers provisioned with Ubuntu 22.04 LTS, SSH accessible, static IPs assigned.

**FAILURE CONDITION:** SSH not accessible; server not reachable on port 22.

**ROLLBACK:** Destroy and re-provision. Save static IPs.

---

### Step 3.2 — Configure firewall rules

**COMMAND (on each server):**
```bash
ufw allow 22/tcp     # SSH (admin only — restrict to operator IP in production)
ufw allow 9651/tcp   # AvalancheGo P2P
ufw allow 9651/udp   # AvalancheGo P2P
# On infra-01 only:
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```

**EXPECTED RESULT:** `ufw status` shows rules active.

**FAILURE CONDITION:** SSH locked out (critical — do not run `ufw enable` without allowing port 22 first).

**ROLLBACK:** Use cloud provider console to access server and reset firewall.

---

### Step 3.3 — Install base dependencies on each server

**COMMAND:**
```bash
apt-get update && apt-get install -y curl jq python3 nginx certbot python3-certbot-nginx postgresql nodejs npm
```

**EXPECTED RESULT:** All packages installed without errors.

**FAILURE CONDITION:** Package not found; apt error.

**ROLLBACK:** Fix apt source or install individually.

---

## PHASE 4 — DNS

**Purpose:** Register DNS A records so TLS certs can be issued and the RPC/Explorer are accessible.

### Step 4.1 — Register DNS records

**ACTION:** In your DNS provider (Cloudflare, Route53, etc.) add:

| Hostname | Type | Value | TTL |
|---|---|---|---|
| `rpc.testnet.primewave.xyz` | A | `<infra-01 IP>` | 300 |
| `explorer.testnet.primewave.xyz` | A | `<infra-01 IP>` | 300 |

**EXPECTED RESULT:** DNS propagated within 5–15 minutes.

**COMMAND (verify):**
```bash
dig +short rpc.testnet.primewave.xyz
dig +short explorer.testnet.primewave.xyz
```

**EXPECTED RESULT:** Both return the infra-01 IP.

**FAILURE CONDITION:** DNS returns NXDOMAIN or wrong IP after 30 minutes.

**ROLLBACK:** Check DNS provider UI. Update record. Wait for TTL to expire and propagate.

---

## PHASE 5 — TLS

**Purpose:** Obtain Let's Encrypt TLS certificates.

### Step 5.1 — Issue TLS certificates (on infra-01)

**COMMAND:**
```bash
certbot --nginx -d rpc.testnet.primewave.xyz -d explorer.testnet.primewave.xyz \
  --non-interactive --agree-tos --email admin@primewave.xyz
```

**EXPECTED RESULT:** Certificates issued and installed. Nginx restarted automatically.

**FAILURE CONDITION:** DNS not yet propagated; rate limited by Let's Encrypt.

**ROLLBACK:** Wait for DNS propagation (Phase 4) or use `--test-cert` for staging.

---

### Step 5.2 — Verify TLS

**COMMAND:**
```bash
curl -sf https://rpc.testnet.primewave.xyz/ext/health && echo "TLS OK"
```

**EXPECTED RESULT:** Returns JSON response with TLS OK.

**FAILURE CONDITION:** Certificate error; connection refused.

**ROLLBACK:** Re-run certbot or check nginx config.

---

## PHASE 6 — FUJI P-CHAIN

**Purpose:** Create the PrimeWave testnet subnet and blockchain on Fuji.

### Step 6.1 — Deploy testnet subnet to Fuji

**COMMAND:**
```bash
cd $REPO
export PATH="$REPO/local-bin:$PATH"
# IMPORTANT: flag is --num-bootstrap-validators (not --num-validators)
# See docs/PW-C15-FUJI-CEREMONY-RUNBOOK.md for full flag reference.
avalanche blockchain deploy primewave-testnet \
  --fuji \
  --key testnet-deployer \
  --bootstrap-filepath config/testnet/bootstrap-validators.json \
  --num-bootstrap-validators 4 2>&1 | tee /tmp/fuji-ceremony.log
```

**EXPECTED RESULT:** Output contains:
```
Subnet ID: <SUBNET_ID>
Blockchain ID: <BLOCKCHAIN_ID>
RPC URL: https://api.avax-test.network/ext/bc/<BLOCKCHAIN_ID>/rpc
```

**FAILURE CONDITION:** Insufficient AVAX; RPC timeout; key not found.

**ROLLBACK:** Fuji P-Chain transactions are irreversible once confirmed. If the deploy partially succeeds, record the SubnetID and restart from Step 6.2 to add the chain. If no transactions were broadcast, retry from Step 6.1.

---

### Step 6.2 — Record and export IDs

**COMMAND:**
```bash
grep -E "(Subnet ID|Blockchain ID)" /tmp/fuji-deploy.log
export TESTNET_SUBNET_ID=<SUBNET_ID_FROM_LOG>
export TESTNET_BLOCKCHAIN_ID=<BLOCKCHAIN_ID_FROM_LOG>
echo "TESTNET_SUBNET_ID=$TESTNET_SUBNET_ID" >> /etc/primewave/testnet.env
echo "TESTNET_BLOCKCHAIN_ID=$TESTNET_BLOCKCHAIN_ID" >> /etc/primewave/testnet.env
```

**EXPECTED RESULT:** Both IDs recorded and exported.

**FAILURE CONDITION:** IDs missing from log.

**ROLLBACK:** Check Fuji P-Chain explorer for the transaction. SubnetID is derivable from the CreateSubnetTx.

---

### Step 6.3 — Verify on Fuji

**COMMAND:**
```bash
curl -sf -X POST -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"platform.getSubnet\",\"params\":{\"subnetID\":\"$TESTNET_SUBNET_ID\"}}" \
  https://api.avax-test.network/ext/bc/P | python3 -m json.tool
```

**EXPECTED RESULT:** Returns subnet info without error.

**FAILURE CONDITION:** `subnetID not found` error.

**ROLLBACK:** Verify the SubnetID from Step 6.2 is correct.

---

## PHASE 7 — GENESIS

**Purpose:** Fill ceremony addresses into genesis template and generate final `genesis.json`.

### Step 7.1 — Fill genesis placeholders

**ACTION:** Open `config/testnet/genesis-template.json` and replace all 7 `__REPLACE_*__` entries with actual ceremony addresses from Phase 2.

```
__REPLACE_TESTNET_DEPLOYER_ADDRESS__   → testnet-deployer address (0xB518397E3D65a0E7475635F01C225E9426a76F11)
__REPLACE_FEE_DISTRIBUTOR_ADDRESS__    → FeeDistributor predicted address (0x27B15970700daC632f0814522118A1c3B200d971)
__REPLACE_TESTNET_TREASURY_ADDRESS__   → treasury multisig address
__REPLACE_TESTNET_TEAM_ADDRESS__       → team vesting address
__REPLACE_TESTNET_COMMUNITY_ADDRESS__  → community pool address
__REPLACE_TESTNET_ECOSYSTEM_ADDRESS__  → ecosystem fund address
__REPLACE_TESTNET_RESERVE_ADDRESS__    → reserve address
```

Deployer address and FeeDistributor predicted address are pre-computed (see `local-data/testnet-key-addresses.env`). Fill the remaining 5 addresses with operator-provided values.

**COMMAND (verify — must return zero):**
```bash
grep -c "__REPLACE_" $REPO/config/testnet/genesis-template.json
```

**EXPECTED RESULT:** `0` (no remaining placeholders).

**FAILURE CONDITION:** Any `__REPLACE_` string still present. STOP.

**ROLLBACK:** Re-edit the template. Do not generate genesis.json until placeholders are all filled.

---

### Step 7.2 — Validate allocation math

**COMMAND:**
```bash
python3 $REPO/scripts/testnet/preflight-testnet.sh 2>/dev/null || \
python3 << 'EOF'
import json
g = json.load(open('config/testnet/genesis-template.json'))
alloc = {k: v for k, v in g['alloc'].items() if 'balance' in v}
total = sum(int(v['balance'], 16) for v in alloc.values())
assert total == 100_000_000 * 10**18, f"Supply mismatch: {total//10**18} PW"
assert g['config']['chainId'] == 77
print(f"Supply: {total//10**18:,} PW ✅  ChainID: {g['config']['chainId']} ✅")
EOF
```

**EXPECTED RESULT:** `Supply: 100,000,000 PW ✅  ChainID: 77 ✅`

**FAILURE CONDITION:** Any assertion error.

**ROLLBACK:** Fix the allocation totals. Total MUST be exactly 100M PW.

---

### Step 7.3 — Generate final genesis.json

**COMMAND:**
```bash
python3 << 'EOF'
import json
g = json.load(open('config/testnet/genesis-template.json'))
# Remove template metadata keys
clean = {k: v for k, v in g.items() if not k.startswith('_')}
clean['alloc'] = {k: {sk: sv for sk, sv in v.items() if not sk.startswith('_')}
                  for k, v in g['alloc'].items() if not k.startswith('_') and not '__REPLACE_' in k}
assert not any('__REPLACE_' in k for k in clean['alloc']), "Unfilled placeholder!"
json.dump(clean, open('config/testnet/genesis.json', 'w'), indent=2)
print("genesis.json generated")
EOF
sha256sum config/testnet/genesis.json
```

**EXPECTED RESULT:** `genesis.json` created; SHA256 hash printed and recorded.

**FAILURE CONDITION:** Assertion error (unfilled placeholder); Python error.

**ROLLBACK:** Do NOT use a genesis.json with unfilled placeholders. Fix template and retry.

---

### Step 7.4 — Cross-validate with all validators

**ACTION:** Distribute `config/testnet/genesis.json` to all validator operators. Each operator must verify:
```bash
sha256sum genesis.json  # Must match the recorded hash from Step 7.3
```

**EXPECTED RESULT:** All 3+ operators confirm the same SHA256.

**FAILURE CONDITION:** Any operator reports a different hash. STOP deployment.

**ROLLBACK:** Re-distribute the canonical genesis.json from the control node.

---

## PHASE 8 — PRIMEWAVE CONTRACTS

**Purpose:** Deploy all 7 protocol contracts to the PrimeWave testnet (Chain ID 77).

### Step 8.1 — Verify testnet RPC is live (Chain ID 77)

**COMMAND:**
```bash
cast chain-id --rpc-url $TESTNET_RPC_URL
```

**EXPECTED RESULT:** `77`

**FAILURE CONDITION:** Returns anything other than 77; connection refused.

**ROLLBACK:** Complete Phases 9–11 first (validators must be running before deploying contracts).

> **NOTE:** Phases 8 and 9 have a circular dependency. The RPC must be live (from Phase 13) before deploying contracts. Complete Phases 9–13 first, then return here.

---

### Step 8.2 — Deploy contracts

**COMMAND:**
```bash
TESTNET_RPC_URL=$TESTNET_RPC_URL \
TESTNET_DEPLOYER_KEY=<testnet-deployer-private-key> \
bash $REPO/scripts/testnet/deploy-contracts.sh 2>&1 | tee /tmp/deploy-contracts.log
```

**EXPECTED RESULT:** Output ends with `DeployTestnet COMPLETE`. File `local-data/testnet-deployed-contracts.env` written with 7 contract addresses.

**FAILURE CONDITION:**
- `WRONG CHAIN ID` → connected to wrong network
- `REFUSED - dev mnemonic key` → using dev key, not testnet key
- `EMS signer addresses are zero` → Phase 2.3 incomplete
- `Insufficient balance` → deployer needs ≥ 15,001 PW in genesis alloc
- `FeeDistributor address prediction mismatch` → nonce was not 0 at deploy time

**ROLLBACK:** If broadcast already happened, contracts are on-chain. Record all addresses from log. If deploy failed mid-way, check each address and decide whether to redeploy individual contracts or redeploy from scratch with a fresh deployer key (new nonce).

---

### Step 8.3 — Record contract addresses

**COMMAND:**
```bash
cat $REPO/local-data/testnet-deployed-contracts.env
```

**EXPECTED RESULT:** 7 address lines:
```
ADDR_EMERGENCY_MULTISIG=0x...
ADDR_TIMELOCK=0x...
ADDR_VALIDATOR_FEE_VAULT=0x...
ADDR_DEV_TREASURY=0x...
ADDR_FEE_DISTRIBUTOR=0x...
ADDR_REWARD_VAULT=0x...
ADDR_VALIDATOR_REGISTRY=0x...
```

Record these in `docs/PW-C15-TESTNET-VARIABLE-MANIFEST.md`.

---

### Step 8.4 — Verify contracts

**COMMAND:**
```bash
source $REPO/local-data/testnet-deployed-contracts.env
TESTNET_RPC_URL=$TESTNET_RPC_URL \
TESTNET_CONTRACTS_ENV=$REPO/local-data/testnet-deployed-contracts.env \
bash $REPO/scripts/testnet/validate-testnet-genesis.sh
```

**EXPECTED RESULT:** `All checked invariants passed.`

**FAILURE CONDITION:** Any invariant FAIL.

**ROLLBACK:** Investigate the failing invariant. Do not proceed until all pass.

---

## PHASE 9 — VALIDATORS

**Purpose:** Start AvalancheGo validator nodes and sync to Fuji.

### Step 9.1 — Set up validator nodes (per validator server)

**COMMAND (on each validator):**
```bash
NODE_ROLE=validator \
TESTNET_SUBNET_ID=$TESTNET_SUBNET_ID \
TESTNET_BLOCKCHAIN_ID=$TESTNET_BLOCKCHAIN_ID \
bash $REPO/scripts/testnet/setup-testnet-node.sh
```

**EXPECTED RESULT:** AvalancheGo installed, systemd service created.

**FAILURE CONDITION:** Binary download fails; apt errors.

**ROLLBACK:** Re-run setup script. Binary is idempotent.

---

### Step 9.2 — Copy genesis and chain config

**COMMAND (on each validator):**
```bash
mkdir -p /etc/primewave/
cp $REPO/config/testnet/genesis.json /etc/primewave/genesis.json
cp $REPO/config/testnet/node-config.json /etc/primewave/node-config.json
# Update node-config.json with actual subnet and blockchain IDs
python3 -c "
import json
c = json.load(open('/etc/primewave/node-config.json'))
c['track-subnets'] = '$TESTNET_SUBNET_ID'
json.dump(c, open('/etc/primewave/node-config.json','w'), indent=2)
"
```

**EXPECTED RESULT:** Config files in place with correct subnet ID.

**FAILURE CONDITION:** Config file not found; JSON parse error.

**ROLLBACK:** Copy from repo and re-run.

---

### Step 9.3 — Start validator nodes

**COMMAND (on each validator):**
```bash
systemctl daemon-reload
systemctl enable primewave-testnet-node
systemctl start primewave-testnet-node
systemctl status primewave-testnet-node
```

**EXPECTED RESULT:** `Active: active (running)`. Logs show `Bootstrapping...` and eventually `Bootstrapping complete`.

**FAILURE CONDITION:** Service failed; OOM; port conflict.

**ROLLBACK:** `systemctl stop primewave-testnet-node`. Check logs: `journalctl -u primewave-testnet-node -n 100`. Fix the issue and restart.

---

### Step 9.4 — Confirm Fuji bootstrap

**COMMAND:**
```bash
curl -sf http://localhost:9650/ext/health | python3 -c "import json,sys; d=json.load(sys.stdin); print('Healthy:', d.get('healthy', False))"
```

**EXPECTED RESULT:** `Healthy: True` (after bootstrap completes — may take 15–60 minutes).

**FAILURE CONDITION:** `Healthy: False`; unhealthy subnets.

**ROLLBACK:** Wait longer (Fuji bootstrap can take up to 2 hours on slow networks). Check `journalctl` for errors.

---

## PHASE 10 — ACP-99

**Purpose:** Register PrimeWave validators via ValidatorManager (ACP-99 protocol).

### Step 10.1 — Initiate ACP-99 validator registration

**COMMAND:**
```bash
# For each validator, call StakingManager.initiateValidatorRegistration()
# via keeper or direct cast call (see keeper configuration)
cast send $ADDR_VALIDATOR_REGISTRY \
  "initiateRegistration(bytes,uint64,uint64,uint16)" \
  <BLS_PUBLIC_KEY_BYTES> <STAKE_WEIGHT> <EXPIRY_TIMESTAMP> <DELEGATION_FEE_BIPS> \
  --rpc-url $TESTNET_RPC_URL \
  --private-key <DEPLOYER_KEY>
```

**EXPECTED RESULT:** Transaction confirmed; `ValidationID` emitted.

**FAILURE CONDITION:** Reverts; insufficient balance; wrong registry address.

**ROLLBACK:** If the ICM/Warp message fails, the validation set on P-Chain is not updated. Retry the registration.

---

## PHASE 11 — ICM / WARP

**Purpose:** Deploy and start the ICM/Warp relayer so P-Chain ↔ subnet messages are processed.

### Step 11.1 — Deploy ICM relayer

**COMMAND:**
```bash
# Install Teleporter relayer (from Ava Labs)
curl -fsSL https://github.com/ava-labs/icm-services/releases/latest/download/relayer-linux-amd64.tar.gz | \
  tar -xz -C /usr/local/bin/

# Configure relayer
cp $REPO/deploy/testnet/icm-relayer-config.json /etc/primewave/relayer-config.json
# Fill in SUBNET_ID, BLOCKCHAIN_ID, RPC endpoints

# Start relayer
systemctl start icm-relayer
```

**EXPECTED RESULT:** Relayer running and processing messages.

**FAILURE CONDITION:** Relayer can't connect to Fuji or local subnet.

**ROLLBACK:** `systemctl stop icm-relayer`. Fix config and restart.

---

## PHASE 12 — KEEPER

**Purpose:** Deploy the PrimeWave keeper service for automated validator sync.

### Step 12.1 — Configure keeper environment

**COMMAND (on infra-01):**
```bash
cp $REPO/deploy/testnet/env/testnet-keeper.env.template /etc/primewave/testnet-keeper.env
# Fill in:
# - KEEPER_RPC_URL (with actual BLOCKCHAIN_ID)
# - KEEPER_PRIVATE_KEY (testnet-keeper-signer private key)
# - KEEPER_REGISTRY_ADDR (from Phase 8.3)
# - KEEPER_VAULT_ADDR (from Phase 8.3)
# - KEEPER_DB_URL (with actual DB password)
chmod 600 /etc/primewave/testnet-keeper.env
```

**EXPECTED RESULT:** Env file in place with no `__REPLACE__` strings remaining.

**FAILURE CONDITION:** Any `__REPLACE__` in the env file.

**ROLLBACK:** Fix the file and reload the service.

---

### Step 12.2 — Build and start keeper

**COMMAND:**
```bash
cd $REPO/keeper && npm ci && npm run build
cp -r $REPO/keeper/dist /opt/primewave/keeper/dist

systemctl daemon-reload
systemctl enable primewave-testnet-keeper
systemctl start primewave-testnet-keeper
sleep 5 && curl -sf http://localhost:8080/health
```

**EXPECTED RESULT:** `{"status":"ok"}` from health endpoint.

**FAILURE CONDITION:** Service crashed; health returns error.

**ROLLBACK:** `systemctl stop primewave-testnet-keeper`. Check `journalctl -u primewave-testnet-keeper -n 50`. Fix and restart.

---

## PHASE 13 — RPC

**Purpose:** Configure nginx as a public-facing RPC reverse proxy.

### Step 13.1 — Install and configure nginx

**COMMAND (on infra-01):**
```bash
# Update domain in nginx config
sed -i 's/rpc.primewave-testnet.example.com/rpc.testnet.primewave.xyz/g' \
  $REPO/deploy/testnet/nginx/rpc.conf
sed -i 's/testnet.pwcscan.example.com/explorer.testnet.primewave.xyz/g' \
  $REPO/deploy/testnet/nginx/explorer.conf

cp $REPO/deploy/testnet/nginx/rpc.conf /etc/nginx/sites-available/primewave-rpc
cp $REPO/deploy/testnet/nginx/explorer.conf /etc/nginx/sites-available/primewave-explorer
ln -sf /etc/nginx/sites-available/primewave-rpc /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/primewave-explorer /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx
```

**EXPECTED RESULT:** `nginx: configuration file /etc/nginx/nginx.conf test is successful`

**FAILURE CONDITION:** Nginx config test fails; syntax error.

**ROLLBACK:** Remove symlinks, restore default config, reload nginx.

---

### Step 13.2 — Verify public RPC

**COMMAND:**
```bash
curl -sf -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
  https://rpc.testnet.primewave.xyz/ext/bc/$TESTNET_BLOCKCHAIN_ID/rpc
```

**EXPECTED RESULT:** `{"jsonrpc":"2.0","result":"0x4d","id":1}` (0x4d = 77)

**FAILURE CONDITION:** Connection error; wrong chain ID.

**ROLLBACK:** Check nginx upstream config. Verify AvalancheGo node is serving on port 9650.

---

## PHASE 14 — POSTGRESQL

**Purpose:** Set up the PostgreSQL database for the indexer.

### Step 14.1 — Create indexer database

**COMMAND (on infra-01):**
```bash
sudo -u postgres createuser indexer --no-superuser --no-createdb --no-createrole
sudo -u postgres createdb primewave_testnet --owner=indexer
sudo -u postgres psql -c "ALTER USER indexer PASSWORD 'REPLACE_WITH_STRONG_PASSWORD';"
```

**EXPECTED RESULT:** Database and user created.

**FAILURE CONDITION:** PostgreSQL not running; permission denied.

**ROLLBACK:** `sudo -u postgres dropdb primewave_testnet && sudo -u postgres dropuser indexer`; restart PostgreSQL and retry.

---

## PHASE 15 — INDEXER

**Purpose:** Start the indexer to sync block/transaction data.

### Step 15.1 — Configure indexer environment

**COMMAND:**
```bash
cp $REPO/deploy/testnet/env/testnet-indexer.env.template /etc/primewave/testnet-indexer.env
# Fill in:
# - INDEXER_RPC_URL and INDEXER_WS_URL (with actual BLOCKCHAIN_ID)
# - INDEXER_DB_URL (with actual DB password)
# - ADDR_* contract addresses (from Phase 8.3)
chmod 600 /etc/primewave/testnet-indexer.env
```

**EXPECTED RESULT:** Env file with no `__REPLACE__` or `__REPLACE_BLOCKCHAIN_ID__` strings.

**FAILURE CONDITION:** Any `__REPLACE__` remaining.

**ROLLBACK:** Fix env file and reload.

---

### Step 15.2 — Build and start indexer

**COMMAND:**
```bash
cd $REPO/indexer && npm ci && npm run build
cp -r $REPO/indexer/dist /opt/primewave/indexer/dist

systemctl daemon-reload
systemctl enable primewave-testnet-indexer
systemctl start primewave-testnet-indexer
sleep 10 && curl -sf http://localhost:4000/health
```

**EXPECTED RESULT:** `{"status":"ok","isSynced":false}` initially (will become `isSynced:true` after catching up).

**FAILURE CONDITION:** Health endpoint unreachable; DB connection refused.

**ROLLBACK:** `systemctl stop primewave-testnet-indexer`. Check logs. Fix config and restart.

---

## PHASE 16 — PWCSCAN

**Purpose:** Deploy PWCScan explorer frontend.

### Step 16.1 — Configure and build PWCScan

**COMMAND:**
```bash
source /etc/primewave/testnet-pwcscan.env
cp $REPO/deploy/testnet/env/testnet-pwcscan.env.template /etc/primewave/testnet-pwcscan.env
# Fill in:
# - VITE_RPC_URL (https://rpc.testnet.primewave.xyz/ext/bc/$BLOCKCHAIN_ID/rpc)
# - VITE_CHAIN_ID=77
# - VITE_NETWORK_LABEL="🧪 Testnet"
# - VITE_INDEXER_URL (https://api.testnet.primewave.xyz)

cd $REPO/artifacts/pwcscan
source /etc/primewave/testnet-pwcscan.env
pnpm install && pnpm build
cp -r dist /opt/primewave/pwcscan/dist
```

**EXPECTED RESULT:** `dist/` directory created with `index.html`.

**FAILURE CONDITION:** Build error; VITE_CHAIN_ID missing.

**ROLLBACK:** Fix env vars and rebuild.

---

### Step 16.2 — Start PWCScan service

**COMMAND:**
```bash
systemctl daemon-reload
systemctl enable primewave-testnet-pwcscan
systemctl start primewave-testnet-pwcscan
sleep 3 && curl -sf https://explorer.testnet.primewave.xyz | grep -c "PrimeWave"
```

**EXPECTED RESULT:** Returns count ≥ 1 (page contains "PrimeWave").

**FAILURE CONDITION:** Connection refused; nginx error.

**ROLLBACK:** Check build output. Fix nginx config. Reload service.

---

## PHASE 17 — MONITORING

**Purpose:** Start Prometheus and Grafana for testnet monitoring.

### Step 17.1 — Configure Prometheus

**COMMAND (on monitoring server):**
```bash
# Update hostnames in prometheus.yml with actual IPs
cp $REPO/deploy/testnet/prometheus/prometheus.yml /etc/prometheus/prometheus.yml
cp $REPO/deploy/testnet/prometheus/alert-rules.yml /etc/prometheus/rules/primewave.yml
# Edit prometheus.yml to replace __REPLACE_VALIDATOR_*_IP__ with actual IPs

systemctl restart prometheus
```

**EXPECTED RESULT:** `promtool check config /etc/prometheus/prometheus.yml` passes. Targets visible in Prometheus UI.

**FAILURE CONDITION:** Config syntax error; targets unreachable.

**ROLLBACK:** Restore previous prometheus.yml; `systemctl restart prometheus`.

---

## PHASE 18 — C15 ACCEPTANCE TESTS

**Purpose:** Execute the C15 test matrix against the live testnet.

### Step 18.1 — Run full C15 live gate

**COMMAND:**
```bash
TESTNET_RPC_URL=$TESTNET_RPC_URL \
TESTNET_INDEXER_URL=$INDEXER_URL \
TESTNET_PWCSCAN_URL=$PWCSCAN_URL \
bash $REPO/scripts/testnet/run-c15-live-gate.sh 2>&1 | tee /tmp/c15-live-gate.log
```

**EXPECTED RESULT:** All PASS. Zero FAIL. Some items may remain BLOCKED (external soak tests, etc.).

**FAILURE CONDITION:** Any critical item FAILs.

**ROLLBACK:** Investigate specific failure. Do not open C16 gate until all FAIL items are resolved.

---

### Step 18.2 — Run testnet health check

**COMMAND:**
```bash
TESTNET_RPC_URL=$TESTNET_RPC_URL \
TESTNET_INDEXER_URL=$INDEXER_URL \
TESTNET_PWCSCAN_URL=$PWCSCAN_URL \
TESTNET_KEEPER_HEALTH_URL=http://localhost:8080 \
bash $REPO/scripts/testnet/testnet-health-check.sh
```

**EXPECTED RESULT:** All HC-* PASS. FAIL: 0.

**FAILURE CONDITION:** Any FAIL.

**ROLLBACK:** Investigate failing component.

---

### Step 18.3 — Run genesis validation

**COMMAND:**
```bash
TESTNET_RPC_URL=$TESTNET_RPC_URL \
TESTNET_CONTRACTS_ENV=$REPO/local-data/testnet-deployed-contracts.env \
bash $REPO/scripts/testnet/validate-testnet-genesis.sh
```

**EXPECTED RESULT:** All INV-G* PASS.

**FAILURE CONDITION:** Any FAIL.

**ROLLBACK:** Investigate contract state.

---

## PHASE 19 — GATE REVIEW

**Purpose:** Verify all C16 entry gate items that can now be cleared are marked PASS.

### Step 19.1 — Update C16 entry gate

**ACTION:** Open `docs/PW-C15-C16-ENTRY-GATE.md`.
For each gate item where a corresponding acceptance test PASSED:
- Change `BLOCKED` → `✅ PASS`
- Add evidence: date, test name, output hash

**EXPECTED RESULT:** Gate items G-01 through G-60 updated.

**FAILURE CONDITION:** Any item marked PASS without actual test evidence.

**ROLLBACK:** Do not advance items without evidence.

---

### Step 19.2 — Final C16 gate decision

**ACTION:** Count PASS / FAIL / BLOCKED / DEFERRED items in `docs/PW-C15-C16-ENTRY-GATE.md`.

**EXPECTED RESULT for C16 to open:**
- Zero FAIL
- All BLOCKED cleared except items explicitly approved as DEFERRED
- G-32 (14-day unbond) either completed or formally DEFERRED with leadership sign-off

**FAILURE CONDITION:** Any unreresolved FAIL.

---

## APPENDIX: EMERGENCY CONTACTS AND ESCALATION

| Role | Contact | Responsibility |
|---|---|---|
| Protocol Lead | — | C16 gate decision authority |
| Infra Lead | — | Cloud/VPS provisioning |
| Security Lead | — | Key ceremony oversight |
| Avalanche Support | discord.gg/avalanche | Fuji P-Chain issues |

## APPENDIX: KEY ARTIFACTS GENERATED DURING DAY-0

| Artifact | Location | Committed to Git? |
|---|---|---|
| Fuji Subnet ID | `docs/PW-C15-TESTNET-VARIABLE-MANIFEST.md` | YES (public) |
| Fuji Blockchain ID | `docs/PW-C15-TESTNET-VARIABLE-MANIFEST.md` | YES (public) |
| genesis.json | `config/testnet/genesis.json` | YES (public) |
| genesis.json SHA256 | `docs/PW-C15-TESTNET-VARIABLE-MANIFEST.md` | YES (public) |
| testnet-deployed-contracts.env | `local-data/testnet-deployed-contracts.env` | NO (gitignored) |
| Ceremony private keys | `/secure/testnet-keys/` | NEVER |
| Keeper private key | `/etc/primewave/testnet-keeper.env` | NEVER |
| EMS signer private keys | `/secure/testnet-keys/` | NEVER |
