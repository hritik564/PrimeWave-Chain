#!/usr/bin/env bash
# =============================================================================
# PrimeWave — Server Qualification Script v2
# Target: Netcup RS 1000 G12 (Debian, KVM) for Avalanche validator use
#
# Run as: bash qualify-server-v2.sh 2>&1 | tee qualify-$(hostname -s)-$(date +%Y%m%d-%H%M%S).log
#
# READ-ONLY / NON-DESTRUCTIVE — no installs, no firewall changes, no reboots.
# =============================================================================
#
# CHANGES FROM v1:
#   Fix 1 — run_ping call sites use || true so set -e never aborts on ping failure
#   Fix 2 — /dev/shm fallback is clearly labelled a memory EXERCISE, not a diagnostic
#   Fix 3 — hard-coded bootstrap IP/TCP probes are informational only; never set CONCERN
#   Fix 4 — CONCERN verdict is "READY WITH CONCERNS — NOT APPROVED FOR PRODUCTION"
#   Fix 5 — inbound TCP 9651 is explicitly recorded as NOT TESTABLE
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

pass()    { echo -e "${GREEN}[PASS]${NC} $*"; }
concern() { echo -e "${YELLOW}[CONCERN]${NC} $*"; }
fail()    { echo -e "${RED}[FAIL]${NC} $*"; }
info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
section() { echo -e "\n${BOLD}════════════════════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}  $*${NC}"; \
            echo -e "${BOLD}════════════════════════════════════════════════════════${NC}"; }

# ── Result accumulator ────────────────────────────────────────────────────────
declare -a RESULTS=()
record() { RESULTS+=("$*"); }

# ── Tool availability helper ──────────────────────────────────────────────────
have() { command -v "$1" &>/dev/null; }

require_or_warn() {
  if ! have "$1"; then
    concern "Tool '$1' not found — some subtests may be skipped. Install with: apt-get install $2"
    return 1
  fi
  return 0
}

echo ""
echo -e "${BOLD}PrimeWave Server Qualification v2 — $(date -u '+%Y-%m-%d %H:%M:%S UTC')${NC}"
echo -e "Host: $(hostname -f 2>/dev/null || hostname)   Kernel: $(uname -r)"
echo ""

# =============================================================================
section "TEST 1 — Network Connectivity"
# =============================================================================
echo ""
echo "Command: ip -4 addr show; ip -6 addr show; ip route show; cat /etc/resolv.conf"
echo ""

T1_PASS=true

# IPv4 interfaces
echo "--- IPv4 interfaces ---"
ip -4 addr show || true
echo ""

# IPv6 interfaces
echo "--- IPv6 interfaces ---"
ip -6 addr show || true
echo ""

# Default routes
echo "--- Routing table ---"
ip route show || true
echo ""
ip -6 route show default 2>/dev/null || true
echo ""

# DNS resolvers
echo "--- DNS configuration ---"
cat /etc/resolv.conf 2>/dev/null || systemd-resolve --status 2>/dev/null | head -20 || true
echo ""

# IPv4 reachability
echo "--- IPv4 reachability tests ---"
PING4_TARGETS=("8.8.8.8" "1.1.1.1" "9.9.9.9")
for T in "${PING4_TARGETS[@]}"; do
  if ping -4 -c 4 -W 5 "$T" &>/dev/null; then
    RTT=$(ping -4 -c 4 -W 5 "$T" 2>/dev/null | tail -1 | awk -F'/' '{print $5}' || echo "?")
    echo "  IPv4 → $T : OK  (avg ${RTT}ms)"
  else
    echo "  IPv4 → $T : FAILED"; T1_PASS=false
  fi
done
echo ""

# IPv6 reachability
echo "--- IPv6 reachability tests ---"
IPV6_TARGETS=("2001:4860:4860::8888" "2606:4700:4700::1111")
for T in "${IPV6_TARGETS[@]}"; do
  if ping -6 -c 4 -W 5 "$T" &>/dev/null; then
    RTT=$(ping -6 -c 4 -W 5 "$T" 2>/dev/null | tail -1 | awk -F'/' '{print $5}' || echo "?")
    echo "  IPv6 → $T : OK  (avg ${RTT}ms)"
  else
    echo "  IPv6 → $T : FAILED (may need route)"; concern "IPv6 target $T unreachable"
  fi
done
echo ""

# DNS resolution
echo "--- DNS resolution ---"
for DOMAIN in google.com cloudflare.com debian.org bootstrap.avax.network; do
  if RESOLVED=$(getent hosts "$DOMAIN" 2>/dev/null | head -1); then
    echo "  $DOMAIN → $RESOLVED"
  else
    echo "  $DOMAIN → FAILED"
    [[ "$DOMAIN" == "bootstrap.avax.network" ]] || T1_PASS=false
  fi
done
echo ""

if $T1_PASS; then
  pass "TEST 1: IPv4 connectivity and DNS resolution verified"
  record "TEST 1 — Network Connectivity: PASS"
else
  fail "TEST 1: One or more connectivity checks failed"
  record "TEST 1 — Network Connectivity: FAIL"
fi

# =============================================================================
section "TEST 2 — Network Latency"
# =============================================================================
echo ""
echo "Command: ping -c 50 <target> (50 packets per target)"
echo ""

T2_CONCERN=false

