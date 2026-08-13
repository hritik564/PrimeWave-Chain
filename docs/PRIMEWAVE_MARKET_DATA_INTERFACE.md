# PrimeWave Chain — Market Data Interface (PrimeWave Dex)
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Overview

PrimeWave Dex is a separate project that provides DexScreener/DEXTools-style market analytics for PW/PWUSD. It is NOT built in PW-C00.

This document defines the **interface boundary** between PrimeWave Chain / PWSwap and the PrimeWave Dex project.

---

## 2. Data Pipeline Architecture

```
PrimeWave Chain
└── PWSwap contracts (Swap, Sync, Mint, Burn events)
        │
        ▼
Indexer Service
└── Consumes chain events in real time
└── Calculates OHLCV, volume, liquidity from raw events
        │
        ▼
Market Database
└── PostgreSQL (time-series optimized)
└── OHLCV candles at multiple timeframes
└── Trade history, LP events
        │
        ▼
Market Data API
└── REST + WebSocket
└── Authenticated and rate-limited
        │
        ▼
PrimeWave Dex (Frontend)
└── Candlestick charts
└── Price, volume, liquidity metrics
└── Trade history
└── Pool reserve display
```

PrimeWave Dex MUST own its own market data pipeline. It MUST NOT depend on DexScreener, DEXTools, or any third-party service for its core data.

---

## 3. Required Chain Interface

PrimeWave Chain (via PWSwap events) provides:

### 3.1 Source Events

| Event | Source Contract | Data Provided |
|---|---|---|
| `Swap` | PWSwapPair | sender, amount0In, amount1In, amount0Out, amount1Out, to |
| `Sync` | PWSwapPair | reserve0, reserve1 (pool reserves after each operation) |
| `Mint` | PWSwapPair | sender, amount0, amount1 (LP addition) |
| `Burn` | PWSwapPair | sender, amount0, amount1, to (LP removal) |
| `Transfer` (LP) | PWSwapPair | LP token transfers |

### 3.2 Derived Data (Indexer responsibility)

The indexer computes from raw events:

| Metric | Derivation |
|---|---|
| Price (PW in PWUSD) | reserve1 / reserve0 from `Sync` events |
| Trade direction (Buy/Sell) | From `Swap` event amounts |
| Volume | Sum of amount0 or amount1 in/out per period |
| Liquidity (USD) | reserve1 × 2 (PWUSD side × 2, assuming PWUSD ≈ $1) |
| Market cap | price × circulating_supply |
| FDV | price × 100,000,000 |
| OHLCV candles | Aggregated from per-block Sync events |

---

## 4. Required Market Data Features

| Feature | Timeframes | Notes |
|---|---|---|
| Candlestick charts | 5m, 15m, 1H, 4H, 1D, 1W | Standard OHLCV candles |
| Price | Live | Derived from reserves |
| Price change | 1H, 24H, 7D | % change |
| Volume | 1H, 24H, 7D | In PWUSD |
| Liquidity | Live | Pool reserve depth |
| Market cap | Live | Based on circulating supply |
| FDV | Live | Based on 100M total supply |
| Buys | Per period | Swap events where PW received |
| Sells | Per period | Swap events where PW sent |
| Trade count | Per period | Total swap count |
| Recent trades | Live feed | Last N Swap events |
| Pool reserves | Live | PW and PWUSD reserves |
| LP additions | Historical | Mint events |
| LP removals | Historical | Burn events |
| Historical data | All timeframes | Stored in market database |

---

## 5. Technology Recommendations for Indexer (Future Sprint)

| Component | Recommendation | Rationale |
|---|---|---|
| Indexer runtime | Node.js or Go | Mature EVM event indexing ecosystem |
| Event source | WebSocket RPC to PrimeWave Chain | Real-time event streaming |
| Database | TimescaleDB (PostgreSQL extension) | Time-series optimized, open-source |
| API | REST + WebSocket | Standard market data API pattern |
| Candle computation | Indexer-computed, stored | Avoid real-time recomputation |
| Deployment | Same infrastructure cluster as chain | Low latency, cost efficient |

---

## 6. Independence Requirements

PrimeWave Dex:
- MUST NOT depend on DexScreener API for core price/volume data
- MUST NOT depend on DEXTools or similar for core functionality
- MAY integrate with external aggregators as OPTIONAL supplementary data
- MUST display its own indexed data as the primary source of truth

---

## 7. What Is NOT Built in PW-C00

- Indexer service
- Market database schema
- Market data API
- PrimeWave Dex frontend
- WebSocket market data feeds

These are deliverables for the PrimeWave Dex project (separate from PrimeWave Chain).

---

*This document is a PW-C00 design specification. No production deployment has occurred.*
