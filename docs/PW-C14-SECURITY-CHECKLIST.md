# PW-C14: Testnet Security Checklist
**Sprint:** PW-C14
**Environment:** TESTNET ONLY
**Reference:** Sections 5, 23, 39 of PW-C14 spec

---

> Complete this checklist before declaring the testnet live.
> Every item is binary PASS / FAIL. Do NOT launch with any FAIL.

---

## Section A: Key Security

| # | Check | Method | Result |
|---|---|---|---|
| K-01 | No mainnet private keys generated or referenced | Grep codebase for production mnemonics | [ ] |
| K-02 | No private keys committed to Git | `git log --all -S "0x" -- "*.env" "*.json"` | [ ] |
| K-03 | No private keys appear in application logs | Check logs for 64-char hex strings | [ ] |
| K-04 | No private keys in environment variables visible to frontend | Check VITE_* vars in built artifact | [ ] |
| K-05 | Testnet deployer key is labeled TESTNET-ONLY | Label on encrypted key file | [ ] |
| K-06 | Testnet keeper signer key is labeled TESTNET-ONLY | Label on encrypted key file | [ ] |
| K-07 | EMS signer keys (×5) are labeled TESTNET-ONLY | Labels on encrypted key files | [ ] |
| K-08 | Validator node keys are node-local only | Not exported from any node | [ ] |
| K-09 | Testnet key directory has 700 permissions | `ls -la /secure/testnet-keys/` | [ ] |
| K-10 | No key material in `/tmp` or world-readable paths | `find /tmp -name "*.json" -o -name "*.key"` | [ ] |

---

## Section B: RPC Security

| # | Check | Method | Result |
|---|---|---|---|
| R-01 | Validator API port (9650) NOT publicly reachable | `nmap -p 9650 <validator-public-ip>` → filtered | [ ] |
| R-02 | Validator admin API disabled (`--api-admin-enabled=false`) | Node config + test: `curl .../ext/admin` → 403 | [ ] |
| R-03 | Validator keystore API disabled | `curl .../ext/keystore` → 403 | [ ] |
| R-04 | Public RPC only exposes allowed methods | Test admin methods via public RPC → rejected | [ ] |
| R-05 | `debug_*` methods not on public RPC | `curl -X POST -d '{"method":"debug_traceTransaction",...}'` → error | [ ] |
| R-06 | RPC rate limiting active | Flood test: 200+ rps → rate limited | [ ] |
| R-07 | TLS certificate valid and auto-renewing | `curl -vI https://rpc.primewave-testnet.example.com` | [ ] |
| R-08 | HTTP redirects to HTTPS | `curl -I http://rpc...` → 301 to HTTPS | [ ] |
| R-09 | HSTS header present | `curl -vI https://rpc...` → `Strict-Transport-Security` | [ ] |

---

## Section C: Database Security

| # | Check | Method | Result |
|---|---|---|---|
| D-01 | PostgreSQL NOT publicly reachable | `nmap -p 5432 <indexer-public-ip>` → filtered | [ ] |
| D-02 | PostgreSQL bound to localhost only | `ss -tlnp | grep 5432` → `127.0.0.1` only | [ ] |
| D-03 | Indexer DB user has limited privileges (no superuser) | `\du` in psql | [ ] |
| D-04 | DB password not in any config file committed to Git | `git log --all -S password` | [ ] |
| D-05 | Backup encryption enabled | Verify backup script uses `age` or GPG | [ ] |

---

## Section D: Network / Firewall

| # | Check | Method | Result |
|---|---|---|---|
| F-01 | Validator P2P (9651) open only to known peers | `iptables -L INPUT` | [ ] |
| F-02 | No unnecessary ports open on validators | `nmap -p- <validator-ip>` → only 9651 public | [ ] |
| F-03 | Sentinel monitoring ports (9090, 3000) NOT public | `nmap -p 9090,3000 <sentinel-ip>` → filtered | [ ] |
| F-04 | Keeper health port (8080) internal only | `nmap -p 8080 <sentinel-public-ip>` → filtered | [ ] |
| F-05 | SSH access via key only (no password auth) | `grep PasswordAuthentication /etc/ssh/sshd_config` | [ ] |

---

## Section E: Protocol Security

| # | Check | Method | Result |
|---|---|---|---|
| P-01 | NativeMinter precompile disabled on testnet | `validate-testnet-genesis.sh` INV-G2 | [ ] |
| P-02 | Fixed supply invariant verified post-deploy | `validate-testnet-genesis.sh` INV-G3 | [ ] |
| P-03 | RewardVault funded with exactly 15M PW | `validate-testnet-genesis.sh` INV-G4 | [ ] |
| P-04 | FeeDistributor routes 70/20/10 correctly | Send tx, inspect events | [ ] |
| P-05 | ValidatorManager remains the authority | EMS cannot add/remove validators directly | [ ] |
| P-06 | EmergencyMultisig has exactly 5 signers (threshold 3) | `cast call EMS "THRESHOLD()(uint256)"` | [ ] |
| P-07 | Timelock delay is 48h (172800s) | `cast call TIMELOCK "getMinDelay()(uint256)"` | [ ] |
| P-08 | No DEV0 EOA is admin/owner of any testnet contract | `validate-testnet-genesis.sh` INV-G8 | [ ] |

---

## Section F: Labels and Identification

| # | Check | Method | Result |
|---|---|---|---|
| L-01 | PWCScan shows "Testnet" environment label | Screenshot of explorer header | [ ] |
| L-02 | Chain ID 77777 visible in explorer | Stats page or header | [ ] |
| L-03 | No production/mainnet labels anywhere in testnet | Visual audit of all pages | [ ] |
| L-04 | API responses include environment metadata | `curl /health` → `"network":"testnet"` | [ ] |
| L-05 | Documentation clearly labeled TESTNET throughout | Audit all C14 docs | [ ] |

---

## Final Sign-Off

| Role | Name | Date | Signature |
|---|---|---|---|
| PrimeWave Tech Lead | TBD | | |
| Security Reviewer | TBD | | |

**Result:** [ ] PASS — All checks passed. Testnet is secure to launch.
**Result:** [ ] FAIL — See failing items above. Do NOT launch.
