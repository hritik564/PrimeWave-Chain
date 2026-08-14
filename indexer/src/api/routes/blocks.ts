/**
 * GET /blocks                      — paginated block list (desc)
 * GET /blocks/:number              — block by number
 * GET /blocks/hash/:hash           — block by hash
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateHash, validateBlockNumber, validatePagination, ok, err, ValidationError } from '../validation';
import { IndexerConfig } from '../../config';

const BLOCK_COLS = `
  number, hash, parent_hash, timestamp_unix,
  gas_limit, gas_used, base_fee_per_gas,
  transaction_count, coinbase, state_root, receipts_root
`.trim();

export default function blocksRouter(config: IndexerConfig): Router {
  const router = Router();

  // GET /blocks
  router.get('/', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );

      const rows = await query(
        `SELECT ${BLOCK_COLS} FROM blocks
         WHERE ($1::bigint IS NULL OR number < $1)
         ORDER BY number DESC LIMIT $2`,
        [after, limit]
      );

      const nextCursor = rows.rows.length === limit
        ? rows.rows[rows.rows.length - 1]?.number
        : null;

      res.json(ok(rows.rows, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  // GET /blocks/hash/:hash
  router.get('/hash/:hash', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const hash = validateHash(req.params['hash']!);
      const rows = await query(`SELECT ${BLOCK_COLS} FROM blocks WHERE hash = $1`, [hash]);
      if (!rows.rowCount) return res.status(404).json(err('Block not found', 404).body);
      res.json(ok(rows.rows[0]));
    } catch (e) { next(e); }
  });

  // GET /blocks/:number
  router.get('/:number', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const number = validateBlockNumber(req.params['number']!);
      const rows   = await query(`SELECT ${BLOCK_COLS} FROM blocks WHERE number = $1`, [number]);
      if (!rows.rowCount) return res.status(404).json(err('Block not found', 404).body);
      res.json(ok(rows.rows[0]));
    } catch (e) { next(e); }
  });

  return router;
}
