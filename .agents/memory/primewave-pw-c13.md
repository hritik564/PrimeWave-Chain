---
name: PrimeWave Chain PW-C13
description: C13 COMPLETE — PWCScan blockchain explorer frontend; design subagent build; typecheck clean; all regressions pass
---

# PW-C13: PWCScan Blockchain Explorer

## Status: COMPLETE AND LOCKED

## Key Facts
- Artifact: `artifacts/pwcscan/` — React + TypeScript + Vite, preview path `/`
- Workflow: `artifacts/pwcscan: web`
- Chain ID: 73571
- API source: C12 indexer REST API (no OpenAPI codegen — hand-written client)
- Dev env var: `VITE_INDEXER_API_URL=http://localhost:4000` in `.env.development`

## Architecture Decisions
- **No codegen**: C12 is standalone npm, not workspace OpenAPI. `src/lib/api.ts` has typed fetch client + 17 React Query hooks written directly.
- **BigInt-safe**: `src/lib/format.ts` uses BigInt throughout. Never `Number(wei_string)`.
- **Stats hook unwraps**: `useStats()` returns `Stats` directly (unwrapped via `.then(res => res.data)`). Pages must use `const stats = statsRes` NOT `statsRes?.data`.
- **Paginated hooks do NOT unwrap**: `useBlocks()`, `useTransactions()`, etc. return `PaginatedApiResponse<T>` — access `.data` to get the array.
- **Dark mode**: class-based Tailwind dark strategy; ThemeProvider in `src/lib/settings.tsx`
- **Native balance not shown**: C12 doesn't index eth_getBalance; address pages show `—`

## TypeCheck Pitfalls Fixed
- Radix dropdown-menu: `inset` prop needs `& { inset?: boolean }` on forwardRef type
- `apiRequest` params type: `Record<string, string | number | boolean>` (not just string|number)
- `useStats` data is already unwrapped — pages must NOT access `.data` on the result

## Test Results
- TypeScript typecheck: 0 errors
- C12 Indexer Jest: 57/57
- Forge (contracts): 792/792
- Keeper Jest: 20/20 (unchanged)

## Files
- `artifacts/pwcscan/src/lib/api.ts` — API client + all hooks + TypeScript interfaces
- `artifacts/pwcscan/src/lib/format.ts` — BigInt-safe formatting utilities
- `artifacts/pwcscan/src/lib/settings.tsx` — Theme/settings context
- `artifacts/pwcscan/src/components/pwcscan/` — 13 domain-specific components
- `artifacts/pwcscan/src/pages/` — 15 pages (all routes implemented)
- `docs/PW-C13-PWCSCAN-*.md` — 5 locked documentation files
