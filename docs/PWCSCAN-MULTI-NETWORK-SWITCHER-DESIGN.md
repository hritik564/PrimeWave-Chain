# PWCScan — Multi-Network Switcher Implementation Design

**Status:** Design only  
**Scope:** PWCScan frontend architecture and configuration  
**Networks:** Devnet / Local Development, Testnet, Mainnet placeholder  
**Chain 77, contracts, validators, production infrastructure:** Unchanged

## 1. Executive summary

PWCScan currently behaves as a single-network explorer:

- `src/lib/api.ts` resolves one global `VITE_INDEXER_API_URL`.
- `src/pages/home.tsx` reads one global `VITE_NETWORK_LABEL` and `VITE_CHAIN_ID`.
- `src/components/layout/NavBar.tsx` displays the global network label.
- React Query keys do not include a network identifier.
- Wouter routes do not include a network identifier.
- Vite proxies only the local `/indexer-api` path.

The implementation should introduce one typed network registry and one active-network context. Every data request, React Query key, route, header label, chain ID, endpoint, and contract-address lookup must derive from that active network.

The recommended shape is:

```text
URL network scope
        │
        ▼
NetworkProvider
        │
        ├── selected network metadata
        ├── selected network endpoints
        ├── selected network contract addresses
        ├── header/mobile switcher
        └── network-aware route/link helpers
                │
                ▼
        Network-aware API client
                │
                ▼
        React Query keys scoped by network
```

Mainnet is represented as a real selectable option, but remains explicitly unconfigured. Selecting it must show a clear unavailable state and must never fall back to Testnet or Devnet.

## 2. Existing architecture findings

### 2.1 Current frontend structure

[ESTABLISHED]

- React + Vite application under `artifacts/pwcscan`.
- Wouter handles routing.
- `App.tsx` creates one global `QueryClient`.
- `SettingsProvider` stores user preferences in `localStorage`.
- `AppLayout` renders `NavBar`, page content, and footer.
- `NavBar` calls `useStats()` for sync status.
- Pages call hooks from `src/lib/api.ts`.

### 2.2 Current data source

[ESTABLISHED]

`src/lib/api.ts` has one `getApiBase()` function:

- It reads `VITE_INDEXER_API_URL`.
- It falls back to `/indexer-api`.
- Local Vite proxies `/indexer-api/*` to the local indexer at `127.0.0.1:4000`.
- All existing API hooks ultimately call `apiRequest()`.

[ESTABLISHED] The explorer currently consumes the indexer API for page data. It does not currently maintain a separate direct-chain RPC client.

[IMPLEMENTATION REQUIRED] The network registry should still carry an RPC URL for network identity, external links, future wallet/RPC functionality, and validation. Explorer page data should continue to come from the selected network's indexer API.

### 2.3 Current network identity surfaces

[ESTABLISHED]

- `VITE_NETWORK_LABEL` is shown in the navbar and home page.
- `VITE_CHAIN_ID` is used as a fallback on the home page.
- The API `/stats` response also contains a `network.chainId`.
- Existing home-page copy says to set `VITE_NETWORK_LABEL` to Testnet and leave it unset for Devnet.
- This global environment-variable approach cannot safely represent three networks simultaneously.

### 2.4 Current routing and links

[ESTABLISHED]

- Routes are network-agnostic, such as `/blocks`, `/tx/:hash`, and `/validator/:id`.
- Internal links are written directly with Wouter `Link`.
- There are direct links across the home, blocks, transactions, validator, staking, rewards, fees, contracts, address, and not-found pages.
- Refreshing the current route does not currently encode a selected network.

[IMPLEMENTATION REQUIRED] Network-aware route/link helpers must replace direct network-agnostic internal navigation.

## 3. Network model

### 3.1 Network identifiers

Use a closed internal union:

```ts
type NetworkId = 'devnet' | 'testnet' | 'mainnet';
```

