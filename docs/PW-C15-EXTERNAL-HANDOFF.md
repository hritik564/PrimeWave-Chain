# PW-C15 — EXTERNAL INFRASTRUCTURE HANDOFF

**Sprint:** PW-C15 — Pre-Infrastructure Readiness Pass
**For:** Infrastructure Operator
**Date:** 2026-08-15
**Prepared by:** PrimeWave Engineering

---

## PURPOSE

This document is a complete handoff to the infrastructure operator.
It tells you exactly what to provide, what to run, and what to send back.

**NEVER paste private keys into Replit, ChatGPT, email, Slack, or any chat system.**
Private keys go: air-gapped machine → encrypted backup → operated server only.

---

## SECTION 1: WHAT YOU NEED TO PROVIDE

### 1A — Fuji Testnet AVAX

| Item | Detail |
|---|---|
| Amount needed | ≥ 2 AVAX on Fuji testnet (no real monetary value) |
| For address (C-Chain) | `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60` |
| Faucet URL | https://faucet.avax.network |
| Alternative | https://core.app (faucet tab) or Avalanche Discord #faucet |
| Purpose | Pay Fuji P-Chain fees for CreateSubnetTx + CreateChainTx |

---

### 1B — Cloud Servers

Minimum required (see `docs/PW-C15-INFRASTRUCTURE-BUDGET.md` for full spec):

| Server | Count | Minimum Spec |
|---|---|---|
| AvalancheGo validators | 3 | 4 vCPU / 8 GB RAM / 200 GB SSD, Ubuntu 22.04 LTS |
| Infrastructure server | 1 | 4 vCPU / 16 GB RAM / 500 GB SSD, Ubuntu 22.04 LTS |
| Monitoring server (optional for minimum gate) | 1 | 2 vCPU / 4 GB RAM |

Required: Ubuntu 22.04 LTS. Static public IPv4 addresses. SSH key access.

---

### 1C — SSH Access

| Item | Requirement |
|---|---|
| Type | SSH key pair |
| Key type | Ed25519 preferred |
| Generate with | `ssh-keygen -t ed25519 -C "primewave-testnet"` |
| Distribute public key | Add to each server's `~/.ssh/authorized_keys` |
| Provide to engineering | Hostname/IP + username for each server |

---

### 1D — DNS Access

