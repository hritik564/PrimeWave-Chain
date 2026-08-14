#!/usr/bin/env bash
# ============================================================
# PrimeWave Testnet — PostgreSQL Database Restore
# Sprint PW-C14 | TESTNET ONLY
# ============================================================
# Restores the testnet indexer database from a backup file.
# Drops and recreates the database before restoring.
#
# Usage:
#   BACKUP_FILE=/backups/testnet-db/primewave_testnet_20260814_020000.dump \
#   PGHOST=localhost PGUSER=indexer PGPASSWORD=... \
#   PGDATABASE=primewave_testnet \
#   bash scripts/testnet/restore-testnet-db.sh
# ============================================================
set -euo pipefail

BACKUP_FILE="${BACKUP_FILE:?BACKUP_FILE must be set (path to .dump file)}"
PGDATABASE="${PGDATABASE:?PGDATABASE must be set}"

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "[ERROR] Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "══ PrimeWave Testnet DB Restore ══"
echo "  Source: $BACKUP_FILE"
echo "  Target: $PGDATABASE"
echo ""
echo "  WARNING: This will DROP and recreate $PGDATABASE."
echo "           Stop the indexer service before proceeding."
echo ""
read -r -p "  Type 'restore-testnet' to confirm: " CONFIRM
if [[ "$CONFIRM" != "restore-testnet" ]]; then
  echo "[ABORT] Cancelled."
  exit 1
fi

echo "[INFO]  Dropping database $PGDATABASE ..."
dropdb --if-exists "$PGDATABASE"
echo "[INFO]  Creating database $PGDATABASE ..."
createdb "$PGDATABASE"
echo "[INFO]  Restoring from $BACKUP_FILE ..."
pg_restore --dbname="$PGDATABASE" --jobs=4 --no-owner "$BACKUP_FILE"
echo "[OK]    Restore complete."
echo ""
echo "  Start indexer: systemctl start primewave-testnet-indexer"
echo "  Verify sync:   curl http://localhost:4000/health"
