/**
 * PrimeWave Indexer — Express API Server
 *
 * Read-only REST API for C13/PWCScan consumption.
 * All mutation endpoints are absent by design.
 *
 * Security:
 *   - Input validated before any DB access
 *   - Parameterised queries everywhere (no string interpolation of user input)
 *   - Request body parsing disabled (GET-only endpoints)
 *   - Unbounded pagination prevented
 */

import express, { Request, Response, NextFunction } from 'express';
import { IndexerConfig } from '../config';
import { IndexerEngine } from '../indexer/engine';
import { ValidationError } from './validation';

// Route modules
import blocksRouter     from './routes/blocks';
import transactionsRouter from './routes/transactions';
import addressesRouter  from './routes/addresses';
import validatorsRouter from './routes/validators';
import stakingRouter    from './routes/staking';
import rewardsRouter    from './routes/rewards';
import feesRouter       from './routes/fees';
import contractsRouter  from './routes/contracts';
import searchRouter     from './routes/search';
import statsRouter      from './routes/stats';

export function createApp(config: IndexerConfig, engine: IndexerEngine): express.Application {
  const app = express();

  // Attach config + engine to request context
  app.use((req: Request, _res: Response, next: NextFunction) => {
    (req as typeof req & { apiConfig: IndexerConfig; engine: IndexerEngine }).apiConfig = config;
    (req as typeof req & { apiConfig: IndexerConfig; engine: IndexerEngine }).engine    = engine;
    next();
  });

  // No body parser — all endpoints are GET

  // ── Routes ──────────────────────────────────────────────────────────────────

  app.get('/health', (_req, res) => {
    res.json({ success: true, data: { status: 'ok', service: 'primewave-indexer' } });
  });

  app.use('/stats',        statsRouter(config, engine));
  app.use('/blocks',       blocksRouter(config));
  app.use('/transactions', transactionsRouter(config));
  app.use('/addresses',    addressesRouter(config));
  app.use('/validators',   validatorsRouter(config));
  app.use('/staking',      stakingRouter(config));
  app.use('/rewards',      rewardsRouter(config));
  app.use('/fees',         feesRouter(config));
  app.use('/contracts',    contractsRouter(config));
  app.use('/search',       searchRouter());

  // ── 404 ─────────────────────────────────────────────────────────────────────
  app.use((_req, res) => {
    res.status(404).json({ success: false, error: 'Not found' });
  });

  // ── Error handler ────────────────────────────────────────────────────────────
  app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (err instanceof ValidationError) {
      return res.status(400).json({ success: false, error: err.message });
    }
    console.error('[api] Unhandled error:', err);
    res.status(500).json({ success: false, error: 'Internal server error' });
  });

  return app;
}

export function startApiServer(
  config:  IndexerConfig,
  engine:  IndexerEngine,
): void {
  const app = createApp(config, engine);
  app.listen(config.apiPort, () => {
    console.log(`[api] Listening on :${config.apiPort}`);
  });
}
