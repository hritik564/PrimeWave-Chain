/**
 * GET /validators                  — paginated validator list
 * GET /validators/:id              — validator by validation ID
 * GET /validators/:id/events       — validator event history
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateValidatorId, validatePagination, ok, err, ValidationError } from '../validation';
import { IndexerConfig } from '../../config';

export default function validatorsRouter(config: IndexerConfig): Router {
  const router = Router();

  // GET /validators
  router.get('/', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { limit } = validatePagination(
        req.query['limit'] as string | undefined,
        undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );
      const afterCursor = req.query['after'] as string | undefined;
      let afterBlock: number | null = null;
      let afterId: string | null = null;
      if (afterCursor) {
        const match = /^(\d+):(0x[0-9a-fA-F]{64})$/.exec(afterCursor);
        if (!match) throw new ValidationError('after: invalid validator cursor');
        afterBlock = Number(match[1]);
        afterId = match[2]!.toLowerCase();
        if (!Number.isSafeInteger(afterBlock)) {
          throw new ValidationError('after: invalid validator cursor');
        }
      }
      let statusFilter: number | null = null;
      if (req.query['status'] !== undefined) {
        const parsedStatus = Number(req.query['status']);
        if (!Number.isSafeInteger(parsedStatus) || parsedStatus < 0) {
          throw new ValidationError('status: must be a non-negative integer');
        }
        statusFilter = parsedStatus;
      }

      const rows = await query(
        `SELECT validation_id, reward_recipient, acp99_weight, uptime_bips,
                status, is_active_in_vault, vault_base_weight, total_fees_claimed,
                first_seen_block, last_updated_block
         FROM validators
         WHERE ($1::int IS NULL OR status = $1)
           AND (
             $2::bigint IS NULL OR first_seen_block < $2 OR
             (first_seen_block = $2 AND validation_id < $3)
           )
         ORDER BY first_seen_block DESC, validation_id DESC
         LIMIT $4`,
        [statusFilter, afterBlock, afterId, limit]
      );

      const nextCursor = rows.rows.length === limit
        ? `${rows.rows[rows.rows.length - 1]?.first_seen_block}:${rows.rows[rows.rows.length - 1]?.validation_id}`
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