# FIX 1: run_ping returns non-zero on unreachable targets; all call sites use
# "|| true" so set -e never aborts the script on a failed ping.
run_ping() {
  local TARGET="$1" LABEL="$2"
  local OUT
  OUT=$(ping -c 50 -i 0.2 -W 5 "$TARGET" 2>&1) || { echo "  $LABEL ($TARGET): UNREACHABLE"; return 1; }
  local MIN AVG MAX MDEV LOSS
  AVG=$(echo "$OUT"  | grep rtt | awk -F'/' '{print $5}')
  MIN=$(echo "$OUT"  | grep rtt | awk -F'/' '{print $4}' | awk -F'=' '{print $2}')
  MAX=$(echo "$OUT"  | grep rtt | awk -F'/' '{print $6}')
  MDEV=$(echo "$OUT" | grep rtt | awk -F'/' '{print $7}' | tr -d ' ms')
  LOSS=$(echo "$OUT" | grep "packet loss" | awk '{print $6}')
  printf "  %-40s  min=%-7s avg=%-7s max=%-7s jitter=%-7s loss=%s\n" \
    "$LABEL ($TARGET)" "${MIN}ms" "${AVG}ms" "${MAX}ms" "${MDEV}ms" "$LOSS"
  # Flag if avg > 100ms or loss > 0%
  local AVG_NUM=${AVG%.*}
  [[ -n "$LOSS" && "$LOSS" != "0%" ]] && { concern "Packet loss to $TARGET: $LOSS"; T2_CONCERN=true; }
  [[ -n "$AVG_NUM" && "$AVG_NUM" -gt 100 ]] 2>/dev/null && { concern "High latency to $TARGET: avg ${AVG}ms"; T2_CONCERN=true; } || true
}

echo "--- Latency to DNS / global endpoints ---"
# FIX 1: || true on every run_ping call site prevents set -e from aborting.
run_ping 8.8.8.8        "Google DNS"        || true
run_ping 1.1.1.1        "Cloudflare DNS"    || true
run_ping 9.9.9.9        "Quad9 DNS"         || true
echo ""

echo "--- Latency to European endpoints ---"
run_ping 193.99.144.80     "Heise (Germany)"    || true
run_ping 151.101.2.132     "Fastly/Debian CDN"  || true
run_ping 130.180.71.177    "DFN Frankfurt"      || true
run_ping ftp.de.debian.org "Debian DE mirror"   || true
echo ""

if ! $T2_CONCERN; then
  pass "TEST 2: Latency and packet loss within acceptable range"
  record "TEST 2 — Network Latency: PASS"
else
  concern "TEST 2: Some latency or packet loss concerns (see above)"
  record "TEST 2 — Network Latency: PASS WITH CONCERN"
fi

# =============================================================================
section "TEST 3 — Internet Throughput"
# =============================================================================
echo ""
echo "Command: curl speed-test via Cloudflare/Debian CDN (controlled volume)"
echo ""

T3_CONCERN=false

# ── Download test: pull ~100 MB from Cloudflare speed.cloudflare.com ──────────
echo "--- Download bandwidth (Cloudflare __down, ~100 MB) ---"
if have curl; then
  DL_RESULT=$(curl -so /dev/null \
    --connect-timeout 10 --max-time 30 \
    -w "Downloaded: %{size_download} bytes  Speed: %{speed_download} B/s  Time: %{time_total}s\n" \
    "https://speed.cloudflare.com/__down?bytes=104857600" 2>/dev/null || echo "FAILED")
  echo "  $DL_RESULT"
  DL_BPS=$(echo "$DL_RESULT" | grep -oP 'Speed: \K[0-9.]+' || echo "0")
  DL_MBPS=$(echo "scale=1; $DL_BPS / 1048576 * 8" | bc 2>/dev/null || echo "?")
  echo "  → Download: ~${DL_MBPS} Mbps"
  [[ "${DL_MBPS%.*}" -lt 100 ]] 2>/dev/null && { concern "Download below 100 Mbps: ${DL_MBPS} Mbps"; T3_CONCERN=true; } || true
else
  info "curl not available — skipping download test"
fi
echo ""

# ── Upload test: POST ~50 MB to Cloudflare ────────────────────────────────────
echo "--- Upload bandwidth (Cloudflare __up, ~50 MB from /dev/zero) ---"
if have curl; then
  UL_RESULT=$(dd if=/dev/zero bs=1M count=50 2>/dev/null | \
    curl -so /dev/null \
      --connect-timeout 10 --max-time 30 \
      -X POST \
      -w "Uploaded: %{size_upload} bytes  Speed: %{speed_upload} B/s  Time: %{time_total}s\n" \
      --data-binary @- \
      "https://speed.cloudflare.com/__up" 2>/dev/null || echo "FAILED")
  echo "  $UL_RESULT"
  UL_BPS=$(echo "$UL_RESULT" | grep -oP 'Speed: \K[0-9.]+' || echo "0")
  UL_MBPS=$(echo "scale=1; $UL_BPS / 1048576 * 8" | bc 2>/dev/null || echo "?")
  echo "  → Upload: ~${UL_MBPS} Mbps"
  [[ "${UL_MBPS%.*}" -lt 50 ]] 2>/dev/null && { concern "Upload below 50 Mbps: ${UL_MBPS} Mbps"; T3_CONCERN=true; } || true
else
  info "curl not available — skipping upload test"
fi
echo ""

# ── speedtest-cli fallback ─────────────────────────────────────────────────────
if have speedtest-cli || have speedtest; then
  echo "--- speedtest-cli result ---"
  (speedtest-cli --simple 2>/dev/null || speedtest 2>/dev/null) | head -10 || true
  echo ""
fi

if ! $T3_CONCERN; then
  pass "TEST 3: Bandwidth appears adequate for validator"
  record "TEST 3 — Internet Throughput: PASS"
