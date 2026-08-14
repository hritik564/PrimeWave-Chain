/**
 * GET /transactions/:hash          — transaction by hash (with receipt)
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';
import { validateHash, ok, err } from '../validation';
import { IndexerConfig } from '../../config';

export default function transactionsRouter(_config: IndexerConfig): Router {
  const router = Router();

  // GET /transactions/:hash
  router.get('/:hash', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const hash = validateHash(req.params['hash']!);

      const txRes = await query<Record<string, unknown>>(
        `SELECT t.*, r.status, r.gas_used AS receipt_gas_used,
                r.effective_gas_price, r.transaction_fee, r.contract_address AS created_contract
         FROM transactions t
         LEFT JOIN transaction_receipts r ON r.tx_hash = t.hash
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
