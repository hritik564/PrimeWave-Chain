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

      // TPS (last 60 seconds of indexed blocks)
      let tps: number | null = null;
      if (latestBlock) {
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
          currentBlock:        latestBlock?.number ?? 0,
          latestBlockTimestamp: latestBlock?.timestamp_unix ?? 0,
          isSynced:            syncStatus.isSynced,
          chainHead:           syncStatus.chainHead,
          latestIndexed:       syncStatus.latestIndexed,
        },
        transactions: {
          total: txCountRes.rows[0]?.count ?? '0',
          inLatestBlock: latestBlock?.transaction_count ?? 0,
          tps_60s: tps,
        },
        gas: {
          gasUsedLatestBlock:  latestBlock?.gas_used ?? '0',
          gasLimitLatestBlock: latestBlock?.gas_limit ?? '0',
        },
        validators: {
          activeCount: activeValRes.rows[0]?.count ?? '0',
        },
        rewardVault: {
          totalFunded:   rvStateRes.rows[0]?.total_funded   ?? '0',
          totalEmitted:  rvStateRes.rows[0]?.total_emitted  ?? '0',
          emissionRate:  rvStateRes.rows[0]?.emission_rate  ?? '0',
        },
        fees: {
          totalDistributed:  totalFeesRes.rows[0]?.total ?? '0',
          totalToValidators: vfvRes.rows[0]?.total ?? '0',
        },
      }));
    } catch (e) { next(e); }
  });

  return router;
}
