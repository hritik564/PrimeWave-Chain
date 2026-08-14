/**
 * GET /search?q=<query>            — global search
 *
 * Resolves query to one of:
 *   - block   (by number or hash)
 *   - tx      (by hash)
 *   - address (by address)
 *   - validator (by validationID)
 *
 * Returns { type, data } or 404.
 * Never fabricates results — returns found/not_found/invalid_format.
 */

import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../../db/client';

const HEX_ADDR     = /^0x[0-9a-fA-F]{40}$/i;
const HEX_HASH64   = /^0x[0-9a-fA-F]{64}$/i;   // tx hash or block hash or validator ID
const DECIMAL_NUM  = /^\d+$/;

export default function searchRouter(): Router {
  const router = Router();

  router.get('/', async (req: Request, res: Response, next: NextFunction) => {
    try {
      const q = (req.query['q'] as string | undefined)?.trim();

      if (!q) {
        return res.status(400).json({ success: false, error: 'q parameter required' });
      }

      // ── Address ──────────────────────────────────────────────────────────
      if (HEX_ADDR.test(q)) {
        const addr = q.toLowerCase();
        const addrRes = await query(
          'SELECT address, is_contract FROM addresses WHERE address = $1', [addr]
        );
        if (addrRes.rowCount) {
          return res.json({ success: true, type: 'address', data: addrRes.rows[0] });
        }
        return res.status(404).json({ success: false, type: 'address', error: 'Not found' });
      }

      // ── 32-byte hex: tx hash, block hash, or validator ID ─────────────
      if (HEX_HASH64.test(q)) {
        const h = q.toLowerCase();

        // Try transaction first
        const txRes = await query('SELECT hash, block_number, from_address, to_address FROM transactions WHERE hash = $1', [h]);
        if (txRes.rowCount) {
          return res.json({ success: true, type: 'transaction', data: txRes.rows[0] });
        }

        // Try block hash
        const blockRes = await query('SELECT number, hash, timestamp_unix FROM blocks WHERE hash = $1', [h]);
        if (blockRes.rowCount) {
          return res.json({ success: true, type: 'block', data: blockRes.rows[0] });
        }

        // Try validator ID
        const valRes = await query('SELECT validation_id, status, reward_recipient FROM validators WHERE validation_id = $1', [h]);
        if (valRes.rowCount) {
          return res.json({ success: true, type: 'validator', data: valRes.rows[0] });
        }

        return res.status(404).json({ success: false, type: 'unknown_hash', error: 'Not found' });
      }

      // ── Block number ──────────────────────────────────────────────────────
      if (DECIMAL_NUM.test(q)) {
        const n = parseInt(q, 10);
        if (!isNaN(n)) {
          const blockRes = await query('SELECT number, hash, timestamp_unix, transaction_count FROM blocks WHERE number = $1', [n]);
          if (blockRes.rowCount) {
            return res.json({ success: true, type: 'block', data: blockRes.rows[0] });
          }
          return res.status(404).json({ success: false, type: 'block', error: 'Block not found' });
        }
      }

      // ── Unrecognised format ──────────────────────────────────────────────
      res.status(400).json({ success: false, type: 'invalid_format', error: 'Query does not match any known format (address, hash, block number, validator ID)' });
    } catch (e) { next(e); }
  });

  return router;
}
