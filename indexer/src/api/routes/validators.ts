/**
 * GET /validators                  — paginated validator list
 * GET /validators/:id              — validator by validation ID
 * GET /validators/:id/events       — validator event history
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateValidatorId, validatePagination, ok, err } from '../validation';
import { IndexerConfig } from '../../config';

export default function validatorsRouter(config: IndexerConfig): Router {
  const router = Router();

  // GET /validators
  router.get('/', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );
      const statusFilter = req.query['status'] !== undefined
        ? parseInt(req.query['status'] as string, 10)
        : null;

      const rows = await query(
        `SELECT validation_id, reward_recipient, acp99_weight, uptime_bips,
                status, is_active_in_vault, vault_base_weight, total_fees_claimed,
                first_seen_block, last_updated_block
         FROM validators
         WHERE ($1::int IS NULL OR status = $1)
           AND ($2::bigint IS NULL OR first_seen_block > $2)
         ORDER BY first_seen_block DESC
         LIMIT $3`,
        [statusFilter, after, limit]
      );

      const nextCursor = rows.rows.length === limit
        ? rows.rows[rows.rows.length - 1]?.first_seen_block
        : null;

      res.json(ok(rows.rows, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  // GET /validators/:id
  router.get('/:id', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const id  = validateValidatorId(req.params['id']!);
      const res2 = await query(
        `SELECT * FROM validators WHERE validation_id = $1`, [id]
      );
      if (!res2.rowCount) return res.status(404).json(err('Validator not found', 404).body);
      res.json(ok(res2.rows[0]));
    } catch (e) { next(e); }
  });

  // GET /validators/:id/events
  router.get('/:id/events', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const id  = validateValidatorId(req.params['id']!);
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );

      const rows = await query(
        `SELECT id, tx_hash, block_number, log_index, event_name, contract_address, event_data
         FROM validator_events
         WHERE validation_id = $1
           AND ($2::bigint IS NULL OR id < $2)
         ORDER BY id DESC LIMIT $3`,
        [id, after, limit]
      );

      const nextCursor = rows.rows.length === limit
        ? rows.rows[rows.rows.length - 1]?.id
        : null;

      res.json(ok(rows.rows, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  return router;
}