These IDs are stable application identifiers and should not be derived from labels or Chain IDs.

### 3.2 Network definition

Introduce a data-only configuration type similar to:

```ts
type NetworkStatus = 'configured' | 'unconfigured';

interface NetworkDefinition {
  id: NetworkId;
  label: string;
  shortLabel: string;
  status: NetworkStatus;
  chainId: number | null;
  rpcUrl: string | null;
  indexerApiUrl: string | null;
  contractAddresses: Partial<Record<ContractName, string>>;
  visual: {
    color: 'devnet' | 'testnet' | 'mainnet';
    badgeClass: string;
  };
}
```

The registry must be the only source of truth for these values.

### 3.3 Required network entries

#### Devnet / Local Development

[TESTNET VERIFIED / ESTABLISHED]

- ID: `devnet`.
- Label: `Devnet`.
- Chain ID: `73571`.
- Indexer API: existing local `/indexer-api` configuration.
- Data source: existing local-development indexer.
- RPC URL: existing local-development RPC configuration where needed.
- Contract addresses: existing local-development addresses where consumed.
- Status: `configured`.

The implementation must preserve the existing local Vite proxy behavior and must not replace it with a browser request to `localhost:4000`.

#### Testnet

[TESTNET VERIFIED]

- ID: `testnet`.
- Label: `Testnet`.
- Chain ID: `77`.
- Indexer API: existing Chain 77 testnet indexer/API.
- RPC URL: existing Chain 77 testnet RPC configuration.
- Contract addresses: existing Chain 77 testnet deployment manifest/configuration.
- Status: `configured`.

The exact external endpoint values should come from the existing testnet deployment configuration. They must not be invented or copied from an unrelated environment.

#### Mainnet

[MAINNET DECISION / IMPLEMENTATION REQUIRED]

- ID: `mainnet`.
- Label: `Mainnet`.
- Chain ID: `null` until approved.
- Indexer API: `null` until finalized.
- RPC URL: `null` until finalized.
- Contract addresses: empty or explicitly absent.
- Status: `unconfigured`.

Mainnet must be selectable for UX validation, but it must not make a network request while unconfigured and must never borrow Testnet or Devnet configuration.

## 4. Configuration strategy

### 4.1 Recommended configuration source

[IMPLEMENTATION REQUIRED] Centralize configuration in one module, for example:

```text
artifacts/pwcscan/src/lib/network-config.ts
```

The module should:

- define `NetworkId` and `NetworkDefinition`;
- assemble the three network entries;
- normalize endpoint URLs;
- validate required fields for configured networks;
- expose a lookup by network ID;
- expose the safe default network;
- reject unknown network IDs;
- reject partially configured Mainnet at runtime.

Adding finalized Mainnet later should require filling the Mainnet configuration, not rewriting API hooks, routes, pages, or the switcher.

### 4.2 Environment variable migration

The current generic variables should be replaced by network-scoped configuration:

```text
VITE_DEVNET_INDEXER_API_URL
VITE_DEVNET_RPC_URL
VITE_TESTNET_INDEXER_API_URL
VITE_TESTNET_RPC_URL
VITE_MAINNET_INDEXER_API_URL
VITE_MAINNET_RPC_URL
VITE_DEFAULT_NETWORK
```

Contract-address variables should also be network-scoped, or supplied through a typed network manifest:

```text
VITE_DEVNET_ADDR_*
VITE_TESTNET_ADDR_*
VITE_MAINNET_ADDR_*
```

[IMPLEMENTATION REQUIRED] During migration:

- Devnet must default to the existing `/indexer-api` proxy.
- The current testnet API value must be mapped explicitly to the Testnet entry.
- `VITE_NETWORK_LABEL` and `VITE_CHAIN_ID` must no longer drive runtime network selection.
- `VITE_INDEXER_API_URL` must not remain a shared fallback for all three networks.
- Mainnet variables must remain empty/unset until mainnet is finalized.

