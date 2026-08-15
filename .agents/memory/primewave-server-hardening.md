---
name: PrimeWave Validator #1 Server Hardening
description: Pre-deployment hardening of Netcup RS 1000 G12 (159.195.193.209) — swap, memtester, nftables firewall
---

## Status
HARDENING COMPLETE — 2026-08-15. Waiting for explicit approval before AvalancheGo installation.

## Server Identity
- IP: 159.195.193.209
- Hostname: v2202608398278499931.bestsrv.de
- OS: Debian 13 / Kernel 6.12.101+deb13-amd64
- Role: Validator Node #1

## What Was Done
1. **Swap**: 4 GiB /swapfile created, chmod 600, mkswap, swapon, persisted in /etc/fstab
2. **memtester**: 4.7.1-1, `memtester 512M 1` — exit 0, PASS, no errors
3. **nftables**: ruleset applied via `nft -f /etc/nftables.conf`; service enabled (sysinit.target.wants)

## nftables Ruleset (Effective)
- Input policy: DROP
- Allow: established/related, invalid-drop, loopback, ICMP, ICMPv6, TCP 22, TCP 9651, UDP 9651
- Forward policy: DROP
- Output policy: ACCEPT (unrestricted outbound)
- Persisted to /etc/nftables.conf (chmod 640)

## Key Pitfalls Learned
- JS template literals + bash `${VAR}` collide: always build bash scripts via string concatenation or escape `$`
- Python heredoc inside bash script via SSH fails if the heredoc delimiter is indented: use base64-decode pattern instead (`printf '%s' 'B64' | base64 -d > file`)
- memtester 512M 1 takes >2 min on this server — always run via nohup background + poll result file
- nftables.conf must be written with `flush ruleset` at the top; after `nft -f`, run `systemctl enable nftables && systemctl restart nftables` for persistence

## Next Required Action (NOT YET DONE)
1. Open Netcup Robot firewall: inbound TCP 9651 (and optionally UDP 9651)
2. Verify from external host: `nc -z -w 8 159.195.193.209 9651`
3. Install AvalancheGo v1.14.2 — awaiting explicit approval

## SSH Access Pattern (working)
```
printf '%s' "$PRIMEWAVE_SSH_KEY_B64" | base64 -d > /tmp/pw_key
chmod 600 /tmp/pw_key
ssh -i /tmp/pw_key -o StrictHostKeyChecking=no root@159.195.193.209
```
Secrets: PRIMEWAVE_SSH_KEY_B64, PRIMEWAVE_SSH_HOST, PRIMEWAVE_SSH_USER
