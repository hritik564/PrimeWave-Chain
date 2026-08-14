# PW-C13 PWCScan UI Specification

**Sprint:** C13  
**Status:** COMPLETE — LOCKED  
**Date:** 2026-08-14  
**Chain ID:** 73571

---

## 1. Overview

PWCScan is the PrimeWave Blockchain Explorer — a premium, production-quality frontend that surfaces the full data model of PrimeWave Chain through the C12 Indexer REST API. It is the authoritative read-only explorer for all on-chain activity.

### Design Philosophy
- **Information architecture** inspired by Solscan — immediate, scannable data hierarchy
- **Visual identity**: "Deep Tech Premium" — PrimeWave Blue (`HSL 221 83% 53%`) as primary anchor, deep oceanic darks for dark mode, crisp airy whites for light mode
- **Typography**: Outfit (display/metrics) · Inter (body) · JetBrains Mono (hashes/addresses/JSON)
- **Dark mode and light mode are both first-class** — system preference respected, toggle persisted to localStorage
- **Mobile responsive**: Desktop primary, mobile fully functional via hamburger nav

---

## 2. Application Architecture

### Technology Stack
- **Framework**: React 18 + TypeScript 5
- **Bundler**: Vite 7
- **Routing**: Wouter (hash-free path routing)
- **State / Data Fetching**: TanStack React Query v5
- **Styling**: Tailwind CSS v4 (class-based dark strategy)
- **Charts**: Recharts 2
- **Animation**: Framer Motion
- **Icons**: Lucide React

### Key Source Files
```
artifacts/pwcscan/src/
├── App.tsx                        # Root router + providers
├── index.css                      # Global CSS variables (light + dark palettes)
├── lib/
│   ├── api.ts                     # Typed API client + React Query hooks
│   ├── format.ts                  # All formatting utilities (BigInt-safe)
│   └── settings.tsx               # Settings context (theme, time format, auto-refresh)
├── components/
│   ├── layout/
│   │   ├── AppLayout.tsx          # Page wrapper with nav + footer
│   │   └── NavBar.tsx             # Top navigation with search + theme toggle
│   ├── pwcscan/                   # Domain-specific components
│   └── ui/                        # shadcn/ui base components
└── pages/                         # 15 route pages
```

---

## 3. Formatting Library (`src/lib/format.ts`)

All monetary/amount values from C12 are **decimal strings** representing wei-denominated integers. The formatter library uses `BigInt` throughout — `Number()` is never used on wei values.

| Function | Description | Example Output |
|---|---|---|
| `formatPW(wei)` | Full 4-sig-fig PW display | `"1.2345 PW"` |
| `formatPWCompact(wei)` | Compact with K/M/B suffix | `"1.23K PW"` |
| `formatHash(hash, chars=8)` | Truncated 32-byte hash | `"0x1234...ABCD"` |
| `formatAddress(addr, chars=6)` | Truncated address | `"0x1234...ABCD"` |
| `formatAge(unixTs)` | Relative time | `"2 mins ago"` |
| `formatTimestamp(unixTs)` | Full ISO-style timestamp | `"2026-08-14 16:30:00"` |
| `formatNumber(n)` | Comma-formatted integer | `"1,234,567"` |
| `formatGas(gas)` | Comma-formatted gas | `"21,000"` |
| `formatGasPercent(used, limit)` | Utilisation % | `"42.3%"` |
| `formatEmissionRate(weiPerSec)` | Annual PW rate | `"X PW / year"` |

---

## 4. API Client (`src/lib/api.ts`)

### Configuration
The indexer base URL is read from `VITE_INDEXER_API_URL` environment variable. When unset or empty, all API calls fail immediately with a typed `ApiError(503)` and the UI shows a banner + polished error states. No fake data is ever displayed.

### Response Envelope
Every C12 endpoint returns:
```ts
// Success (singular)
{ success: true, data: T }

// Success (paginated)
{ success: true, data: T[], pagination: { limit: number, nextCursor: number | null } }

// Failure
{ success: false, error: string }
```

The client unwraps these transparently. React Query hooks return `T` directly for singular endpoints and `PaginatedApiResponse<T>` for paginated ones.