The old variables may be accepted temporarily by a migration adapter only when the target network is explicit. They must not be used as an implicit cross-network fallback.

### 4.3 Safe default selection

Network selection precedence:

1. Valid network ID in the URL.
2. Previously selected network in `localStorage`.
3. Explicit `VITE_DEFAULT_NETWORK`.
4. `devnet` as the safe development fallback.

Rules:

- Mainnet must never be the implicit fallback.
- An unknown URL network must render a clear invalid-network state or redirect to the safe default.
- URL selection always wins over local storage.
- Storage is convenience only; the URL is the shareable source of truth.

## 5. Network context and state

### 5.1 NetworkProvider

[IMPLEMENTATION REQUIRED] Add a `NetworkProvider` inside `WouterRouter` and above `AppLayout`.

It should expose:

```ts
interface NetworkContextValue {
  networkId: NetworkId;
  network: NetworkDefinition;
  setNetwork: (id: NetworkId) => void;
  isConfigured: boolean;
  buildNetworkPath: (path: string, id?: NetworkId) => string;
}
```

The provider should derive the active network from the current URL and keep `localStorage` synchronized.

### 5.2 Switching behavior

When the user chooses a network:

1. Validate the target ID against the registry.
2. Update the URL to the target network scope.
3. Persist the selected ID for future visits.
4. Cancel active requests for the previous network where appropriate.
5. Render the target network context immediately.
6. Start queries against only the target network endpoint.
7. Show a loading state instead of previous-network data.
8. If unconfigured, show the explicit unavailable state and make no API request.

The previous network's React Query cache may remain available for fast return, but it must not be rendered under a different network key.

### 5.3 Query cache isolation

Every query key must begin with the network ID:

```ts
['network', networkId, 'stats']
['network', networkId, 'blocks', params]
['network', networkId, 'transaction', hash]
['network', networkId, 'validator', validatorId]
```

This applies to every hook in `src/lib/api.ts`, including:

- stats;
- blocks;
- block detail;
- transactions;
- transaction detail;
- addresses;
- address transactions;
- validators;
- validator detail/events;
- staking;
- rewards;
- fees;
- contracts; and
- search.

No query key may omit the network ID.

## 6. API client design

### 6.1 Network-aware requests

Replace the module-global `getApiBase()` behavior with a client that receives the selected `NetworkDefinition`:

```ts
apiRequest(network, path, params)
```

or a context-bound client:

```ts
const api = useNetworkApi();
api.request('/blocks', params);
```

The second form is preferred for preventing individual pages from accidentally selecting the wrong configuration.

### 6.2 Endpoint behavior

For a configured network:

- Normalize relative and absolute API URLs using the existing `formatApiUrl()` behavior.
- Preserve the local relative `/indexer-api` path for Devnet.
- Use the explicit existing Testnet indexer/API endpoint for Testnet.
- Use the finalized Mainnet endpoint only after mainnet configuration is approved.

For an unconfigured network:

- Do not call `fetch`.
- Return a typed `NetworkUnavailableError`.
- Render a clear "Mainnet configuration pending" state.
- Do not try another network.

### 6.3 Chain ID verification

[IMPLEMENTATION REQUIRED] `useStats()` should validate that the selected configuration matches the API response:

```text
configured network chain ID
        must equal
stats.network.chainId
```

On mismatch:

- discard the response;
- do not render the data;
- show a visible "Network data mismatch" error;
- include the selected network and expected/received Chain IDs;
- stop auto-refresh until the endpoint is corrected or the user switches networks.

This is the primary defense against an endpoint being accidentally assigned to the wrong network.

### 6.4 Response scope

The selected network is part of the client request context even though the current indexer API does not require a network query parameter.

Do not add a network query parameter unless the existing API contract explicitly supports it. Network separation should come from:

- the selected configuration;
- the selected endpoint;
- URL scope;
- React Query keys; and
- Chain ID validation.

