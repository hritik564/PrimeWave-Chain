/**
 * GET /contracts                   — paginated contract list
 * GET /contracts/:address          — contract details + recent events
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateAddress, validatePagination, ok, err } from '../validation';
import { IndexerConfig } from '../../config';

export default function contractsRouter(config: IndexerConfig): Router {
  const router = Router();

  // GET /contracts
  router.get('/', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );

      const knownOnly = req.query['known'] === 'true';

      const rows = await query(
        `SELECT c.address, c.creation_tx, c.creation_block,
                c.is_verified, c.is_known_protocol, c.protocol_name,
                a.tx_count
         FROM contracts c
         JOIN addresses a ON a.address = c.address
         WHERE ($1 = false OR c.is_known_protocol = true)
           AND ($2::bigint IS NULL OR c.creation_block < $2)
         ORDER BY c.creation_block DESC NULLS LAST
         LIMIT $3`,
        [knownOnly, after, limit]
      );

      const nextCursor = rows.rows.length === limit
        ? rows.rows[rows.rows.length - 1]?.creation_block
        : null;

      res.json(ok(rows.rows, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  // GET /contracts/:address
  router.get('/:address', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const addr = validateAddress(req.params['address']!);

      const contractRes = await query(
        `SELECT c.*, a.tx_count, a.first_seen_block, a.last_seen_block
         FROM contracts c
         JOIN addresses a ON a.address = c.address
         WHERE c.address = $1`,
        [addr]
      );

      if (!contractRes.rowCount) return res.status(404).json(err('Contract not found', 404).body);

      // Recent decoded events for this contract
      const eventsRes = await query(
        `SELECT de.event_name, de.event_signature, de.decoded_json,
                de.tx_hash, de.block_number
         FROM decoded_events de
         WHERE de.contract_address = $1
         ORDER BY de.id DESC LIMIT 20`,
        [addr]
      );

      res.json(ok({ ...contractRes.rows[0], recentEvents: eventsRes.rows }));
    } catch (e) { next(e); }
  });

  return router;
}
