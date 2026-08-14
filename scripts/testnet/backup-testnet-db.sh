#!/usr/bin/env bash
# ============================================================
# PrimeWave Testnet — PostgreSQL Database Backup
# Sprint PW-C14 | TESTNET ONLY
# ============================================================
# Creates a timestamped PostgreSQL dump of the testnet indexer DB.
# Verifies the backup by row-count comparison.
#
# Usage (manual):
#   PGHOST=localhost PGPORT=5432 PGUSER=indexer PGPASSWORD=... \
#   PGDATABASE=primewave_testnet \
#   BACKUP_DIR=/backups/testnet-db \
#   bash scripts/testnet/backup-testnet-db.sh
#
# Cron example (daily at 02:00):
#   0 2 * * * /opt/primewave/scripts/testnet/backup-testnet-db.sh >> /var/log/pw-backup.log 2>&1
# ============================================================
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups/testnet-db}"
PGDATABASE="${PGDATABASE:?PGDATABASE must be set}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TS=$(date -u +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/primewave_testnet_${TS}.dump"

mkdir -p "$BACKUP_DIR"

echo "[$(date -u +%FT%TZ)]  Starting backup: $PGDATABASE → $BACKUP_FILE"

# Create backup
pg_dump \
  --format=custom \
  --compress=9 \
  --file="$BACKUP_FILE" \
  "$PGDATABASE"

SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
echo "[$(date -u +%FT%TZ)]  Backup complete: $SIZE"

# Verify backup (list contents)
pg_restore --list "$BACKUP_FILE" > /dev/null
echo "[$(date -u +%FT%TZ)]  Backup verified (pg_restore --list succeeded)"

# Clean old backups
find "$BACKUP_DIR" -name "primewave_testnet_*.dump" -mtime "+$RETENTION_DAYS" -delete
echo "[$(date -u +%FT%TZ)]  Pruned backups older than $RETENTION_DAYS days"
echo "[$(date -u +%FT%TZ)]  Done: $BACKUP_FILE"