## 7. Routing design

### 7.1 Recommended URL shape

Use a network prefix while preserving the existing page paths:

```text
/devnet/
/devnet/blocks
/devnet/blocks/123
/devnet/tx/0x...
/devnet/address/0x...

/testnet/
/testnet/validators
/testnet/search?q=...

/mainnet/
/mainnet/contracts
```

Within the artifact's existing `BASE_URL`, these paths remain relative to the PWCScan artifact.

### 7.2 Why path scope is preferred

- Refresh preserves the selected network.
- Shared links carry the selected network.
- Browser history records network changes.
- A Testnet transaction link cannot silently open against Devnet.
- Query keys and URL scope reinforce each other.
- Future network additions use the same route structure.

### 7.3 Route migration

[IMPLEMENTATION REQUIRED]

Refactor route definitions in `App.tsx` so every page route is network-scoped.

Recommended route shape:

```text
/:networkId
/:networkId/blocks
/:networkId/blocks/:number
/:networkId/transactions
/:networkId/tx/:hash
/:networkId/address/:address
/:networkId/contract/:address
/:networkId/contracts
/:networkId/validators
/:networkId/validator/:id
/:networkId/staking
/:networkId/rewards
/:networkId/fees
/:networkId/governance
/:networkId/stats
/:networkId/search
```

The artifact `BASE_URL` remains the Wouter router base. The network prefix is an application route segment, not a replacement for `BASE_URL`.

### 7.4 Legacy route compatibility

[IMPLEMENTATION REQUIRED] Existing unscoped links such as `/blocks` should either:

- redirect to `/${safeDefaultNetwork}/blocks`; or
- be retained only as a short-lived compatibility route that immediately normalizes to a network-scoped URL.

The normalized URL must be the canonical URL after navigation.

### 7.5 Network-aware links

Introduce a `NetworkLink` wrapper or `useNetworkPath()` helper. All existing internal links must use it, including links in:

- `NavBar`;
- `home.tsx`;
- `blocks.tsx`;
- `transactions.tsx`;
- `transaction-detail.tsx`;
- `address-detail.tsx`;
- `contracts.tsx`;
- `validators.tsx`;
- `validator-detail.tsx`;
- `staking.tsx`;
- `rewards.tsx`;
- `fees.tsx`; and
- `not-found.tsx`.

The helper must preserve the current network and append query parameters without losing the network prefix.

## 8. Header and switcher UX

### 8.1 Header placement

Add a dedicated `NetworkSwitcher` beside the PWCScan brand in `NavBar`.

The selected network must always be visible without opening the menu:

```text
PWCScan   [Devnet · Chain 73571 ▾]
PWCScan   [Testnet · Chain 77 ▾]
PWCScan   [Mainnet · Not configured ▾]
```

The exact visual treatment can follow the existing shadcn/Radix dropdown conventions.

### 8.2 Visual distinction

Use stable network-specific visual tokens:

| Network | Visual treatment | Meaning |
|---|---|---|
| Devnet | Violet/blue badge | Local development; disposable data |
| Testnet | Amber/orange badge | Chain 77 test environment |
| Mainnet | Green/emerald when configured; muted gray with pending indicator while unconfigured | Production network or not yet available |

The label should include both the environment and Chain ID when known.

Avoid relying on color alone. Include text and, where useful, an icon or status dot.

### 8.3 Dropdown contents

Each option should show:

- Network name.
- Short environment description.
- Chain ID when configured.
- Status such as `Connected`, `Configured`, or `Configuration pending`.

Mainnet remains selectable for testing the placeholder state. It must not be presented as live.

### 8.4 Mobile navigation

The same switcher must be present in the mobile menu, not only in the desktop header.

The mobile menu should show:

- Current network at the top.
- All three options.
- Mainnet configuration-pending status.
- Network selection before the page links.

