/**
 * GET /addresses/:address                — address summary
 * GET /addresses/:address/transactions   — paginated tx history
 * GET /addresses/:address/logs           — paginated log history
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateAddress, validatePagination, ok, err } from '../validation';
import { IndexerConfig } from '../../config';

export default function addressesRouter(config: IndexerConfig): Router {
  const router = Router();

  // GET /addresses/:address
  router.get('/:address', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const addr = validateAddress(req.params['address']!);
      const res2 = await query(
        `SELECT a.*, c.creation_tx, c.creation_block, c.is_verified, c.is_known_protocol, c.protocol_name
         FROM addresses a
         LEFT JOIN contracts c ON c.address = a.address
         WHERE a.address = $1`,
        [addr]
      );
      if (!res2.rowCount) return res.status(404).json(err('Address not found', 404).body);
      res.json(ok(res2.rows[0]));
    } catch (e) { next(e); }
  });

  // GET /addresses/:address/transactions
  router.get('/:address/transactions', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const addr = validateAddress(req.params['address']!);
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );

      const rows = await query(
        `SELECT t.hash, t.block_number, t.transaction_index,
                t.from_address, t.to_address, t.value, t.gas_limit,
                t.gas_price, t.tx_type, r.status, r.transaction_fee
         FROM transactions t
         LEFT JOIN transaction_receipts r ON r.tx_hash = t.hash
         WHERE (t.from_address = $1 OR t.to_address = $1)
           AND ($2::bigint IS NULL OR t.block_number < $2)
         ORDER BY t.block_number DESC, t.transaction_index DESC
         LIMIT $3`,
        [addr, after, limit]
      );

      const nextCursor = rows.rows.length === limit
        ? rows.rows[rows.rows.length - 1]?.block_number
        : null;

      res.json(ok(rows.rows, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  // GET /addresses/:address/logs
  router.get('/:address/logs', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const addr = validateAddress(req.params['address']!);
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );

      const rows = await query(
        `SELECT id, block_number, tx_hash, log_index, topic0, topic1, topic2, topic3, data
         FROM transaction_logs
         WHERE contract_address = $1
           AND ($2::bigint IS NULL OR id < $2)
         ORDER BY id DESC
         LIMIT $3`,
        [addr, after, limit]
      );

      const nextCursor = rows.rows.length === limit
        ? rows.rows[rows.rows.length - 1]?.id
        : null;

      res.json(ok(rows.rows, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  return router;
}