### Hook Inventory
| Hook | Endpoint | Returns |
|---|---|---|
| `useStats(refetchInterval?)` | `GET /stats` | `Stats` |
| `useBlocks(params?)` | `GET /blocks` | `PaginatedApiResponse<Block>` |
| `useBlock(numberOrHash)` | `GET /blocks/:n` or `/blocks/hash/:h` | `Block` |
| `useTransactions(params?)` | `GET /transactions` | `PaginatedApiResponse<Transaction>` |
| `useTransaction(hash)` | `GET /transactions/:hash` | `Transaction` |
| `useAddress(address)` | `GET /addresses/:addr` | `Address` |
| `useAddressTransactions(addr, params?)` | `GET /addresses/:addr/transactions` | `PaginatedApiResponse<Transaction>` |
| `useValidators(params?)` | `GET /validators` | `Validator[]` |
| `useValidator(id)` | `GET /validators/:id` | `Validator` |
| `useValidatorEvents(id, params?)` | `GET /validators/:id/events` | `PaginatedApiResponse<ValidatorEvent>` |
| `useStaking(params?)` | `GET /staking` | `PaginatedApiResponse<StakingEvent>` |
| `useStakingByAddress(addr)` | `GET /staking/:addr` | `StakingPosition[]` |
| `useRewards()` | `GET /rewards` | `RewardsOverview` |
| `useRewardsByAddress(addr, params?)` | `GET /rewards/:addr` | `PaginatedApiResponse<RewardEvent>` |
| `useFees(params?)` | `GET /fees` | `FeesOverview` |
| `useContracts(params?)` | `GET /contracts` | `PaginatedApiResponse<Contract>` |
| `useSearch(q)` | `GET /search?q=` | `SearchResult` |

---

## 5. Settings Context (`src/lib/settings.tsx`)

Persisted to `localStorage` key `pwcscan_settings`:

| Setting | Type | Default | Description |
|---|---|---|---|
| `theme` | `'system'\|'light'\|'dark'` | `'system'` | Color scheme preference |
| `addressDisplay` | `'truncated'\|'full'` | `'truncated'` | Address truncation toggle |
| `timeFormat` | `'local'\|'utc'` | `'local'` | Timestamp display format |
| `autoRefresh` | `boolean` | `true` | Polling for homepage stats/blocks/txs |

---

## 6. Layout Shell

### NavBar
- Left: PWCScan logo → links to `/`
- Center: `Blocks` · `Transactions` · `Contracts` · `Validators` · `More` (dropdown for Staking/Rewards/Fees/Governance/Stats)
- Right: global search input → `/search?q=` · theme toggle · settings gear
- Mobile: logo left, settings + hamburger right → slide-out sheet with full nav

### Footer
- Left: `© 2026 PrimeWave Chain Explorer. All rights reserved.`
- Right: `API` · `Terms` · `Privacy` links

### Syncing Banner
When `stats.network.isSynced === false`, a yellow banner or status badge indicates the indexer is still catching up.

### Offline Banner
When `VITE_INDEXER_API_URL` is empty/not set, a blue info banner appears: "Indexer offline — configure VITE_INDEXER_API_URL to connect".

---

## 7. UX Constraints

1. **No fake data**: Empty/offline states show `—` or polished EmptyState, never fabricated values
2. **No PW/USD price, market cap, TVL, or circulating supply** — not provided by C12
3. **BigInt safety**: No `Number(wei_string)` anywhere in the codebase
4. **Read-only**: No wallet connect, no write operations, no private key fields
5. **No emojis**: Lucide React icons only throughout
6. **Copy-on-click**: All addresses and hashes copy to clipboard with visual checkmark feedback
7. **SEO**: `document.title` set per page (e.g. `"Block #12345 | PWCScan"`)
8. **Validator status map**: 0=Unknown, 1=PendingAdded, 2=Active, 3=PendingRemoved, 4=Completed, 5=Invalidated
9. **`data-testid` attributes** on all interactive elements and key data displays

---

## 8. Development Environment

### `.env.development`
```
VITE_INDEXER_API_URL=http://localhost:4000
```

### Start PWCScan Dev Server
```bash
pnpm --filter @workspace/pwcscan run dev
```

The workflow `artifacts/pwcscan: web` manages this via the Replit artifact system.
