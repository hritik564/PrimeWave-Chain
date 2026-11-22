/**
 * GET /addresses/:address                — address summary
 * GET /addresses/:address/transactions   — paginated tx history
 * GET /addresses/:address/logs           — paginated log history
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateAddress, validatePagination, ok, err, ValidationError } from '../validation';
import { IndexerConfig } from '../../config';
import { RpcClient, hexToBigInt } from '../../rpc';

export default function addressesRouter(config: IndexerConfig, balanceRpc?: RpcClient): Router {
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
      const nativeBalance = balanceRpc
        ? await balanceRpc.getBalance(addr)
          .then((hex) => /^0x[0-9a-f]+$/i.test(hex) ? hexToBigInt(hex).toString() : null)
          .catch(() => null)
        : null;
      res.json(ok({
        ...res2.rows[0],
        native_balance_wei: nativeBalance,
      }));
    } catch (e) { next(e); }
  });

  // GET /addresses/:address/transactions
  router.get('/:address/transactions', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const addr = validateAddress(req.params['address']!);
      const { limit } = validatePagination(
        req.query['limit'] as string | undefined,
        undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );
      const afterCursor = req.query['after'] as string | undefined;
      let afterBlock: number | null = null;
      let afterIndex: number | null = null;
      if (afterCursor) {
        const parts = afterCursor.split(':');
        if (
          parts.length !== 2 ||
          !/^\d+$/.test(parts[0]!) ||
          !/^\d+$/.test(parts[1]!)
        ) {
          throw new ValidationError('after: invalid transaction cursor');
        }
        afterBlock = Number(parts[0]);
        afterIndex = Number(parts[1]);
        if (!Number.isSafeInteger(afterBlock) || !Number.isSafeInteger(afterIndex)) {
          throw new ValidationError('after: invalid transaction cursor');
        }
      }

      const rows = await query(
        `SELECT t.hash, t.block_number, t.transaction_index, b.timestamp_unix,
                t.from_address, t.to_address, t.value, t.gas_limit,
                t.gas_price, t.tx_type, r.status, r.transaction_fee
         FROM transactions t
         LEFT JOIN transaction_receipts r ON r.tx_hash = t.hash
         LEFT JOIN blocks b ON b.number = t.block_number
         WHERE (t.from_address = $1 OR t.to_address = $1)
           AND (
             $2::bigint IS NULL OR t.block_number < $2 OR
             (t.block_number = $2 AND t.transaction_index < $3)
           )
         ORDER BY t.block_number DESC, t.transaction_index DESC
         LIMIT $4`,
        [addr, afterBlock, afterIndex, limit]
      );

      const nextCursor = rows.rows.length === limit
        ? `${rows.rows[rows.rows.length - 1]?.block_number}:${rows.rows[rows.rows.length - 1]?.transaction_index}`
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
