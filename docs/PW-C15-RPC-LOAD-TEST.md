# PW-C15 — RPC LOAD TEST

**Sprint:** PW-C15 — Testnet Battle Test + Mainnet Readiness
**Status:** PROCEDURE READY — PENDING EXTERNAL EXECUTION
**Environment:** TESTNET ONLY — Chain ID 77

---

## 1. OBJECTIVE

Measure testnet RPC capacity under controlled, realistic load.
Determine normal capacity, degraded behavior, rate-limit threshold, and recovery.

> **IMPORTANT:** Do NOT perform uncontrolled internet-wide load tests.
> All load is generated from controlled internal clients only.

---

## 2. RPC ENDPOINT VERIFICATION

Before any load test, verify all standard endpoints respond correctly:

```bash
RPC=https://rpc.testnet.primewave.xyz

# Verify chain identity
cast chain-id --rpc-url $RPC           # Must return 77
cast client --rpc-url $RPC             # AvalancheGo version string

# Core methods
cast block-number --rpc-url $RPC
cast gas-price --rpc-url $RPC
cast block latest --rpc-url $RPC
```

### 2.1 Method Coverage Matrix

| Method | Expected Response | Actual | Pass/Fail |
|---|---|---|---|
| `eth_chainId` | `0x4d` (77) | TBD | 🔵 |
| `eth_blockNumber` | current block hex | TBD | 🔵 |
| `eth_gasPrice` | > 0 | TBD | 🔵 |
| `eth_getBlockByNumber` | block object | TBD | 🔵 |
| `eth_getTransactionByHash` | tx object | TBD | 🔵 |
| `eth_getTransactionReceipt` | receipt object | TBD | 🔵 |
| `eth_call` | result bytes | TBD | 🔵 |
| `eth_getLogs` | log array | TBD | 🔵 |
| `net_version` | `77` | TBD | 🔵 |
| `web3_clientVersion` | version string | TBD | 🔵 |
| `eth_syncing` | `false` | TBD | 🔵 |

### 2.2 Security: Admin Methods Must Be Blocked

| Method | Expected | Actual |
|---|---|---|
| `admin_peers` | 403 or error | TBD |
| `admin_addPeer` | 403 or error | TBD |
| `debug_traceTransaction` | 403 or blocked | TBD |
| `personal_unlockAccount` | 403 or error | TBD |
| `eth_sendRawTransaction` (private key test) | allowed (broadcast only) | TBD |

---

## 3. LOAD TEST TOOL

