/**
 * GET /transactions                — paginated transaction list (desc by block, then tx index)
 * GET /transactions/:hash          — transaction by hash (with receipt, logs, decoded events)
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateHash, validateBlockNumber, validatePagination, ok, err, ValidationError } from '../validation';
import { IndexerConfig } from '../../config';

const TX_COLS = `
  t.hash, t.block_number, t.block_hash, t.transaction_index,
  b.timestamp_unix, t.from_address, t.to_address,
  t.value, t.gas_limit, t.gas_price, t.max_fee_per_gas, t.max_priority_fee,
  t.nonce, t.input, t.chain_id, t.tx_type,
  r.status, r.gas_used AS receipt_gas_used,
  r.effective_gas_price, r.transaction_fee, r.contract_address AS created_contract
`.trim();

export default function transactionsRouter(config: IndexerConfig): Router {
  const router = Router();

  // GET /transactions  — paginated list (newest first)
  router.get('/', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const { limit, after } = validatePagination(
        req.query['limit'] as string | undefined,
        req.query['after'] as string | undefined,
        config.apiMaxLimit, config.apiDefaultLimit
      );

      // Cursor encodes block_number DESC, transaction_index DESC
      // after format: "<block_number>:<tx_index>"
      const afterStr = req.query['after'] as string | undefined;
      let afterBlock: number | null = null;
      let afterIdx: number | null = null;
      const blockNumber = req.query['block'] === undefined
        ? null
        : validateBlockNumber(req.query['block'] as string);
      if (afterStr) {
        const parts = afterStr.split(':');
        if (
          parts.length !== 2 ||
          !/^\d+$/.test(parts[0]!) ||
          !/^\d+$/.test(parts[1]!)
        ) {
          throw new ValidationError('after: invalid transaction cursor');
        }
        afterBlock = Number(parts[0]);
        afterIdx = Number(parts[1]);
        if (!Number.isSafeInteger(afterBlock) || !Number.isSafeInteger(afterIdx)) {
          throw new ValidationError('after: invalid transaction cursor');
        }
      }

      const rows = await query<Record<string, unknown>>(
        `SELECT ${TX_COLS}
         FROM transactions t
         LEFT JOIN transaction_receipts r ON r.tx_hash = t.hash
         LEFT JOIN blocks b ON b.number = t.block_number
         WHERE (
           $1::bigint IS NULL OR
           t.block_number < $1 OR
           (t.block_number = $1 AND t.transaction_index < $2)
         )
           AND ($4::bigint IS NULL OR t.block_number = $4)
         ORDER BY t.block_number DESC, t.transaction_index DESC
         LIMIT $3`,
        [afterBlock, afterIdx, limit, blockNumber]
      );

      const last = rows.rows[rows.rows.length - 1];
      const nextCursor = rows.rows.length === limit && last
        ? `${last['block_number']}:${last['transaction_index']}`
        : null;

      res.json(ok(rows.rows, { pagination: { limit, nextCursor } }));
    } catch (e) { next(e); }
  });

  // GET /transactions/:hash  — single transaction with full detail
  router.get('/:hash', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const hash = validateHash(req.params['hash']!);

      const txRes = await query<Record<string, unknown>>(
        `SELECT ${TX_COLS}
         FROM transactions t
         LEFT JOIN transaction_receipts r ON r.tx_hash = t.hash
         LEFT JOIN blocks b ON b.number = t.block_number
         WHERE t.hash = $1`,
        [hash]
      );

      if (!txRes.rowCount) return res.status(404).json(err('Transaction not found', 404).body);

      // Attach logs
      const logsRes = await query(
        `SELECT log_index, contract_address, topic0, topic1, topic2, topic3, data
         FROM transaction_logs WHERE tx_hash = $1 ORDER BY log_index`,
        [hash]
      );

      // Attach decoded events for this tx
      const decodedRes = await query(
        `SELECT de.event_name, de.event_signature, de.decoded_json, de.contract_address
         FROM decoded_events de WHERE de.tx_hash = $1 ORDER BY de.id`,
        [hash]
      );

      res.json(ok({
        ...txRes.rows[0],
        logs:          logsRes.rows,
        decodedEvents: decodedRes.rows,
      }));
    } catch (e) { next(e); }
  });

  return router;
}
