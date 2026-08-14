/**
 * GET /fees                        — fee distribution summary + recent events
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validatePagination, ok } from '../validation';
import { IndexerConfig } from '../../config';

export default function feesRouter(config: IndexerConfig): Router {
  const router = Router();

  // GET /fees
  router.get('/', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );

      // Totals
      const totalsRes = await query<{
        total_distributed: string;
        total_validator:   string;
        total_treasury:    string;
        total_burn:        string;
        event_count:       string;
      }>(
        `SELECT
           COALESCE(SUM(total_amount::numeric), 0)::text   AS total_distributed,
           COALESCE(SUM(validator_share::numeric), 0)::text AS total_validator,
           COALESCE(SUM(treasury_share::numeric), 0)::text  AS total_treasury,
           COALESCE(SUM(burn_share::numeric), 0)::text      AS total_burn,
           COUNT(*)::text AS event_count
         FROM fee_distribution`
      );

      // Recent events
      const eventsRes = await query(
        `SELECT id, tx_hash, block_number, log_index,
                total_amount, validator_share, treasury_share, burn_share
         FROM fee_distribution
         WHERE ($1::bigint IS NULL OR id < $1)
         ORDER BY id DESC LIMIT $2`,
        [after, limit]
      );

      const nextCursor = eventsRes.rows.length === limit
        ? eventsRes.rows[eventsRes.rows.length - 1]?.id
        : null;

      res.json(ok({
        summary: totalsRes.rows[0] ?? null,
        events:  eventsRes.rows,
      }, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  return router;
}