### 8.5 Home-page identity

Remove the home page's direct dependency on `VITE_NETWORK_LABEL` and `VITE_CHAIN_ID`.

The home page should read from `useNetwork()` and display:

- selected label;
- configured Chain ID or `Not configured`;
- selected network status;
- API/indexer sync status only when the network is configured.

## 9. Mainnet placeholder behavior

Selecting Mainnet before final configuration must produce a deliberate state:

```text
Mainnet
Configuration pending

Mainnet network identity and explorer endpoints will appear here
after the architecture and deployment are finalized.

No Mainnet data source is configured.
```

Rules:

- No `fetch` call.
- No use of Testnet API.
- No use of Devnet API.
- No testnet contract addresses.
- No fake blocks, transactions, validators, or stats.
- No "Synced" state.
- No Chain ID value.
- No silent redirect to another network.

## 10. Contract-address configuration

### 10.1 Address manifest

Add a typed address manifest to each network definition:

```ts
type ContractName =
  | 'emergencyMultisig'
  | 'timelock'
  | 'validatorFeeVault'
  | 'devTreasury'
  | 'feeDistributor'
  | 'validatorRegistry'
  | 'rewardVault'
  | 'stakingManager';
```

Configured Devnet and Testnet entries may contain the addresses already used by those environments.

The Mainnet entry must contain no placeholder addresses that could be mistaken for real deployments.

### 10.2 Usage

Pages and helpers that need protocol-address metadata must read:

```ts
network.contractAddresses.feeDistributor
```

They must not import a global testnet address manifest.

If a configured network lacks an address required for a page:

- show an explicit configuration error;
- do not substitute an address from another network;
- do not create a link that could resolve against the wrong chain.

## 11. Files and implementation units

This is the proposed implementation split; no changes are made in the design phase.

### New modules

- `artifacts/pwcscan/src/lib/network-config.ts`
  - network IDs, definitions, endpoint resolution, address manifests, validation.
- `artifacts/pwcscan/src/lib/network-context.tsx`
  - URL synchronization, persistence, active network context, switch behavior.
- `artifacts/pwcscan/src/lib/network-routes.ts`
  - route parsing, route building, legacy normalization.
- `artifacts/pwcscan/src/components/layout/NetworkSwitcher.tsx`
  - desktop and mobile switcher UI.
- `artifacts/pwcscan/src/components/pwcscan/network-state.tsx`
  - configured, loading, unavailable, and mismatch states if a shared component is useful.

### Existing modules to update during implementation

- `artifacts/pwcscan/src/App.tsx`
  - provider placement and network-scoped routes.
- `artifacts/pwcscan/src/lib/api.ts`
  - network-aware client, query keys, mismatch validation.
- `artifacts/pwcscan/src/components/layout/NavBar.tsx`
  - switcher, selected label, network-aware navigation.
- `artifacts/pwcscan/src/pages/home.tsx`
  - selected network metadata and mismatch/unavailable states.
- All page files containing internal Wouter links
  - replace direct links with network-aware links.
- `artifacts/pwcscan/src/lib/settings.tsx`
  - only if network persistence is intentionally grouped with existing preferences; a separate network context is preferred.
- `artifacts/pwcscan/vite.config.ts`
  - only if an additional same-origin proxy is needed for an already-approved endpoint. No production infrastructure change is implied.

## 12. Implementation sequence

1. Add the typed network definitions with Devnet, Testnet, and unconfigured Mainnet.
2. Add config validation and explicit safe-default behavior.
3. Add URL parsing and `NetworkProvider`.
4. Add network-scoped route definitions and legacy URL normalization.
5. Add the header/mobile switcher.
6. Convert `api.ts` to a network-aware client.
7. Add network IDs to every React Query key.
8. Add API Chain ID mismatch validation.
9. Convert all internal links to preserve the active network.
10. Add Mainnet unavailable state.
11. Add visual network identity to navbar and home.
12. Verify Devnet against the existing local indexer.
13. Verify Testnet against the existing Chain 77 indexer/API.
14. Verify Mainnet makes no request and does not inherit another config.

