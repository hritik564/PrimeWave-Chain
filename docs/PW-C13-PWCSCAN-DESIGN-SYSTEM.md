# PW-C13 PWCScan Design System

**Sprint:** C13  
**Status:** COMPLETE — LOCKED  
**Date:** 2026-08-14

---

## 1. Design Concept

**"Deep Tech Premium"**  
A sophisticated, high-contrast visual identity. PrimeWave Blue anchors every interactive surface. Deep oceanic darks create depth in dark mode; crisp airy whites feel authoritative in light mode. Metric density is always the priority — decoration serves data, never the reverse.

---

## 2. Color Palette

### CSS Variables (Light Mode — `:root`)
| Token | Value | Usage |
|---|---|---|
| `--primary` | `221 83% 53%` | PrimeWave Blue — links, CTAs, active state |
| `--background` | `210 40% 98%` | Page background |
| `--foreground` | `222 47% 11%` | Primary text |
| `--card` | `0 0% 100%` | Card surfaces |
| `--card-border` | `214 32% 91%` | Card borders |
| `--muted` | `210 40% 96%` | Muted backgrounds |
| `--muted-foreground` | `215 16% 47%` | Secondary text |
| `--border` | `214 32% 91%` | General borders |
| `--destructive` | `0 84% 60%` | Errors / Failed badge |

### CSS Variables (Dark Mode — `.dark`)
| Token | Value | Usage |
|---|---|---|
| `--primary` | `221 83% 63%` | Brightened blue for dark backgrounds |
| `--background` | `222 47% 7%` | Deep navy page background |
| `--foreground` | `210 40% 98%` | Near-white text |
| `--card` | `222 47% 11%` | Elevated card surfaces |
| `--card-border` | `217 33% 18%` | Subtle card borders |
| `--muted` | `222 47% 14%` | Muted backgrounds |
| `--muted-foreground` | `215 20% 65%` | Secondary text |

---

## 3. Typography

| Role | Font | Weight | Usage |
|---|---|---|---|
| Display / Metric | Outfit | 700 | Page titles, MetricCard values, hero headings |
| Body | Inter | 400–600 | All UI body text, labels, descriptions |
| Mono | JetBrains Mono | 400–600 | Hashes, addresses, JSON payloads, raw tx input |

Fonts loaded via Google Fonts in `index.css`.

---

## 4. Domain-Specific Components (`src/components/pwcscan/`)

### `AddressDisplay`
Renders a truncated Ethereum address with one-click copy.
```tsx
<AddressDisplay address="0x1234...ABCD" showCopy={true} chars={6} />
```
- Default: `0x1234...ABCD` (6 chars each side)
- Full address on hover/focus
- Click → clipboard copy with checkmark feedback
- Monospace font, links to `/address/:address`

### `HashDisplay`
Same as `AddressDisplay` but for 32-byte tx/block hashes.
```tsx
<HashDisplay hash="0xabc...def" showCopy={true} chars={8} />
```
- Default: `0xabcd1234...ef56789a` (8 chars each side)
- Links to `/tx/:hash` or `/blocks/hash/:hash` depending on `linkTo` prop

### `CopyButton`
Icon-only button that copies a string value to clipboard.
```tsx
<CopyButton value="0x1234..." className="h-9 w-9" />
```
- Shows `Copy` icon → transitions to `Check` icon for 2 seconds on success
- Uses `navigator.clipboard.writeText`

### `QRModal`
Dialog rendering a QR code for any string value (address, validator ID).
```tsx
<QRModal value="0x1234..." title="Address" />
```
- Trigger: QR-code icon button
- Renders QR in a canvas element inside a `<Dialog>`
- Copies value on scan

### `StatusBadge`
Maps status strings to colored pill badges.
```tsx
<StatusBadge status="success" label="Success" />
<StatusBadge status="failed" label="Failed" />
```
| Status | Color |
|---|---|
| `success` | Emerald green |
| `failed` | Red |
| `pending` | Amber |
| `active` | Blue |
| `inactive` | Gray |
| `paused` | Orange |

