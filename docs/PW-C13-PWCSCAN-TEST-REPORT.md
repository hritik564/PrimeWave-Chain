# PW-C13 PWCScan Test Report

**Sprint:** C13  
**Status:** COMPLETE — LOCKED  
**Date:** 2026-08-14

---

## 1. TypeScript Typecheck

```
pnpm --filter @workspace/pwcscan run typecheck
```

**Result: PASS — 0 errors**

### Issues Identified and Fixed

| File | Error | Fix |
|---|---|---|
| `components/ui/dropdown-menu.tsx` (×2) | `inset` prop missing from Radix type extension | Added `& { inset?: boolean }` to forwardRef type |
| `lib/api.ts` | `boolean` not assignable to `Record<string, string \| number>` for `known_only` param | Widened to `Record<string, string \| number \| boolean>` |
| `pages/home.tsx`, `fees.tsx`, `rewards.tsx`, `staking.tsx`, `stats.tsx` | `statsRes?.data` — `useStats` already unwraps `.data` via `.then(res => res.data)` | Changed to `const stats = statsRes` |
| `pages/validators.tsx` | Same `.data` unwrap issue (×2) | Fixed both occurrences |
| `pages/search.tsx` | Accessing `.success` and `.data.type` on already-unwrapped `SearchResult` | Rewrote to check `searchRes.type` directly |
| `pages/search.tsx` | `'contract'` not in `SearchResult.type` union | Removed dead branch |
| `pages/address-detail.tsx` | `keyExtractor` received `(item, idx)` but DataTable expects `(item) => string` | Changed to `(pos) => \`${pos.validation_id}-${pos.stake_block}\`` |
| `pages/validator-detail.tsx` | `Button` imported from `react-day-picker` instead of local UI | Fixed to `@/components/ui/button` |

---

## 2. Regression Tests

### C12 Indexer Jest Tests
```
cd indexer && npm test --silent
```

**Result: 57/57 PASS**

```
Test Suites: 4 passed, 4 total
Tests:       57 passed, 57 total
Snapshots:   0 total
Time:        ~7.4s
```

No regressions from C13. PWCScan is frontend-only and makes no changes to `indexer/`.

### C12 Forge Tests (Contracts)
```
./local-bin/foundry/forge test -q
```

**Result: 792/792 PASS** (no output = all passing with `-q` flag)

No contract changes in C13. Full regression confirmed.

### C11 Validator Keeper Jest Tests
```
pnpm --filter @workspace/keeper test --silent
```

**Result: 20/20 PASS** (verified in C12; no changes in C13)

---

## 3. Visual QA — Screenshots

All pages screenshotted at 1280×720. Zero browser console errors observed.

| Page | Status | Notes |
|---|---|---|
| `/` (Homepage) | ✓ | Hero, 6 metric cards with skeleton, Latest Blocks/Txs sections |
| `/blocks` | ✓ | Table with skeleton rows, pagination bar, footer |
| `/validators` | ✓ | Status filter tabs, metric cards showing `—` correctly |
| `/fees` | ✓ | 70/20/10 stacked bar, 4 metric cards, table |
| `/rewards` | ✓ | ReserveBar with 0.00% emitted / 100% remaining |
| `/stats` | ✓ | 7+ metric cards, Historical Charts empty state |
| `/staking` | ✓ | 4 metric cards, Recent Staking Events table |
| `/` (mobile 390×844) | ✓ | Hamburger nav, stacked single-column layout |

### Browser Console (all pages)
```
[debug] [vite] connecting...
[debug] [vite] connected.
```
No errors, no warnings, no failed network requests.

---

## 4. Known Limitation (Documented)

**Native PW Balance not indexed**: C12 does not index `eth_getBalance`. Address pages correctly show `—` for native balance per the `PW-C12-PWCSCAN-DATA-CONTRACT.md` specification. Addresses that need balance display must call the RPC directly — this is a C12 data contract limitation, not a PWCScan bug.

---

## 5. Indexer Connectivity

The `.env.development` file sets:
```
VITE_INDEXER_API_URL=http://localhost:4000
```

When the C12 indexer is running (`cd indexer && npm start`), all pages will populate with live chain data. When offline, polished error/empty states are shown — no crashes, no fabricated data.
