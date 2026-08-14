# PW-C14: Monitoring and Alerting
**Sprint:** PW-C14
**Environment:** TESTNET ONLY
**Reference:** Section 27 of PW-C14 spec

---

## 1. Monitoring Stack

| Component | Tool | Version | Purpose |
|---|---|---|---|
| Metrics collection | Prometheus | 2.x | Scrape all node metrics |
| Visualization | Grafana | 10.x | Dashboards |
| Alerting | Alertmanager | 0.26.x | Route alerts to email/Slack/PagerDuty |
| System metrics | node_exporter | 1.8.x | CPU, RAM, disk, network |
| PostgreSQL metrics | postgres_exporter | 0.15.x | DB health and query stats |

All monitoring runs on the **sentinel node** (internal network only, not publicly exposed).

---

## 2. Metrics

### 2.1 AvalancheGo Metrics (from `/ext/metrics`)

| Metric | Alert Threshold | Description |
|---|---|---|
| `avalanche_network_peers` | < 1 for 5m | Peer count |
| `avalanche_health_checks_failed_count` | > 0 for 2m | Failed health checks |
| Node block height | No change for 10m | Chain stalled |
| `avalanche_X_db_size_sum` | — | DB growth |

### 2.2 Keeper Metrics (from port 8080 `/metrics`)

| Metric | Alert Threshold | Description |
|---|---|---|
| `primewave_keeper_last_poll_timestamp_seconds` | stale > 120s | Keeper not polling |
| `primewave_keeper_sync_failures_total` | rising | Sync failures |
| `primewave_keeper_pending_syncs` | > 10 for 30m | Queue backlog |

### 2.3 Indexer Metrics (derived from `/stats`)

| Metric | Alert Threshold | Description |
|---|---|---|
| `chainHead - latestIndexed` | > 100 blocks for 10m | Sync lag |
| `isSynced` | false for 5m | Not synced |

### 2.4 System Metrics (node_exporter)

| Metric | Alert Threshold | Description |
|---|---|---|
| Disk space | < 15% free (warn), < 5% (critical) | Storage |
| Memory | > 90% for 10m | RAM pressure |
| CPU | > 95% for 15m | CPU pressure |
| Network error rate | > 1% | Interface errors |

---

## 3. Alert Routing

### 3.1 Alertmanager Configuration Template

```yaml
# /etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  receiver: 'primewave-testnet-team'
  group_by: ['alertname', 'environment']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h

  routes:
    - match:
        severity: critical
      receiver: 'primewave-oncall'
      repeat_interval: 15m

receivers:
  - name: 'primewave-testnet-team'
    slack_configs:
      - api_url: '__REPLACE_SLACK_WEBHOOK__'
        channel: '#primewave-testnet-alerts'
        title: 'PrimeWave Testnet Alert'

  - name: 'primewave-oncall'
    slack_configs:
      - api_url: '__REPLACE_SLACK_WEBHOOK__'
        channel: '#primewave-oncall'
    pagerduty_configs:
      - service_key: '__REPLACE_PAGERDUTY_KEY__'
```

---

## 4. Grafana Dashboards

### 4.1 Testnet Overview Dashboard

Panels:
- Current block height (all nodes)
- Block production rate (blocks/min)
- Active validators
- Total transactions (24h)
- RPC request rate
- Indexer sync lag
- Keeper poll rate

### 4.2 Node Health Dashboard

Per-node panels:
- AvalancheGo uptime
- Peer count
- Memory usage
- Disk usage
- CPU usage
- Network I/O

### 4.3 Protocol Dashboard

- RewardVault: totalFunded, totalEmitted, balance
- ValidatorFeeVault: total fees accumulated, per-validator split
- FeeDistributor: distributions (70/20/10) over time
- Keeper: sync operations per hour, failure rate

---

## 5. Log Management

### 5.1 What to Log

```
timestamp | service | severity | event | public identifiers
```

Example (keeper):
```json
{"timestamp":"2026-08-14T17:00:00Z","service":"keeper","severity":"INFO","event":"syncValidator.submitted","validatorId":"0xabc...","txHash":"0xdef..."}
```

### 5.2 What Never to Log

- Private keys
- Seed phrases
- Database passwords
- RPC auth tokens
- Session cookies

### 5.3 Log Retention

| Service | Retention | Location |
|---|---|---|
| AvalancheGo | 14 days | `/var/log/avalanchego/` + systemd journal |
| Indexer | 14 days | systemd journal |
| Keeper | 14 days | systemd journal |
| nginx | 30 days | `/var/log/nginx/` |
| Prometheus | 15 days | Prometheus TSDB |

---

## 6. Health Check Schedule

| Check | Frequency | Tool |
|---|---|---|
| Node liveness | 15s | Prometheus scrape |
| Block height advancing | 1m | Alert rule |
| Indexer sync | 1m | Alert rule |
| Keeper alive | 1m | Prometheus scrape |
| DB health | 30s | postgres_exporter |
| Full health script | 15m | Cron → `testnet-health-check.sh` |
| Security audit | Weekly | Manual |
| Backup verification | Daily | Cron → backup script |

---

## 7. On-Call Runbook (Testnet)

### Alert: NodeDown

1. SSH to affected node: `ssh validator-N`
2. Check logs: `journalctl -u primewave-testnet-node -n 50`
3. Restart: `systemctl restart primewave-testnet-node`
4. If disk full: `df -h` → extend volume or prune logs
5. If repeated crash: check avalanchego logs for panic/error and file issue

### Alert: IndexerSyncLag

1. Check indexer health: `curl http://localhost:4000/health`
2. Check logs: `journalctl -u primewave-testnet-indexer -n 50`
3. Check DB: `psql primewave_testnet -c "SELECT MAX(number) FROM blocks"`
4. Restart if stalled: `systemctl restart primewave-testnet-indexer`

### Alert: KeeperStalled

1. Check: `curl http://localhost:8080/health`
2. Check logs: `journalctl -u primewave-testnet-keeper -n 100`
3. Restart: `systemctl restart primewave-testnet-keeper`
