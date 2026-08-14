# PW-C11: Monitoring and Alerting Design

**Sprint:** C11 — Production Infrastructure + Validator Keeper + Genesis Finalization
**Status:** COMPLETE
**Date:** 2026-08-14

---

## 1. Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    Sentinel Node                                │
│                                                                  │
│  ┌──────────────┐    ┌─────────────┐    ┌──────────────────┐   │
│  │  Prometheus  │◀───│  Keeper     │    │   AvalancheGo    │   │
│  │  (scrape)    │    │  :8080/met  │    │   /ext/metrics   │   │
│  └──────┬───────┘    └─────────────┘    └──────────────────┘   │
│         │                                         ▲             │
│         │ metrics                                 │             │
│         │                              ┌──────────┘             │
│         ▼                              │ node-exporter          │
│  ┌──────────────┐    ┌─────────────────┴───┐                   │
│  │   Grafana    │    │  Node Exporter       │                   │
│  │  (dashboards)│    │  (system metrics)    │                   │
│  └──────┬───────┘    └─────────────────────┘                   │
│         │                                                        │
│         ▼                                                        │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Alertmanager → PagerDuty / Slack / Email                │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────┘
```

---

## 2. Prometheus Scrape Targets

```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'primewave-keeper'
    static_configs:
      - targets: ['localhost:8080']
    scrape_interval: 15s

  - job_name: 'avalanchego-validator-1'
    static_configs:
      - targets: ['validator-1:9650']
    metrics_path: /ext/metrics

  - job_name: 'avalanchego-validator-2'
    static_configs:
      - targets: ['validator-2:9650']
    metrics_path: /ext/metrics

  # Repeat for all 5 validators and 2 RPC nodes

  - job_name: 'node-exporter'
    static_configs:
      - targets:
        - validator-1:9100
        - validator-2:9100
        - validator-3:9100
        - validator-4:9100
        - validator-5:9100
        - rpc-1:9100
        - rpc-2:9100
        - sentinel:9100

rule_files:
  - 'alerts.yml'
```

---

## 3. Alert Rules

### 3.1 Critical Alerts (Page immediately)

```yaml
# alerts.yml
groups:
  - name: primewave.critical
    rules:

    - alert: KeeperDown
      expr: up{job="primewave-keeper"} == 0
      for: 2m
      labels:
        severity: critical
      annotations:
        summary: "Keeper is DOWN"
        description: "Validator sync keeper unreachable for > 2 minutes. Validators may fall out of sync."

    - alert: ValidatorSyncLag
      expr: time() - primewave_keeper_last_poll_timestamp_seconds > 300
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: "Keeper has not polled in > 5 minutes"
        description: "Last poll was {{ $value | humanizeDuration }} ago."

    - alert: PendingSyncsHigh
      expr: primewave_keeper_pending_syncs > 5
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "{{ $value }} validators have pending syncs"
        description: "Keeper cannot sync validators — manual intervention needed."

    - alert: ValidatorNodeDown
      expr: up{job=~"avalanchego-validator-.*"} == 0
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "Validator node {{ $labels.instance }} is DOWN"

    - alert: DiskSpaceCritical
      expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.10
      for: 0m
      labels:
        severity: critical
      annotations:
        summary: "Disk space < 10% on {{ $labels.instance }}"
        description: "Available: {{ $value | humanizePercentage }}. Node may stop producing blocks."