| Item | Detail |
|---|---|
| Domain | `primewave.xyz` (or your registrar's domain) |
| Records to add | See table below |
| TTL | 300 seconds during setup; increase to 3600 after stable |

DNS A records required:

| Hostname | Type | Value |
|---|---|---|
| `rpc.testnet.primewave.xyz` | A | `<infra-01 IP>` |
| `explorer.testnet.primewave.xyz` | A | `<infra-01 IP>` |

---

### 1E — TLS Certificates

TLS is handled automatically via Let's Encrypt once DNS is in place.
No manual certificate generation is required.
The setup script handles this (Phase 5 in `docs/PW-C15-TESTNET-DAY-0-CHECKLIST.md`).

---

### 1F — Secure Key Ceremony Environment

| Requirement | Detail |
|---|---|
| Machine type | Air-gapped laptop or dedicated hardware wallet |
| Network | OFFLINE (no WiFi, no Ethernet, no Bluetooth) |
| OS | Live USB (Tails or Ubuntu live) preferred |
| Keys generated | testnet-keeper-signer + testnet-ems-signer-1..5 |
| Output | Public addresses only — private keys stay on air-gapped machine |
| Backup | age-encrypt private keys; store offline |

Follow `docs/PRIMEWAVE_KEY_SECURITY_PROCEDURE.md` for full procedure.

---

## SECTION 2: EXACT COMMANDS TO RUN

### STEP A: Fund Fuji Wallet (browser only)

1. Open: https://faucet.avax.network
2. Select: **Fuji Testnet**
3. Enter address: `0x2AD3152Ca630e2eF6679EBeb8da7b8311bfbFc60`
4. Click "Request 2 AVAX"
5. Repeat on successive days if more is needed (faucet rate limits)

---

### STEP B: Provision Servers

(Replace with your cloud provider's actual commands)

**Hetzner Cloud CLI example:**
```bash
# Install hcloud CLI: https://github.com/hetznercloud/cli
hcloud server create \
  --name primewave-validator-01 \
  --type cx32 \
  --image ubuntu-22.04 \
  --ssh-key my-key \
  --datacenter nbg1-dc3

# Repeat for validator-02, validator-03, infra-01
```

**AWS CLI example:**
```bash
aws ec2 run-instances \
  --image-id ami-0c7217cdde317cfec \
  --instance-type t3.xlarge \
  --count 3 \
  --key-name primewave-testnet \
  --security-group-ids sg-XXXX \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=primewave-validator}]'
```

---

### STEP C: SSH Into Each Server and Run Setup

```bash
# Clone repository
git clone <repo-url> /opt/primewave
cd /opt/primewave

# Run pre-flight to confirm environment
bash scripts/testnet/preflight-testnet.sh

# Follow the DAY-0 CHECKLIST from Phase 3 onwards:
# docs/PW-C15-TESTNET-DAY-0-CHECKLIST.md
```

---

### STEP D: Fuji P-Chain Subnet Creation

```bash
cd /opt/primewave
export PATH="$PWD/local-bin:$PATH"

# This creates the Fuji subnet and blockchain for PrimeWave testnet
avalanche blockchain deploy primewave-testnet \
  --fuji \
  --key testnet-deployer \
  --num-validators 3 2>&1 | tee /tmp/fuji-deploy.log

# RECORD THE OUTPUT — YOU WILL NEED THESE VALUES:
grep -E "(Subnet ID|Blockchain ID|RPC URL)" /tmp/fuji-deploy.log
```

---

### STEP E: DNS Records

In your DNS provider console:

```
Type: A
Name: rpc.testnet.primewave.xyz
Value: <infra-01 public IP>
TTL: 300

Type: A
Name: explorer.testnet.primewave.xyz
Value: <infra-01 public IP>
TTL: 300
```

---

### STEP F: TLS Certificates (on infra-01)

```bash
certbot --nginx \
  -d rpc.testnet.primewave.xyz \
  -d explorer.testnet.primewave.xyz \
  --non-interactive \
  --agree-tos \
  --email admin@primewave.xyz
```

---

### STEP G: Start Validators (on each validator server)

```bash
# REPLACE with actual IDs from Step D
export TESTNET_SUBNET_ID=<from Step D>
export TESTNET_BLOCKCHAIN_ID=<from Step D>

NODE_ROLE=validator \
TESTNET_SUBNET_ID=$TESTNET_SUBNET_ID \
TESTNET_BLOCKCHAIN_ID=$TESTNET_BLOCKCHAIN_ID \
bash /opt/primewave/scripts/testnet/setup-testnet-node.sh

systemctl start primewave-testnet-node
```

---

### STEP H: Run Health Check (from infra-01, after all services are up)

```bash
TESTNET_RPC_URL=https://rpc.testnet.primewave.xyz/ext/bc/$TESTNET_BLOCKCHAIN_ID/rpc \
TESTNET_INDEXER_URL=https://api.testnet.primewave.xyz \
TESTNET_PWCSCAN_URL=https://explorer.testnet.primewave.xyz \
bash /opt/primewave/scripts/testnet/testnet-health-check.sh
```

---

### STEP I: Run C15 Live Gate

```bash
TESTNET_RPC_URL=https://rpc.testnet.primewave.xyz/ext/bc/$TESTNET_BLOCKCHAIN_ID/rpc \
bash /opt/primewave/scripts/testnet/run-c15-live-gate.sh
```

---

## SECTION 3: EXPECTED OUTPUT

After Steps A–I are complete, you should see:

**From Fuji deploy (Step D):**
```
Subnet ID: <62-char CB58 string>
Blockchain ID: <62-char CB58 string>
RPC URL: https://api.avax-test.network/ext/bc/<BLOCKCHAIN_ID>/rpc
```

**From health check (Step H):**
```
[PASS]  HC-01: RPC eth_chainId => 0x4d
[PASS]  HC-02: RPC eth_blockNumber => <any number>
[PASS]  HC-03: RPC eth_gasPrice
[PASS]  HC-04: RPC net_version => 77
...
PASS: N | FAIL: 0 | SKIP: 0
[OK]    All components healthy.
```

**From C15 live gate (Step I):**
```
══ PRE-FLIGHT ══         [READY]
══ NETWORK IDENTITY ══   [PASS]
══ GENESIS ══            [PASS]
══ RPC ══                [PASS]
...
══ FINAL GATE ══
  PASS: N | FAIL: 0 | BLOCKED: 0
```

---

## SECTION 4: WHAT TO SEND BACK

After completing the above steps, send the following to engineering:

**Required (send via secure channel — these are all PUBLIC values):**

1. **Fuji Subnet ID** — 62-character CB58 string (from Step D output)
2. **Fuji Blockchain ID** — 62-character CB58 string (from Step D output)
3. **genesis.json SHA256** — from `sha256sum /opt/primewave/config/testnet/genesis.json`
4. **Contract addresses** — contents of `local-data/testnet-deployed-contracts.env` (addresses only, no keys)
5. **Validator NodeIDs** — from each validator's logs: `journalctl -u primewave-testnet-node | grep "NodeID"`
6. **Ceremony key public addresses** — testnet-deployer, testnet-ems-signer-1..5, testnet-keeper-signer (addresses only)
7. **Health check output** — output of Step H (full text)
8. **C15 live gate output** — output of Step I (full text)
9. **Server IPs** — public IPs of all provisioned servers
10. **Screenshots** — PWCScan explorer showing Chain ID 77 + 🧪 Testnet badge

**DO NOT SEND:**
- Private keys (testnet-deployer, testnet-keeper-signer, testnet-ems-signers)
- Database passwords
- Any file from `/secure/testnet-keys/`
- `.env` files containing credentials

**Delivery channel:**
- Encrypted: use Signal/ProtonMail or PGP-encrypt before sending
- All public values (contract addresses, node IDs, genesis hash): can be sent via any channel

---

## SECTION 5: SUPPORT

| Issue | Contact |
|---|---|
| Fuji P-Chain issues | Avalanche Discord: discord.gg/avalanche (#dev-support) |
| Avalanche CLI issues | https://github.com/ava-labs/avalanche-cli/issues |
| AvalancheGo issues | https://github.com/ava-labs/avalanchego/issues |
| PrimeWave protocol | Lead engineer (internal) |
| Cloud/server issues | Your cloud provider support |

---

## SECTION 6: IMPORTANT WARNINGS

1. **DO NOT use the `ewoq` key** for any testnet deployment. It is publicly known.
   ewoq C-Chain: `0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC`
   ewoq P-Chain: `P-fuji18jma8ppw3nhx5r4ap8clazz0dps7rv5u6wmu4t`
   These keys are present in the Avalanche CLI keystore as a local dev fixture.
   They must NEVER be used in any deployment operation.

2. **Fuji P-Chain transactions are IRREVERSIBLE.** Double-check SubnetID and BlockchainID
   before filling any config file.

3. **The genesis.json must be IDENTICAL on all validators.** Use `sha256sum` to verify.
   A divergent genesis causes a chain split — the network will not reach consensus.

4. **Do not run `deploy-contracts.sh` until the testnet RPC is live (Phase 13).**
   The script enforces Chain ID = 77 and will refuse to run on the wrong network.

5. **Mainnet Chain ID is TBD.** Do not register any mainnet chain ID. Do not generate
   any mainnet private keys. Mainnet deployment is C16+ scope.
