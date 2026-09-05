---
name: Replit Testnet Explorer migrations
description: Replit-managed production PostgreSQL schema handling for the PrimeWave C12 indexer
---

Replit production PostgreSQL schema changes are applied by the Publish flow. The C12 indexer may retain its idempotent migration runner for development, but production startup must not issue DDL; it should verify the published C12 tables and fail clearly if the schema is incomplete.

**Why:** Replit's managed database workflow rejects custom deploy-time or startup-time production migrations as unsupported and unsafe.

**How to apply:** When preparing a Testnet Explorer publish, ensure the development schema source includes the C12 tables or otherwise confirm the Publish diff will create them, then run the VM smoke test only after production database binding exists.