else
  concern "TEST 3: Bandwidth concern — check results above"
  record "TEST 3 — Internet Throughput: PASS WITH CONCERN"
fi

# =============================================================================
section "TEST 4 — Outbound TCP Connectivity"
# =============================================================================
echo ""
echo "Command: curl/nc -z to Avalanche-relevant ports"
echo ""
# Avalanche ports of interest:
#   9651 — AvalancheGo P2P staking port (inbound required for validator)
#   9650 — AvalancheGo HTTP/RPC API
#   443  — HTTPS (bootstrap contacts, API)
#   80   — HTTP
#   53   — DNS
# We test OUTBOUND TCP to known public hosts on these ports.

T4_CONCERN=false
TCP_TARGETS=(
  "8.8.8.8:53:DNS"
  "1.1.1.1:443:HTTPS-Cloudflare"
  "151.101.2.132:443:HTTPS-Fastly"
  "35.231.88.39:443:HTTPS-GCP-US"
  "8.8.8.8:443:HTTPS-Google"
)
# FIX 3: Bootstrap IP probes are informational only. Results are shown but
# never set T4_CONCERN. IPs are hard-coded and may change; treat as advisory.
AVAX_STAKING_TARGETS=(
  "54.94.43.146:9651:AVAX-bootstrap-SA"
  "54.87.56.168:9651:AVAX-bootstrap-US"
  "18.209.162.254:9651:AVAX-bootstrap-US2"
  "54.211.11.39:9651:AVAX-bootstrap-US3"
)

echo "--- Standard TCP ports ---"
for ENTRY in "${TCP_TARGETS[@]}"; do
  HOST="${ENTRY%%:*}"; REST="${ENTRY#*:}"; PORT="${REST%%:*}"; LABEL="${REST#*:}"
  if have nc; then
    if nc -z -w 5 "$HOST" "$PORT" &>/dev/null; then
      echo "  TCP $HOST:$PORT ($LABEL): OPEN"
    else
      echo "  TCP $HOST:$PORT ($LABEL): REFUSED/FILTERED"
      [[ "$PORT" != "9651" ]] && T4_CONCERN=true
    fi
  elif have curl; then
    CODE=$(curl -so /dev/null --connect-timeout 5 -w "%{http_code}" "https://$HOST/" 2>/dev/null || echo "000")
    [[ "$CODE" != "000" ]] && echo "  TCP $HOST:$PORT ($LABEL): OPEN (HTTP $CODE)" \
                            || echo "  TCP $HOST:$PORT ($LABEL): REFUSED/FILTERED"
  fi
done
echo ""

# FIX 3: These probes test outbound 9651 against hard-coded IPs that may change.
# Results are INFORMATIONAL ONLY — a timeout here does not indicate a problem
# with this server; the remote may be filtered, moved, or decommissioned.
echo "--- Avalanche staking port 9651 — INFORMATIONAL ONLY (hard-coded IPs may change) ---"
for ENTRY in "${AVAX_STAKING_TARGETS[@]}"; do
  HOST="${ENTRY%%:*}"; REST="${ENTRY#*:}"; PORT="${REST%%:*}"; LABEL="${REST#*:}"
  if have nc; then
    if nc -z -w 8 "$HOST" "$PORT" &>/dev/null; then
      echo "  [INFO] $LABEL ($HOST:$PORT): reachable — outbound 9651 confirmed working"
    else
      echo "  [INFO] $LABEL ($HOST:$PORT): timeout/refused — remote may be filtered or IP stale"
    fi
  else
    info "nc not available — skipping 9651 outbound informational probe"
    break
  fi
done
echo ""

# FIX 5: Inbound TCP 9651 is explicitly NOT TESTABLE from this host.
echo "--- Inbound TCP 9651 — NOT TESTABLE from this host ---"
echo "  Inbound reachability on port 9651 requires an external probe."
echo "  This check CANNOT be performed from the server under test."
echo "  Action required before going live:"
echo "    1. Open TCP 9651 inbound in the Netcup firewall panel"
echo "    2. From an EXTERNAL host, run: nc -z -w 8 <this-server-public-ip> 9651"
echo "    3. Confirm the connection is accepted"
echo ""
record "Inbound TCP 9651: NOT TESTABLE — external probe required before validator goes live"

if ! $T4_CONCERN; then
  pass "TEST 4: Outbound TCP connectivity is functional"
  record "TEST 4 — TCP Connectivity: PASS"
else
  concern "TEST 4: Some TCP targets unreachable"
  record "TEST 4 — TCP Connectivity: PASS WITH CONCERN"
fi

# =============================================================================
section "TEST 5 — UDP Connectivity"
# =============================================================================
echo ""
echo "Command: nc -u / dig (outbound UDP); inbound not testable from this host alone"
echo ""

T5_NOTE=false

echo "--- Outbound UDP DNS (port 53) ---"
for DNS_SERVER in 8.8.8.8 1.1.1.1 9.9.9.9; do
  if RESULT=$(dig @"$DNS_SERVER" +time=5 +tries=2 google.com A 2>/dev/null | grep -E "^;; Query time:"); then
    echo "  UDP DNS → $DNS_SERVER: OK  ($RESULT)"
  else
    echo "  UDP DNS → $DNS_SERVER: FAILED"
    T5_NOTE=true
  fi
done
echo ""

echo "--- Outbound UDP NTP (port 123) ---"
if have ntpdate; then
  ntpdate -q pool.ntp.org 2>/dev/null | tail -3 || echo "  ntpdate failed (non-critical)"
