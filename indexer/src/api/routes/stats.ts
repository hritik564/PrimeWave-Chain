/**
 * GET /stats                       — network statistics
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { ok } from '../validation';
import { IndexerConfig } from '../../config';
import { IndexerEngine } from '../../indexer/engine';

export default function statsRouter(config: IndexerConfig, engine: IndexerEngine): Router {
  const router = Router();

  router.get('/', async (_req: Request, res: Response, next: NextFunction) => {
    try {
      // Latest block
      const latestBlockRes = await query<{ number: number; timestamp_unix: number; transaction_count: number; gas_used: string; gas_limit: string }>(
        'SELECT number, timestamp_unix, transaction_count, gas_used, gas_limit FROM blocks ORDER BY number DESC LIMIT 1'
      );
      const latestBlock = latestBlockRes.rows[0] ?? null;

      // Total indexed transactions
      const txCountRes = await query<{ count: string }>('SELECT COUNT(*) AS count FROM transactions');

      // Active validators
      const activeValRes = await query<{ count: string }>(
        "SELECT COUNT(*) AS count FROM validators WHERE is_active_in_vault = true"
      );

      // RewardVault state (latest snapshot)
      const rvStateRes = await query(
        'SELECT total_funded, total_emitted, emission_rate FROM reward_vault_state ORDER BY block_number DESC LIMIT 1'
      );

      // ValidatorFeeVault total received (sum of FeeDistributed.validatorShare)
      const vfvRes = await query<{ total: string }>(
        'SELECT COALESCE(SUM(validator_share::numeric), 0)::text AS total FROM fee_distribution'
      );

      // Total fees distributed
      const totalFeesRes = await query<{ total: string }>(
        'SELECT COALESCE(SUM(total_amount::numeric), 0)::text AS total FROM fee_distribution'
      );

      // Sync status
      const syncStatus = await engine.getSyncStatus().catch(() => ({
        latestIndexed: -1, chainHead: -1, isSynced: false
      }));
      const hasIndexCoverage =
        latestBlock !== null &&
        syncStatus.latestIndexed >= 0 &&
        syncStatus.isSynced;
      const hasRewardVault = Boolean(config.contracts.rewardVault);
      const hasFeeDistributor = Boolean(config.contracts.feeDistributor);

      // TPS (last 60 seconds of indexed blocks)
      let tps: number | null = null;
      if (latestBlock && hasIndexCoverage) {
        const windowEnd   = latestBlock.timestamp_unix;
        const windowStart = windowEnd - 60;
        const tpsRes = await query<{ tx_count: string; block_count: string }>(
          `SELECT COALESCE(SUM(transaction_count), 0)::text AS tx_count,
                  COUNT(*)::text AS block_count
           FROM blocks WHERE timestamp_unix BETWEEN $1 AND $2`,
          [windowStart, windowEnd]
        );
        const blockCount = Number(tpsRes.rows[0]?.block_count ?? 0);
        const txCount    = Number(tpsRes.rows[0]?.tx_count ?? 0);
        if (blockCount > 0) {
          tps = Math.round((txCount / 60) * 100) / 100;
        }
      }

      res.json(ok({
        network: {
          chainId:             config.chainId,
          currentBlock:        latestBlock?.number ?? null,
          latestBlockTimestamp: latestBlock?.timestamp_unix ?? null,
          isSynced:            hasIndexCoverage,
          chainHead:           syncStatus.chainHead,
          latestIndexed:       syncStatus.latestIndexed,
        },
        transactions: {
          total: hasIndexCoverage ? txCountRes.rows[0]?.count ?? null : null,
          inLatestBlock: latestBlock?.transaction_count ?? null,
          tps_60s: tps,
        },
        gas: {
          gasUsedLatestBlock:  latestBlock?.gas_used ?? null,
          gasLimitLatestBlock: latestBlock?.gas_limit ?? null,
        },
        validators: {
          activeCount: hasIndexCoverage ? activeValRes.rows[0]?.count ?? null : null,
        },
        rewardVault: {
          totalFunded:   hasRewardVault && hasIndexCoverage ? rvStateRes.rows[0]?.total_funded ?? null : null,
          totalEmitted:  hasRewardVault && hasIndexCoverage ? rvStateRes.rows[0]?.total_emitted ?? null : null,
          emissionRate:  hasRewardVault && hasIndexCoverage ? rvStateRes.rows[0]?.emission_rate ?? null : null,
        },
        fees: {
          totalDistributed:  hasFeeDistributor && hasIndexCoverage ? totalFeesRes.rows[0]?.total ?? null : null,
          totalToValidators: hasFeeDistributor && hasIndexCoverage ? vfvRes.rows[0]?.total ?? null : null,
        },
      }));
    } catch (e) { next(e); }
  });

  return router;
}