### `ValidatorStatusBadge`
Maps the numeric validator status code to a `StatusBadge`.
```tsx
<ValidatorStatusBadge status={2} />
```
| Code | Label | Color |
|---|---|---|
| 0 | Unknown | Gray |
| 1 | PendingAdded | Amber |
| 2 | Active | Green |
| 3 | PendingRemoved | Orange |
| 4 | Completed | Blue |
| 5 | Invalidated | Red |

### `MetricCard`
Dashboard KPI card with icon, label, value, and optional subtitle.
```tsx
<MetricCard
  title="Latest Block"
  value="1,234,567"
  subtitle="10s ago"
  icon={<Blocks className="h-5 w-5" />}
  isLoading={false}
/>
```
- Shows a `Skeleton` when `isLoading={true}`
- Value typography: Outfit Bold

### `DataTable<T>`
Generic table component with skeleton loading, empty state, and optional pagination.
```tsx
<DataTable
  columns={[{ key: 'hash', header: 'Tx Hash', render: (tx) => <HashDisplay hash={tx.hash} /> }]}
  data={txs}
  isLoading={isLoading}
  keyExtractor={(tx) => tx.hash}
  pagination={{ hasPrev, hasNext, onPrev, onNext }}
/>
```
- Renders 5 skeleton rows while loading
- `EmptyState` when data is empty and not loading
- Horizontal scroll on mobile
- Hover highlight on rows

### `Pagination`
Cursor-based prev/next pagination control.
```tsx
<Pagination hasPrev={true} hasNext={false} onPrev={prev} onNext={next} label="25 items" />
```

### `GasBar`
Compact horizontal progress bar for gas used vs gas limit.
```tsx
<GasBar used="15000000" limit="30000000" />
```
- Green fill → amber if >85% utilized
- Shows percentage label

### `ReserveBar`
Visual reserve indicator for the RewardVault — shows emitted vs remaining out of total funded.
```tsx
<ReserveBar funded="1000000..." emitted="100000..." />
```
- Blue fill (emitted portion), gray remainder
- Shows `X.XX% Emitted` left and `100 - X.XX% Remaining` right

### `EventLogItem`
Expandable decoded event display.
```tsx
<EventLogItem event={decodedEvent} />
```
- Header: contract name (or address) + event name badge
- Collapsed: single line
- Expanded: formatted parameter table (key → value pairs from `decoded_json`)

### `EmptyState`
Polished empty state with icon, title, and description.
```tsx
<EmptyState type="not-found" title="Block not found" description="Block #99999 does not exist." />
```

### `ErrorState`
Error display with retry button for API failures.
```tsx
<ErrorState title="Cannot connect to indexer" onRetry={refetch} />
```

---

## 5. shadcn/ui Components Used

From `src/components/ui/` — all standard shadcn/ui v2 components:
`Button`, `Card`, `Badge`, `Tabs`, `Dialog`, `Sheet`, `Skeleton`, `Separator`, `Tooltip`, `DropdownMenu`, `Select`, `Table`, `Progress`, `ScrollArea`

---

## 6. Motion & Animation

- **Page mount**: `framer-motion` `fadeIn` (opacity 0→1, y 8→0, 0.3s)
- **Modal open/close**: scale-in/out via Dialog
- **Row hover**: `transition-colors 150ms` via Tailwind
- **Skeleton**: Tailwind `animate-pulse`
- **Copy feedback**: icon swap with 200ms transition

---

## 7. Responsive Breakpoints

| Breakpoint | Width | Layout |
|---|---|---|
| Mobile | < 768px | Single column, hamburger nav, stacked metric cards |
| Tablet | 768px–1024px | 2-column grids, side-by-side tables |
| Desktop | > 1024px | 3-column metric grids, full table columns visible |

---

## 8. Icons

All icons from `lucide-react`. No emojis anywhere.

Key icons used:
| Context | Icon |
|---|---|
| Blocks | `Blocks` |
| Transactions | `ArrowRightLeft` |
| Validators | `ShieldCheck` |
| Contracts | `FileCode` |
| Staking | `Shield` |
| Rewards | `ShieldAlert` |
| Fees | `Coins` |
| Governance | `Gavel` |
| Stats | `Activity` |
| Search | `Search` |
| Copy | `Copy` / `Check` |
| QR | `QrCode` |
| Gas | `Gauge` |