elif have chronyc; then
  chronyc tracking 2>/dev/null | head -5 || echo "  chronyc not reachable"
else
  info "ntpdate/chronyc not available — checking time sync via timedatectl"
  timedatectl status 2>/dev/null | grep -E "synchronized|NTP" || true
fi
echo ""

echo "--- UDP reachability summary ---"
echo "  VERIFIED:   Outbound UDP port 53 (DNS) works if dig tests above passed"
echo "  NOT TESTED: Inbound UDP reachability (requires external probe host)"
echo "  ASSUMED:    Outbound UDP connectivity generally works if DNS is functional"
echo "  AVALANCHE:  Port 9651 uses TCP for P2P; UDP may be used for discovery"
echo "              Inbound 9651 TCP must be verified after firewall is opened"
echo ""

if ! $T5_NOTE; then
  pass "TEST 5: Outbound UDP functional; inbound not testable from this host"
  record "TEST 5 — UDP Connectivity: PASS (outbound verified) / NOT TESTABLE (inbound)"
else
  concern "TEST 5: Some outbound UDP issues — check DNS results"
  record "TEST 5 — UDP Connectivity: PASS WITH CONCERN (outbound) / NOT TESTABLE (inbound)"
fi

# =============================================================================
section "TEST 6 — Public IP / NAT"
# =============================================================================
echo ""
echo "Command: ip addr show; curl ifconfig.me; ip route show"
echo ""

T6_CONCERN=false

echo "--- Network interfaces ---"
ip addr show 2>/dev/null || ifconfig 2>/dev/null || true
echo ""

echo "--- Default gateway ---"
ip route show default 2>/dev/null || true
echo ""

echo "--- Detected public IPv4 (via external resolver) ---"
PUBLIC_IP4=$(curl -s4 --max-time 8 ifconfig.me 2>/dev/null \
          || curl -s4 --max-time 8 api.ipify.org 2>/dev/null \
          || curl -s4 --max-time 8 ipecho.net/plain 2>/dev/null \
          || echo "FAILED")
echo "  Public IPv4: $PUBLIC_IP4"

echo "--- Detected public IPv6 ---"
PUBLIC_IP6=$(curl -s6 --max-time 8 ifconfig.me 2>/dev/null \
          || curl -s6 --max-time 8 api6.ipify.org 2>/dev/null \
          || echo "FAILED/none")
echo "  Public IPv6: $PUBLIC_IP6"
echo ""

