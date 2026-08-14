/**
 * GET /staking/:address            — staking position(s) for an address
 * GET /staking                     — recent staking events (paginated)
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateAddress, validatePagination, ok } from '../validation';
import { IndexerConfig } from '../../config';

export default function stakingRouter(config: IndexerConfig): Router {
  const router = Router();

  // GET /staking
  router.get('/', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );

      const rows = await query(
        `SELECT id, tx_hash, block_number, event_name, validation_id, address, amount
         FROM staking_events
         WHERE ($1::bigint IS NULL OR id < $1)
         ORDER BY id DESC LIMIT $2`,
        [after, limit]
      );

      const nextCursor = rows.rows.length === limit
        ? rows.rows[rows.rows.length - 1]?.id
        : null;

      res.json(ok(rows.rows, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  // GET /staking/:address
  router.get('/:address', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const addr = validateAddress(req.params['address']!);

      const positions = await query(
        `SELECT validation_id, staker, amount, stake_block, is_returned, return_block
         FROM staking_positions WHERE staker = $1 ORDER BY stake_block DESC`,
        [addr]
      );

      const events = await query(
        `SELECT id, tx_hash, block_number, event_name, validation_id, amount
         FROM staking_events WHERE address = $1 ORDER BY id DESC LIMIT 50`,
        [addr]
      );

      res.json(ok({ positions: positions.rows, recentEvents: events.rows }));
    } catch (e) { next(e); }
  });

  return router;
}