## 13. Safety invariants

The implementation is correct only if all of these hold:

1. The selected network is visible in the header and mobile navigation.
2. The selected network is present in the URL after navigation.
3. Refreshing a deep link preserves the selected network.
4. Every API request uses the selected network's endpoint.
5. Every React Query key includes the selected network ID.
6. Switching networks never renders the previous network's cached response under the new network label.
7. Stats Chain ID must match the selected configuration.
8. Devnet remains on Chain ID `73571` and the existing local `/indexer-api` path.
9. Testnet remains on Chain ID `77` and the existing testnet indexer/API.
10. Mainnet has no endpoint, Chain ID, or contract-address fallback.
11. No testnet or devnet value is read from a global singleton after the network context exists.
12. Network-specific internal links preserve the active network.
13. A network mismatch is a visible error, not a warning that still renders data.
14. Missing configuration fails explicitly.
15. No direct browser request to local `localhost:4000` is introduced.

## 14. Verification plan

### Configuration tests

- Registry returns exactly `devnet`, `testnet`, and `mainnet`.
- Devnet resolves to Chain ID `73571`.
- Testnet resolves to Chain ID `77`.
- Mainnet resolves to `unconfigured`.
- Unknown network IDs are rejected.
- Mainnet has no endpoint fallback.

### Routing tests

- `/devnet/blocks` resolves to Devnet.
- `/testnet/tx/:hash` resolves to Testnet.
- `/mainnet/validators` resolves to Mainnet placeholder state.
- Refreshing a network-scoped detail URL preserves its network.
- Legacy unscoped routes normalize to a safe network URL.
- Internal links preserve the active network.

### API and cache tests

- API URL selection differs by network.
- Query keys differ by network for the same page and parameters.
- Switching networks does not reuse the previous network's result.
- Testnet stats with Chain ID `77` pass validation.
- A mismatched stats Chain ID produces an error and no rendered data.
- Unconfigured Mainnet performs zero API calls.

### UI tests

- Header visibly identifies Devnet, Testnet, and Mainnet.
- Mobile navigation includes the same switcher.
- Mainnet pending state is visually distinct.
- Loading the new network does not display old network rows or stats.
- Search and detail pages retain network scope.

### Manual acceptance checks

1. Open Devnet home and confirm local data and Chain ID `73571`.
2. Switch to Testnet and confirm the URL changes and Chain ID `77` data appears.
3. Refresh a Testnet block or transaction URL and confirm it remains Testnet.
4. Switch to Mainnet and confirm no request is made and the pending state appears.
5. Navigate back to Devnet and confirm the local data source returns.
6. Open a shared network-scoped link in a fresh tab and confirm the URL determines the network.
7. Confirm no network shows data from another network.

## 15. Non-goals for this phase

- No mainnet Chain ID selection.
- No mainnet RPC or indexer endpoint selection.
- No mainnet contract addresses.
- No mainnet deployment.
- No Chain 77 infrastructure changes.
- No contract changes.
- No validator changes.
- No backend database changes.
- No new production proxy or TLS configuration.
- No direct blockchain transactions.

## 16. Implementation approval boundary

The next implementation phase may proceed once the owner confirms:

- the path-scoped URL strategy;
- the Devnet/Testnet endpoint mapping;
- the intended persistence precedence;
- the visual network treatments;
- the Mainnet placeholder behavior; and
- whether the network manifest should be environment variables only or a runtime-loaded manifest.

The implementation should not require another architecture redesign when the finalized Mainnet values become available.

**Design outcome:** PWCScan will have one reusable multi-network shell, isolated data/cache/routing contexts, explicit environment identity, and a Mainnet placeholder that cannot accidentally display Testnet or Devnet data.