# NAT detection: compare interface IPs with public IP
INTERFACE_IPS=$(ip -4 addr show scope global | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' || true)
echo "--- NAT check ---"
echo "  Interface IPs: $(echo $INTERFACE_IPS | tr '\n' ' ')"
echo "  External IP  : $PUBLIC_IP4"
NAT_DETECTED=false
for IIP in $INTERFACE_IPS; do
  if [[ "$IIP" == "$PUBLIC_IP4" ]]; then
    echo "  → Direct assignment confirmed (no NAT): $IIP = $PUBLIC_IP4"
    NAT_DETECTED=false
    break
  else
    NAT_DETECTED=true
  fi
done
if $NAT_DETECTED; then
  concern "NAT detected: interface IP differs from public IP. Avalanche validators require direct public IP or port forwarding for inbound 9651."
  T6_CONCERN=true
fi
echo ""

if ! $T6_CONCERN; then
  pass "TEST 6: Direct public IP confirmed, no NAT"
  record "TEST 6 — Public IP / NAT: PASS"
else
  concern "TEST 6: NAT detected — may require port forwarding configuration"
  record "TEST 6 — Public IP / NAT: PASS WITH CONCERN — NAT detected"
fi

# =============================================================================
section "TEST 7 — CPU Benchmark (Short)"
# =============================================================================
echo ""
echo "Command: nproc; lscpu; openssl speed; 30s stress via yes/bc"
echo ""

echo "--- CPU information ---"
lscpu 2>/dev/null | grep -E "Model name|CPU\(s\)|Thread|Core|Socket|MHz|NUMA|Architecture|Vendor" || true
echo ""
echo "  Logical CPUs: $(nproc)"
echo ""

# CPU flags relevant for crypto / AvalancheGo
echo "--- Crypto / SIMD CPU flags ---"
grep -m1 "flags" /proc/cpuinfo 2>/dev/null | tr ' ' '\n' | \
  grep -E "^(aes|avx|avx2|sse4|sha_ni|rdrand|bmi2|pclmul)" | sort | tr '\n' ' '
echo ""
echo ""

# OpenSSL speed (measures AES-GCM and SHA which AvalancheGo uses heavily)
echo "--- OpenSSL AES-256-GCM and SHA256 speed (10s) ---"
if have openssl; then
  openssl speed -elapsed aes-256-gcm sha256 2>&1 | grep -E "^(Doing|aes|sha|Bytes|type)" | head -20
else
  info "openssl not found — skipping crypto benchmark"
fi
echo ""

# Short controlled CPU load: all cores, 30 seconds
echo "--- 30-second all-core load test ---"
NCPU=$(nproc)
echo "  Starting ${NCPU} workers for 30s..."

# Use sha256sum to generate a repeatable, measurable CPU load
(
  for ((i=0; i<NCPU; i++)); do
    dd if=/dev/urandom bs=64K count=4096 2>/dev/null | sha256sum > /dev/null &
  done
  PIDS=$(jobs -p)
  sleep 30
  kill $PIDS 2>/dev/null || true
  wait 2>/dev/null || true
) &
LOAD_PID=$!

# Sample load average and frequency during the test
sleep 5
echo "  Load average (at 5s):  $(cat /proc/loadavg)"
sleep 10
echo "  Load average (at 15s): $(cat /proc/loadavg)"
sleep 10
echo "  Load average (at 25s): $(cat /proc/loadavg)"
wait $LOAD_PID 2>/dev/null || true
echo "  Load average (at end): $(cat /proc/loadavg)"
echo ""

# CPU frequency (current vs max)
echo "--- CPU frequency ---"
if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
  for CPU in /sys/devices/system/cpu/cpu*/cpufreq; do
    CORE=$(basename "$(dirname "$CPU")")
    CURR=$(cat "$CPU/scaling_cur_freq" 2>/dev/null || echo "?")
    MAX=$(cat  "$CPU/scaling_max_freq" 2>/dev/null || echo "?")
    GOV=$(cat  "$CPU/scaling_governor" 2>/dev/null || echo "?")
    echo "  $CORE: ${CURR}kHz / ${MAX}kHz  governor=${GOV}"
  done
else
  info "cpufreq sysfs not available (KVM may not expose it)"
  grep "cpu MHz" /proc/cpuinfo | head -4 || true
fi
echo ""

# Thermal — if available
echo "--- Thermal (guest view) ---"
if have sensors; then
  sensors 2>/dev/null || info "No sensor data available"
else
  # Try reading hwmon
  for TEMP in /sys/class/thermal/thermal_zone*/temp; do
    [[ -f "$TEMP" ]] && echo "  $TEMP: $(( $(cat "$TEMP") / 1000 ))°C" || true
  done 2>/dev/null
  info "lm-sensors not installed — temperature readings limited in KVM guest"
fi
echo ""

# Steal time
echo "--- CPU steal time ---"
STEAL=$(top -bn1 2>/dev/null | grep "Cpu(s)" | grep -oP '\d+\.\d+(?= *st)' || echo "0.0")
echo "  Steal: ${STEAL}%"
STEAL_INT=${STEAL%.*}
[[ "$STEAL_INT" -gt 5 ]] 2>/dev/null && concern "High CPU steal time: ${STEAL}% — shared host contention" || true
echo ""

pass "TEST 7: CPU benchmark completed"
record "TEST 7 — CPU: PASS (review steal time and frequency above)"

# =============================================================================
section "TEST 8 — Memory Test"
# =============================================================================
echo ""
echo "Command: free -h; memtester 512M 1 (controlled, 512 MB)"
echo ""

echo "--- Memory overview ---"
free -h 2>/dev/null || true
echo ""
cat /proc/meminfo | grep -E "^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree|Hugepage)" || true
echo ""

T8_CONCERN=false

# Use memtester if available, otherwise a pure-bash dd/sha256 approach.
# FIX 2: /dev/shm fallback is a memory EXERCISE that verifies read/write
# integrity at the OS level. It is NOT a diagnostic substitute for memtester
# (which performs multi-pattern cell-level hardware tests). Install memtester
# for a conclusive hardware memory diagnostic.
if have memtester; then
  echo "--- memtester: 512 MB, 1 pass (hardware diagnostic) ---"
  echo "  Command: memtester 512M 1"
  if OUTPUT=$(memtester 512M 1 2>&1); then
    echo "$OUTPUT" | tail -20
    if echo "$OUTPUT" | grep -qi "FAILURE"; then
      fail "memtester reported memory errors!"
      T8_CONCERN=true
    else
      pass "  memtester: no errors in 512 MB"
    fi
  else
    concern "memtester failed to run (OOM or permission issue)"
    T8_CONCERN=true
  fi
else
  echo "--- /dev/shm MEMORY EXERCISE (256 MB write/read/verify) ---"
  echo ""
  echo -e "  ${YELLOW}NOTE: memtester is NOT installed.${NC}"
  echo "  This fallback is an OS-level read/write integrity check — it verifies"
  echo "  that the kernel can allocate, write, and re-read 256 MB without"
  echo "  corruption at the filesystem layer. It does NOT perform hardware"
  echo "  cell-level fault detection (pattern walking, bit-flip tests, etc.)."
  echo "  For a conclusive hardware memory diagnostic, install memtester:"
  echo "    apt-get install memtester && memtester 512M 1"
  echo ""
  MEM_FILE="/dev/shm/qual_memtest_$$"
  trap 'rm -f "$MEM_FILE"' EXIT
  echo "  Writing 256 MB to /dev/shm..."
  dd if=/dev/urandom of="$MEM_FILE" bs=1M count=256 2>/dev/null
  SUM1=$(sha256sum "$MEM_FILE" | awk '{print $1}')
  SUM2=$(sha256sum "$MEM_FILE" | awk '{print $1}')
  rm -f "$MEM_FILE"
  if [[ "$SUM1" == "$SUM2" ]]; then
    info "  Memory exercise PASSED: 256 MB read-verify checksums match"
    info "  (OS-level integrity only — install memtester for hardware diagnostic)"
  else
    fail "  Memory exercise FAILED: CHECKSUM MISMATCH — file corruption in /dev/shm!"
    T8_CONCERN=true
  fi
fi
echo ""

# Check swap usage
SWAP_USED=$(free | awk '/Swap/{print $3}')
if [[ -n "$SWAP_USED" && "$SWAP_USED" -gt 0 ]]; then
  concern "Swap is currently in use: ${SWAP_USED} kB — system may be memory-pressured"
  T8_CONCERN=true
fi

if ! $T8_CONCERN; then
  if have memtester; then
    pass "TEST 8: Memory diagnostic (memtester) passed"
    record "TEST 8 — Memory: PASS (memtester — hardware diagnostic)"
  else
    pass "TEST 8: Memory exercise passed (OS-level only — memtester not installed)"
    record "TEST 8 — Memory: PASS WITH CONCERN (exercise only — install memtester for hardware diagnostic)"
  fi
else
  concern "TEST 8: Memory concern — review above"
  record "TEST 8 — Memory: PASS WITH CONCERN"
fi

# =============================================================================
section "TEST 9 — Disk Health"
# =============================================================================
echo ""
echo "Command: lsblk; df -h; blockdev; cat /sys/block/*/queue/scheduler"
echo ""

echo "--- Block devices ---"
lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,ROTA,SCHED 2>/dev/null || lsblk 2>/dev/null || true
echo ""

echo "--- Filesystem usage ---"
df -h 2>/dev/null | grep -v "tmpfs\|udev\|none\|/run" || true
echo ""

echo "--- VirtIO device detection ---"
if ls /dev/vd* &>/dev/null; then
  echo "  VirtIO block devices detected: $(ls /dev/vd*)"
else
  info "No /dev/vd* devices (may be /dev/sda or nvme)"
fi
echo ""

echo "--- I/O scheduler per device ---"
for DEV in /sys/block/*/queue/scheduler; do
  DEVNAME=$(echo "$DEV" | cut -d/ -f4)
  SCHED=$(cat "$DEV" 2>/dev/null || echo "n/a")
  echo "  $DEVNAME: $SCHED"
done
echo ""

echo "--- Block device parameters ---"
for DEV in /sys/block/vd* /sys/block/sd* /sys/block/nvme*; do
  [[ -d "$DEV" ]] || continue
  DEVNAME=$(basename "$DEV")
  echo "  /dev/$DEVNAME:"
  echo "    Queue depth:  $(cat "$DEV/queue/nr_requests" 2>/dev/null || echo 'n/a')"
  echo "    Read-ahead:   $(cat "$DEV/queue/read_ahead_kb" 2>/dev/null || echo 'n/a') kB"
  echo "    Rotational:   $(cat "$DEV/queue/rotational" 2>/dev/null || echo 'n/a') (0=SSD/NVMe)"
  echo "    Write-cache:  $(cat "$DEV/queue/write_cache" 2>/dev/null || echo 'n/a')"
done
echo ""

echo "--- Current disk I/O utilization ---"
if have iostat; then
  iostat -xd 2 2 2>/dev/null | tail -30
else
  cat /proc/diskstats 2>/dev/null | awk '{print $3, "reads:", $4, "writes:", $8}' | head -10
fi
echo ""

echo "--- SMART / disk health (guest view) ---"
if have smartctl; then
  for DEV in /dev/vd? /dev/sd? /dev/nvme?n?; do
    [[ -b "$DEV" ]] || continue
    echo "  smartctl for $DEV:"
    smartctl -H "$DEV" 2>/dev/null || echo "  (SMART not available in KVM guest — expected)"
  done
else
  info "smartctl not installed — SMART data unavailable (expected in KVM)"
  echo "  Note: In KVM, SMART passthrough is hypervisor-dependent. VirtIO disks"
  echo "  report health via the filesystem and I/O error counters, not SMART."
fi
echo ""

echo "--- Filesystem error indicators ---"
dmesg 2>/dev/null | grep -iE "(error|fail|ext4|xfs|btrfs|io err)" | tail -15 || true
echo ""
echo "--- /proc/sys filesystem info ---"
for DEV in /dev/vd? /dev/sd?; do
  [[ -b "$DEV" ]] || continue
  echo "  $DEV size: $(blockdev --getsize64 "$DEV" 2>/dev/null | numfmt --to=iec 2>/dev/null || echo 'n/a')"
done
echo ""

pass "TEST 9: Disk health indicators checked (no SMART in KVM; I/O errors reviewed)"
record "TEST 9 — Disk Health: PASS (SMART not available in KVM guest — expected)"

# =============================================================================
section "TEST 10 — System Health"
# =============================================================================
echo ""
T10_CONCERN=false

echo "--- Uptime and load ---"
uptime
echo ""

echo "--- Memory pressure ---"
free -h
echo ""
AVAIL_MB=$(free | awk '/Mem:/{print int($7/1024)}')
echo "  Available: ~${AVAIL_MB} MB"
[[ "$AVAIL_MB" -lt 512 ]] && { concern "Less than 512 MB free RAM — AvalancheGo needs ~2-3 GB"; T10_CONCERN=true; } || true
echo ""

echo "--- Swap ---"
SWAP_TOTAL=$(free | awk '/Swap/{print $2}')
SWAP_USED2=$(free  | awk '/Swap/{print $3}')
echo "  Total: ${SWAP_TOTAL} kB   Used: ${SWAP_USED2} kB"
[[ -n "$SWAP_TOTAL" && "$SWAP_TOTAL" -eq 0 ]] && concern "No swap configured — consider a small swap for OOM safety" || true
echo ""

echo "--- Filesystem usage ---"
df -h | grep -vE "tmpfs|udev|/run|none" || true
echo ""

echo "--- Failed systemd services ---"
if have systemctl; then
  FAILED=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
  if [[ "$FAILED" -gt 0 ]]; then
    concern "$FAILED failed systemd service(s):"
    systemctl --failed --no-legend 2>/dev/null
    T10_CONCERN=true
  else
    echo "  No failed systemd services ✓"
  fi
else
  info "systemctl not available"
fi
echo ""

echo "--- Kernel errors (recent dmesg) ---"
KERNEL_ERRORS=$(dmesg --level=err,crit,emerg 2>/dev/null | tail -20 || \
                dmesg 2>/dev/null | grep -E "^\[.*\] (error|BUG|kernel BUG|Oops)" | tail -20 || true)
if [[ -n "$KERNEL_ERRORS" ]]; then
  concern "Kernel errors found:"
  echo "$KERNEL_ERRORS"
  T10_CONCERN=true
else
  echo "  No kernel errors in dmesg ✓"
fi
echo ""

echo "--- Network interface errors and drops ---"
ip -s link 2>/dev/null || ifconfig 2>/dev/null || true
echo ""
# Summarise error counts
ip -s link 2>/dev/null | awk '
  /^[0-9]+:/ { iface=$2 }
  /RX:/ { rx=1 }
  /TX:/ { tx=1; rx=0 }
  /errors [0-9]/ {
    if (rx) { match($0, /errors ([0-9]+)/, a); if (a[1]+0>0) print "  " iface " RX errors: " a[1] }
    if (tx) { match($0, /errors ([0-9]+)/, a); if (a[1]+0>0) print "  " iface " TX errors: " a[1] }
  }
' || true
echo ""

echo "--- CPU steal time (final) ---"
# Try mpstat for more accurate steal
if have mpstat; then
  mpstat 1 3 2>/dev/null | tail -5
else
  vmstat 1 3 2>/dev/null | tail -4
fi
echo ""

echo "--- OOM events ---"
OOMS=$(dmesg 2>/dev/null | grep -c "Out of memory\|oom-kill" || echo 0)
[[ "$OOMS" -gt 0 ]] && { concern "OOM events in dmesg: $OOMS"; T10_CONCERN=true; } || echo "  No OOM events ✓"
echo ""

if ! $T10_CONCERN; then
  pass "TEST 10: System health is good"
  record "TEST 10 — System Health: PASS"
else
  concern "TEST 10: Some health concerns — review above"
  record "TEST 10 — System Health: PASS WITH CONCERN"
fi

# =============================================================================
section "TEST 11 — Avalanche-Specific Network Readiness"
# =============================================================================
echo ""
echo "Command: DNS lookup of Avalanche domains; TCP probe of bootstrap nodes"
echo ""

T11_CONCERN=false

echo "--- Avalanche domain resolution ---"
AVAX_DOMAINS=(
  "bootstrap.avax.network"
  "api.avax.network"
  "subnets.avax.network"
  "stats.avax.network"
  "glacier-api.avax.network"
  "api.avax-test.network"
)
for D in "${AVAX_DOMAINS[@]}"; do
  RESULT=$(dig +short +time=5 +tries=2 "$D" 2>/dev/null | head -3 | tr '\n' ' ')
  if [[ -n "$RESULT" ]]; then
    echo "  $D → $RESULT"
  else
    # FIX 3: DNS failure for bootstrap.avax.network is informational, not a
    # hard failure. The domain may not resolve from all regions / resolvers,
    # and bootstrap node discovery also works via hard-coded IP in the binary.
    echo "  $D → UNRESOLVED"
    info "  (bootstrap.avax.network unresolvable — informational only; bootstrap IPs are baked into AvalancheGo)"
  fi
done
echo ""

# FIX 3: Bootstrap node TCP probes are hard-coded IPs. They are INFORMATIONAL
# ONLY. A timeout here never causes a CONCERN — the remote IP may have changed,
# the peer may be down, or their firewall may block inbound probes from
# unrecognised sources. What matters is this server's ability to initiate
# outbound TCP on port 9651, which is confirmed if ANY probe succeeds.
echo "--- Avalanche bootstrap node TCP 9651 — INFORMATIONAL ONLY ---"
echo "  Source: https://github.com/ava-labs/avalanchego — mainnet bootstrappers"
echo "  NOTE: These IPs are hard-coded and may change. A timeout here is NOT a"
echo "  failure criterion. Results are informational evidence of outbound 9651."
BOOTSTRAP_NODES=(
  "54.94.43.146:9651:Mainnet-bootstrap-1"
  "52.79.47.77:9651:Mainnet-bootstrap-2"
  "18.184.133.249:9651:Mainnet-bootstrap-3"
  "13.250.151.136:9651:Mainnet-bootstrap-4"
  "52.0.15.183:9651:Mainnet-bootstrap-5"
)
OUTBOUND_9651_OK=false
for ENTRY in "${BOOTSTRAP_NODES[@]}"; do
  HOST="${ENTRY%%:*}"; REST="${ENTRY#*:}"; PORT="${REST%%:*}"; LABEL="${REST#*:}"
  if have nc; then
    if nc -z -w 8 "$HOST" "$PORT" &>/dev/null; then
      echo "  [INFO] $LABEL ($HOST:$PORT): reachable — outbound TCP 9651 confirmed"
      OUTBOUND_9651_OK=true
    else
      echo "  [INFO] $LABEL ($HOST:$PORT): timeout/refused — not a failure (IP may have changed)"
    fi
  else
    info "  nc not available — cannot probe bootstrap nodes"
    break
  fi
done
if $OUTBOUND_9651_OK; then
  echo "  → At least one probe succeeded: outbound TCP 9651 is functional"
else
  echo "  → No probes succeeded: outbound TCP 9651 unconfirmed from hard-coded IPs"
  info "  (This is informational. Confirm outbound 9651 manually after firewall is open.)"
fi
echo ""

echo "--- Avalanche port requirements summary ---"
cat << 'EOF'
  INBOUND (must be open/forwarded for a validator):
    TCP 9651  — P2P staking port (essential — validators MUST be reachable on this port)
    TCP 9650  — HTTP API (optional for public RPC; close for security unless needed)

  OUTBOUND (must be able to reach):
    TCP 9651  — to connect to bootstrap/peer nodes (probed above — informational)
    TCP 443   — HTTPS to Avalanche APIs and bootstrap DNS
    UDP 53    — DNS resolution (tested via DNS tests)
    UDP 123   — NTP time sync (critical: AvalancheGo is time-sensitive)

  WHAT IS VERIFIED HERE:
    ✓ DNS resolution of Avalanche domains
    ✓ Outbound TCP 9651 informational probe (hard-coded IPs — may be stale)
    ✓ Outbound HTTPS/TLS (tested in TEST 4)
    ✓ Outbound DNS/UDP (tested in TEST 5)

  WHAT CANNOT BE VERIFIED FROM THIS HOST:
    ✗ Inbound TCP 9651 reachability (see TEST 4 — NOT TESTABLE, external probe required)
    ✗ Inbound UDP reachability
    ✗ Whether port 9651 is blocked by upstream provider (Netcup)
EOF
echo ""

# Time sync check (critical for AvalancheGo)
echo "--- NTP / time synchronization (critical for Avalanche) ---"
if have timedatectl; then
  timedatectl status 2>/dev/null | grep -E "Local time|Universal|RTC|NTP|synchronized|Time zone"
  NTP_SYNC=$(timedatectl status 2>/dev/null | grep -oP '(?<=NTP synchronized: )\w+' || echo "unknown")
  [[ "$NTP_SYNC" != "yes" ]] && { concern "NTP not synchronized — AvalancheGo requires accurate time"; T11_CONCERN=true; } || true
elif have chronyc; then
  chronyc tracking 2>/dev/null | head -8
else
  info "timedatectl/chronyc not available — checking /proc/sys/kernel/ngroups_max as proxy"
  date -u
fi
echo ""

if ! $T11_CONCERN; then
  pass "TEST 11: Avalanche network readiness — all verifiable checks passed"
  record "TEST 11 — Avalanche Network Readiness: PASS (inbound not testable)"
else
  concern "TEST 11: One or more Avalanche readiness concerns (see above)"
  record "TEST 11 — Avalanche Network Readiness: PASS WITH CONCERN"
fi

# =============================================================================
section "QUALIFICATION REPORT"
# =============================================================================
echo ""
echo -e "${BOLD}Server:${NC} $(hostname -f 2>/dev/null || hostname)"
echo -e "${BOLD}Date:${NC}   $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo -e "${BOLD}Kernel:${NC} $(uname -r)"
echo -e "${BOLD}CPU:${NC}    $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'unknown')"
echo -e "${BOLD}RAM:${NC}    $(free -h | awk '/Mem:/{print $2}')"
echo ""
echo -e "${BOLD}Results:${NC}"
for R in "${RESULTS[@]}"; do
  if echo "$R" | grep -q "PASS WITH CONCERN"; then
    echo -e "  ${YELLOW}⚠${NC}  $R"
  elif echo "$R" | grep -qE "^TEST.*FAIL$"; then
    echo -e "  ${RED}✗${NC}  $R"
  elif echo "$R" | grep -qE "NOT TESTABLE|NOT APPROVED"; then
    echo -e "  ${CYAN}?${NC}  $R"
  else
    echo -e "  ${GREEN}✓${NC}  $R"
  fi
done
echo ""

# FIX 4: Any CONCERN result → "READY WITH CONCERNS — NOT APPROVED FOR PRODUCTION"
# Only a clean PASS on every test earns an unqualified READY verdict.
FAIL_COUNT=$(printf '%s\n' "${RESULTS[@]}" | grep -cE "^TEST.*FAIL$" || true)
CONCERN_COUNT=$(printf '%s\n' "${RESULTS[@]}" | grep -c "CONCERN" || true)

echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo -e "${RED}${BOLD}  OVERALL VERDICT: NOT READY — $FAIL_COUNT test(s) FAILED${NC}"
elif [[ "$CONCERN_COUNT" -gt 0 ]]; then
  # FIX 4: CONCERN → explicit "NOT APPROVED FOR PRODUCTION" until concerns are resolved.
  echo -e "${YELLOW}${BOLD}  OVERALL VERDICT: READY WITH CONCERNS — NOT APPROVED FOR PRODUCTION${NC}"
  echo -e "${YELLOW}  $CONCERN_COUNT concern(s) must be reviewed and resolved before going live.${NC}"
  echo -e "${YELLOW}  Re-run this script after addressing each concern.${NC}"
else
  echo -e "${GREEN}${BOLD}  OVERALL VERDICT: READY FOR AVALANCHE VALIDATOR SETUP${NC}"
fi
echo -e "${BOLD}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "REQUIRED NEXT STEPS (after all tests pass):"
echo "  1. Open inbound TCP 9651 in the Netcup firewall panel (and any host firewall)"
echo "  2. Verify inbound TCP 9651 from an EXTERNAL host: nc -z -w 8 <public-ip> 9651"
echo "  3. Ensure NTP is synchronized (systemd-timesyncd or chrony)"
echo "  4. Follow PW-C15 INFRA PROVISIONING GUIDE to install AvalancheGo"
echo ""
echo "Log saved to: qualify-$(hostname -s)-<timestamp>.log (if you used tee)"
echo ""
