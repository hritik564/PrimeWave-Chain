/**
 * GET /rewards                     — RewardVault summary + latest state
 * GET /rewards/:address            — reward claims for an address
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateAddress, validatePagination, ok } from '../validation';
import { IndexerConfig } from '../../config';

export default function rewardsRouter(config: IndexerConfig): Router {
  const router = Router();

  // GET /rewards
  router.get('/', async (_req: Request, res: Response, next: NextFunction) => {
    try {
      // Latest RewardVault snapshot
      const stateRes = await query(
        `SELECT * FROM reward_vault_state ORDER BY block_number DESC LIMIT 1`
      );

      // Total claimed (sum of all RewardClaimed events)
      const claimedRes = await query<{ total: string }>(
        `SELECT COALESCE(SUM(amount::numeric), 0)::text AS total
         FROM reward_events WHERE event_name = 'RewardClaimed' AND amount IS NOT NULL`
      );

      // Emission rate from latest state
      const rateRes = await query<{ emission_rate: string }>(
        `SELECT emission_rate FROM reward_vault_state ORDER BY block_number DESC LIMIT 1`
      );

      res.json(ok({
        latestState:  stateRes.rows[0] ?? null,
        totalClaimed: claimedRes.rows[0]?.total ?? '0',
        emissionRate: rateRes.rows[0]?.emission_rate ?? '0',
      }));
    } catch (e) { next(e); }
  });

  // GET /rewards/:address
  router.get('/:address', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const addr = validateAddress(req.params['address']!);
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );

      const events = await query(
        `SELECT id, tx_hash, block_number, event_name, recipient_id, amount
         FROM reward_events
         WHERE reward_address = $1
           AND ($2::bigint IS NULL OR id < $2)
         ORDER BY id DESC LIMIT $3`,
        [addr, after, limit]
      );

      const totalClaimed = await query<{ total: string }>(
        `SELECT COALESCE(SUM(amount::numeric), 0)::text AS total
         FROM reward_events
         WHERE reward_address = $1 AND event_name = 'RewardClaimed' AND amount IS NOT NULL`,
        [addr]
      );

      const nextCursor = events.rows.length === limit
        ? events.rows[events.rows.length - 1]?.id
        : null;

      res.json(ok({
        totalClaimed: totalClaimed.rows[0]?.total ?? '0',
        events:       events.rows,
      }, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  return router;
}