```

### 3.2 Warning Alerts (Ticket, non-paging)

```yaml
  - name: primewave.warning
    rules:

    - alert: KeeperSyncFailures
      expr: rate(primewave_keeper_sync_failures_total[5m]) > 0.1
      for: 2m
      labels:
        severity: warning
      annotations:
        summary: "Keeper sync failure rate > 0.1/s ({{ $value | humanize }}/s)"

    - alert: DiskSpaceWarning
      expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.20
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Disk space < 20% on {{ $labels.instance }}"

    - alert: BlockProductionSlow
      expr: rate(avalanche_network_msgs_received_sum{chain=~".*primewave.*"}[5m]) == 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "No new blocks in 5 minutes"

    - alert: PeerCountLow
      expr: avalanche_network_peers < 2
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Validator {{ $labels.instance }} has < 2 peers"

    - alert: MemoryPressure
      expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.15
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Memory < 15% available on {{ $labels.instance }}"
```

---

## 4. Grafana Dashboards

### 4.1 Keeper Health Dashboard

**Panels:**

| Panel | Metric | Visualization |
|-------|--------|---------------|
| Keeper Status | Health endpoint status | Status indicator |
| Syncs/s | `rate(sync_successes_total[5m])` | Time series |
| Failure Rate | `rate(sync_failures_total[5m])` | Time series |
| Pending Syncs | `pending_syncs` | Gauge |
| Managed Validators | `managed_validators` | Stat |
| Last Poll Age | `time() - last_poll_timestamp_seconds` | Gauge |
| Total Syncs (all time) | `sync_successes_total` | Stat |
| Success Rate | `successes / attempts * 100` | Gauge |

### 4.2 Network Health Dashboard

**Panels:**

| Panel | Metric | Visualization |
|-------|--------|---------------|
| Validator Count (up) | `count(up{job=~"avalanche.*"} == 1)` | Stat |
| Block Height | `avalanche_network_msgs_received_count` | Time series |
| Peer Count per Node | `avalanche_network_peers` | Time series |
| TX Throughput | `rate(avalanche_chain_txs_accepted_total[1m])` | Time series |
| Block Time | Derived from block height delta | Time series |

### 4.3 System Health Dashboard

**Panels:**

| Panel | Metric | Visualization |
|-------|--------|---------------|
| CPU Usage | `100 - (avg(iowait) * 100)` | Heat map per node |
| Memory Usage | `(total - available) / total` | Time series per node |
| Disk Usage | `(size - avail) / size` | Gauge per node |
| Network I/O | `rate(bytes_sent[1m]) + rate(bytes_recv[1m])` | Time series |
| Load Average | `node_load15` | Time series |

---

## 5. Log Monitoring

The keeper emits structured JSON logs (one per line) to stdout. All logs are captured by `journald` and can be queried:

```bash
# All keeper logs
journalctl -u primewave-keeper -f

# Only sync failures
journalctl -u primewave-keeper --grep='"event":"keeper.*failed"' -n 50

# Only errors
journalctl -u primewave-keeper -p err -n 100
```

### Log Fields

All keeper logs include:
```json
{
  "timestamp":   "2026-08-14T12:00:00.000Z",
  "environment": "production",
  "chainId":     "73571",
  "component":   "primewave-keeper",
  "severity":    "INFO",
  "event":       "keeper.sync.confirmed",
  "validationId": "0x...",
  "txHash":       "0x...",
  "blockNumber":  12345
}
```

---

## 6. On-Call Escalation Procedure

### Alert Severity Tiers

| Tier | Criteria | Response Time | Escalation |
|------|----------|---------------|------------|
| P1 (Critical) | Keeper down, validator down, disk < 10% | 15 minutes | Page on-call → EMS (if governance action needed) |
| P2 (Warning) | Sync failures, disk < 20%, peer count low | 2 hours | Slack notification |
| P3 (Info) | Slow tx throughput, minor latency | Next business day | Daily review |

### P1 Runbook (Keeper Down)

1. `systemctl status primewave-keeper`
2. `journalctl -u primewave-keeper -n 100`
3. Check gas balance: `cast balance $KEEPER_ADDRESS --rpc-url $RPC`
4. If gas: `systemctl start primewave-keeper`
5. If RPC issue: `./scripts/health-check.sh`
6. Manual sync: `forge send $REGISTRY "syncAll()" --private-key $ANY_KEY --rpc-url $RPC`
7. Escalate to EMS if governance action is needed (e.g., emergency pause)

---

## 7. Alertmanager Configuration

```yaml
# alertmanager.yml
route:
  receiver: default
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - match:
        severity: critical
      receiver: pagerduty
      repeat_interval: 1h

receivers:
  - name: default
    slack_configs:
      - api_url: '$SLACK_WEBHOOK_URL'
        channel: '#primewave-alerts'
        title: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: pagerduty
    pagerduty_configs:
      - routing_key: '$PAGERDUTY_KEY'
        description: '{{ .GroupLabels.alertname }}: {{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
```

---

## 8. Deployment

Run on Sentinel Node:
```bash
# Prometheus
docker run -d \
  -v /etc/primewave/prometheus:/etc/prometheus \
  -p 9090:9090 \
  prom/prometheus:latest

# Grafana
docker run -d \
  -p 3000:3000 \
  grafana/grafana:latest

# Alertmanager
docker run -d \
  -v /etc/primewave/alertmanager:/etc/alertmanager \
  -p 9093:9093 \
  prom/alertmanager:latest

# Node Exporter (on each node)
docker run -d \
  --net=host \
  prom/node-exporter:latest
```