Use [k6](https://k6.io/) or Apache Bench (`ab`) for controlled HTTP load.

```javascript
// k6 script: testnet-rpc-load.js
import http from 'k6/http';
import { check, sleep } from 'k6';

const RPC_URL = __ENV.RPC_URL || 'https://rpc.testnet.primewave.xyz';

export let options = {
  stages: [
    { duration: '1m', target: 10 },   // ramp up
    { duration: '3m', target: 50 },   // sustained load
    { duration: '1m', target: 100 },  // burst
    { duration: '2m', target: 50 },   // recovery
    { duration: '1m', target: 0 },    // ramp down
  ],
};

export default function () {
  let payload = JSON.stringify({
    jsonrpc: '2.0',
    method: 'eth_blockNumber',
    params: [],
    id: 1,
  });

  let res = http.post(RPC_URL, payload, {
    headers: { 'Content-Type': 'application/json' },
    timeout: '5s',
  });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'has result': (r) => JSON.parse(r.body).result !== undefined,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  sleep(0.1);
}
```

```bash
# Run the load test
RPC_URL=https://rpc.testnet.primewave.xyz k6 run testnet-rpc-load.js
```

---

## 4. TEST SCENARIOS

### Scenario A: Steady-State Baseline

| Parameter | Value |
|---|---|
| Concurrent clients | 10 |
| Duration | 5 minutes |
| Request mix | 60% eth_blockNumber, 20% eth_getBlockByNumber, 20% eth_call |

**Expected results:**

| Metric | Target | Actual |
|---|---|---|
| p50 latency | < 100ms | TBD |
| p95 latency | < 300ms | TBD |
| p99 latency | < 1000ms | TBD |
| Error rate | < 0.1% | TBD |
| RPS | > 50 | TBD |

### Scenario B: Sustained Load

| Parameter | Value |
|---|---|
| Concurrent clients | 50 |
| Duration | 10 minutes |
| Request mix | Mixed read methods |

**Expected results:**

| Metric | Target | Actual |
|---|---|---|
| p50 latency | < 200ms | TBD |
| p95 latency | < 1000ms | TBD |
| Error rate | < 1% | TBD |
| RPS sustained | Report observed | TBD |

### Scenario C: Burst

| Parameter | Value |
|---|---|
| Concurrent clients | 100 |
| Duration | 2 minutes |
| Request mix | eth_blockNumber only |

**Expected results:**

| Metric | Target | Actual |
|---|---|---|
| p95 latency | < 2000ms | TBD |
| Error rate | < 5% (rate limiting acceptable) | TBD |
| Recovery time | < 30s after burst | TBD |

### Scenario D: Rate Limiting Threshold

Increase load until rate limiting kicks in. Record the threshold.

| Metric | Value |
|---|---|
| Rate limit activation threshold (RPS) | TBD |
| HTTP status on rate limit | TBD (expect 429 or similar) |
| Retry-After header present | TBD |
| Recovery time after throttle | TBD |

---

## 5. INVALID REQUEST BEHAVIOR

Verify the RPC handles malformed input safely:

```bash
# Malformed JSON
curl -s -X POST -H 'Content-Type: application/json' \
  --data 'not json' https://rpc.testnet.primewave.xyz
# Expected: {"jsonrpc":"2.0","error":{"code":-32700,...},"id":null}

# Unknown method
curl -s -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_nonExistentMethod","params":[],"id":1}' \
  https://rpc.testnet.primewave.xyz
# Expected: error code -32601 (Method not found)

# Oversized payload (1MB)
python3 -c "print('{\"jsonrpc\":\"2.0\",\"method\":\"eth_call\",\"params\":[{\"data\":\"' + '0'*2000000 + '\"}]}')" | \
  curl -s -X POST -H 'Content-Type: application/json' --data @- https://rpc.testnet.primewave.xyz
# Expected: 413 Payload Too Large or error
```

| Test | Expected | Actual |
|---|---|---|
| Malformed JSON | RPC error -32700 | TBD |
| Unknown method | RPC error -32601 | TBD |
| Missing params | RPC error -32602 | TBD |
| Oversized payload | 413 / error | TBD |
| Empty body | RPC error or 400 | TBD |

---

## 6. RESULTS SUMMARY

> Fill after test execution

| Scenario | RPS | p50 ms | p95 ms | p99 ms | Error % | Pass/Fail |
|---|---|---|---|---|---|---|
| A: Baseline (10c) | TBD | TBD | TBD | TBD | TBD | 🔵 |
| B: Sustained (50c) | TBD | TBD | TBD | TBD | TBD | 🔵 |
| C: Burst (100c) | TBD | TBD | TBD | TBD | TBD | 🔵 |
| D: Rate limit | TBD | TBD | TBD | TBD | TBD | 🔵 |

**Normal capacity (Req/sec):** TBD
**Degraded threshold (RPS where p95 > 1s):** TBD
**Rate limit threshold (RPS):** TBD
**Test infrastructure:** TBD (cloud client machine specs)
**Test date:** TBD

---

## 7. ACCEPTANCE CRITERIA

| Criterion | Required | Actual | Pass/Fail |
|---|---|---|---|
| All standard methods respond | Yes | TBD | 🔵 |
| eth_chainId == 0x4d | Yes | TBD | 🔵 |
| net_version == 77 | Yes | TBD | 🔵 |
| Admin methods blocked | Yes | TBD | 🔵 |
| Baseline p95 < 300ms | Yes | TBD | 🔵 |
| Burst error rate < 5% | Yes | TBD | 🔵 |
| Recovery within 30s | Yes | TBD | 🔵 |
| Rate limiting active | Yes | TBD | 🔵 |
| Invalid requests fail safely | Yes | TBD | 🔵 |
