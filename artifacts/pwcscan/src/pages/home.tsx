import {
  Activity,
  ArrowDownRight,
  ArrowRight,
  ArrowUpRight,
  Blocks,
  CircleHelp,
  Clock3,
  ExternalLink,
  Gauge,
  Search,
  ShieldCheck,
  Users,
  Waves,
} from 'lucide-react';
import { useState } from 'react';
import { useLocation } from 'wouter';
import { NetworkDataMismatchError, useBlocks, useStats, useTransactions } from '@/lib/api';
import { formatAge, formatHash, formatNumber, formatPW } from '@/lib/format';
import { NetworkLink, useNetwork } from '@/lib/network';
import { useSettings } from '@/lib/settings';
import { AddressDisplay } from '@/components/pwcscan/address-display';
import { ExplorerSearch } from '@/components/pwcscan/explorer-search';
import { HashDisplay } from '@/components/pwcscan/hash-display';
import { StatusBadge } from '@/components/pwcscan/status-badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';

function Metric({ label, value, foot, icon: Icon, loading }: {
  label: string;
  value: string;
  foot?: string;
  icon: typeof Activity;
  loading: boolean;
}) {
  return (
    <Card className="pw-metric-card">
      <CardContent className="p-5 sm:p-6">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">{label}</p>
            <p className="mt-3 truncate font-display text-2xl font-semibold tracking-tight sm:text-[1.8rem]">
              {loading ? <span className="pw-skeleton inline-block h-7 w-28 align-middle" /> : value}
            </p>
            {foot && !loading && <p className="mt-1.5 text-xs text-muted-foreground">{foot}</p>}
          </div>
          <span className="pw-metric-icon"><Icon className="h-[18px] w-[18px]" /></span>
        </div>
      </CardContent>
    </Card>
  );
}

function LoadingRows({ count = 4 }: { count?: number }) {
  return <div className="divide-y divide-border/70">{Array.from({ length: count }, (_, i) => (
    <div className="grid grid-cols-[1fr_auto] items-center gap-3 py-4" key={i}>
      <span className="pw-skeleton h-4 w-32" /><span className="pw-skeleton h-4 w-16" />
    </div>
  ))}</div>;
}

export default function Home() {
  const { autoRefresh } = useSettings();
  const { network, isConfigured, buildNetworkPath } = useNetwork();
  const [, setLocation] = useLocation();
  const [queryError, setQueryError] = useState('');
  const { data: stats, isLoading: statsLoading, error: statsError, refetch } = useStats(autoRefresh ? 15000 : undefined);
  const { data: blockResponse, isLoading: blocksLoading } = useBlocks({ limit: 6 });
  const { data: txResponse, isLoading: txsLoading } = useTransactions({ limit: 6 });
  const blocks = blockResponse?.data ?? [];
  const transactions = txResponse?.data ?? [];

  const latestBlock = stats?.network.currentBlock;
  const syncError = statsError instanceof NetworkDataMismatchError
    ? 'The configured RPC and indexer do not report the same network. Data is hidden until the mismatch is corrected.'
    : statsError instanceof Error ? statsError.message : '';

  return (
    <div className="pw-home space-y-7 sm:space-y-9">
      <section className="pw-hero relative isolate overflow-hidden rounded-[1.65rem] border px-5 py-7 sm:px-9 sm:py-9 lg:px-12 lg:py-11">
        <div className="pw-hero-orbit pw-hero-orbit-one" aria-hidden="true" />
        <div className="pw-hero-orbit pw-hero-orbit-two" aria-hidden="true" />
        <div className="relative z-10 grid gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(320px,440px)] lg:items-end">
          <div>
            <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-primary/15 bg-white/70 px-3 py-1.5 text-xs font-semibold text-primary shadow-sm dark:bg-black/20">
              <span className={`h-2 w-2 rounded-full ${stats?.network.isSynced ? 'bg-emerald-500' : 'bg-amber-500'} ${stats?.network.isSynced ? 'pw-live-dot' : ''}`} />
              {stats?.network.isSynced ? 'Network synchronized' : stats ? 'Indexer catching up' : `${network.label} data connection pending`}
            </div>
            <p className="mb-2 text-xs font-semibold uppercase tracking-[0.2em] text-primary/75">PrimeWave · {network.label} explorer</p>
            <h1 className="max-w-2xl font-display text-4xl font-semibold leading-[1.06] tracking-[-0.045em] sm:text-5xl lg:text-[3.6rem]">
              Explore the <span className="pw-gradient-text">PrimeWave</span> network.
            </h1>
            <p className="mt-4 max-w-xl text-sm leading-6 text-muted-foreground sm:text-base">
              Follow blocks, transactions and on-chain activity, all in one place.
            </p>
            <div className="mt-6 flex flex-wrap gap-2">
              <span className="pw-hero-chip"><Waves className="h-3.5 w-3.5" /> Chain ID {network.chainId ?? 'pending'}</span>
              <span className="pw-hero-chip">Native asset <strong>{network.nativeCurrency.symbol}</strong></span>
              <span className="pw-hero-chip"><ShieldCheck className="h-3.5 w-3.5" /> {network.id === 'mainnet' ? 'Avalanche L1' : network.id === 'devnet' ? 'Local development' : 'Test network'}</span>
            </div>
          </div>
          <form className="relative" role="search" onSubmit={(event) => {
            event.preventDefault();
            const form = event.currentTarget;
            const value = String(new FormData(form).get('q') ?? '').trim();
            if (!value) { setQueryError('Enter an address, transaction hash, or block number.'); return; }
            setQueryError('');
            setLocation(buildNetworkPath(`/search?q=${encodeURIComponent(value)}`));
          }}>
            <label htmlFor="mainnet-search" className="mb-2 block text-xs font-semibold text-foreground/80">Search the blockchain</label>
            <div className="pw-search-shell flex items-center gap-2 rounded-xl border bg-background/95 p-1.5 shadow-lg shadow-primary/5 focus-within:ring-2 focus-within:ring-primary/30">
              <Search className="ml-3 h-4 w-4 shrink-0 text-muted-foreground" />
              <input id="mainnet-search" name="q" autoComplete="off" spellCheck={false}
                placeholder="Address, transaction, block…"
                className="h-10 min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground/70" />
              <Button type="submit" size="sm" className="h-10 rounded-lg px-4">Search<ArrowRight className="ml-2 h-4 w-4" /></Button>
            </div>
            {queryError && <p role="alert" className="mt-2 text-xs text-destructive">{queryError}</p>}
            <p className="mt-2 text-[11px] text-muted-foreground">Searches use indexed chain data. No sample or placeholder results are shown.</p>
          </form>
        </div>
      </section>

      {!isConfigured && (
        <div className="pw-notice flex flex-col gap-3 rounded-xl border border-amber-500/25 bg-amber-500/[0.06] p-4 sm:flex-row sm:items-center sm:justify-between">
          <div className="flex items-start gap-3">
            <CircleHelp className="mt-0.5 h-4 w-4 shrink-0 text-amber-600" />
            <div><p className="text-sm font-semibold">{network.label} explorer is not connected yet</p><p className="mt-1 text-xs leading-5 text-muted-foreground">No verified chain data is displayed until the {network.label} identity and its RPC/indexer services are configured and online.</p></div>
          </div>
          <span className="shrink-0 rounded-md bg-background/80 px-2.5 py-1.5 font-mono text-[11px] text-muted-foreground">RPC + indexer · not configured</span>
        </div>
      )}

      {syncError && isConfigured && (
        <div className="flex flex-col gap-3 rounded-xl border border-destructive/20 bg-destructive/[0.04] p-4 sm:flex-row sm:items-center sm:justify-between" role="alert">
          <div><p className="text-sm font-semibold">Explorer data is temporarily unavailable</p><p className="mt-1 max-w-2xl text-xs leading-5 text-muted-foreground">{syncError}</p></div>
          <Button size="sm" variant="outline" onClick={() => void refetch()}>Try again</Button>
        </div>
      )}

      <section aria-label="Network overview" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Metric label="Latest block" value={latestBlock == null ? '—' : formatNumber(latestBlock)} foot={stats?.network.latestBlockTimestamp ? formatAge(stats.network.latestBlockTimestamp) : 'Live block height'} icon={Blocks} loading={statsLoading && isConfigured} />
        <Metric label="Transactions" value={stats ? formatNumber(stats.transactions.total) : '—'} foot={stats?.transactions.tps_60s == null ? 'Total indexed' : `${stats.transactions.tps_60s.toFixed(2)} TPS · last 60 sec`} icon={ArrowRight} loading={statsLoading && isConfigured} />
        <Metric label="Active validators" value={stats ? formatNumber(stats.validators.activeCount) : '—'} foot="Reported by the indexer" icon={Users} loading={statsLoading && isConfigured} />
        <Metric label="Gas used · latest block" value={stats ? `${(Number(stats.gas.gasUsedLatestBlock) / 1_000_000).toFixed(2)}M` : '—'} foot={stats ? `of ${(Number(stats.gas.gasLimitLatestBlock) / 1_000_000).toFixed(2)}M gas` : 'Awaiting indexed block data'} icon={Gauge} loading={statsLoading && isConfigured} />
      </section>

      <section className="grid gap-5 xl:grid-cols-[1.1fr_0.9fr]">
        <Card className="pw-data-card overflow-hidden">
          <div className="flex items-center justify-between gap-3 border-b px-5 py-4 sm:px-6">
            <div className="flex items-center gap-3"><span className="pw-section-icon"><Blocks className="h-4 w-4" /></span><div><h2 className="text-sm font-semibold">Latest blocks</h2><p className="mt-0.5 text-xs text-muted-foreground">Recent canonical block activity</p></div></div>
            <Button variant="ghost" size="sm" asChild><NetworkLink href="/blocks">All blocks<ArrowRight className="ml-1.5 h-3.5 w-3.5" /></NetworkLink></Button>
          </div>
          <div className="px-5 sm:px-6">
            <div className="pw-table-head grid grid-cols-[1fr_0.9fr_auto] gap-3 py-3 text-[10px] font-semibold uppercase tracking-[0.13em] text-muted-foreground"><span>Height / age</span><span>Validator</span><span className="text-right">Txns</span></div>
            {blocksLoading && isConfigured ? <LoadingRows /> : blocks.length ? <div className="divide-y divide-border/70">{blocks.map((block) => <div key={block.number} className="grid grid-cols-[1fr_0.9fr_auto] items-center gap-3 py-4 text-sm">
              <div className="min-w-0"><NetworkLink className="font-mono text-sm font-semibold text-primary hover:underline" href={`/blocks/${block.number}`}>{formatNumber(block.number)}</NetworkLink><p className="mt-1 text-[11px] text-muted-foreground">{formatAge(block.timestamp_unix)}</p></div>
              <div className="min-w-0">{block.coinbase ? <AddressDisplay address={block.coinbase} showCopy={false} /> : <span className="text-xs text-muted-foreground">—</span>}</div>
              <span className="text-right font-mono text-xs text-foreground/80">{formatNumber(block.transaction_count)}</span>
            </div>)}</div> : <div className="py-8 text-center"><Blocks className="mx-auto h-5 w-5 text-muted-foreground/50"/><p className="mt-2 text-sm font-medium">{isConfigured ? 'No indexed blocks yet' : 'Block data will appear here'}</p><p className="mt-1 text-xs text-muted-foreground">Only confirmed network data is displayed.</p></div>}
          </div>
        </Card>

        <Card className="pw-data-card overflow-hidden">
          <div className="flex items-center justify-between gap-3 border-b px-5 py-4 sm:px-6">
            <div className="flex items-center gap-3"><span className="pw-section-icon pw-section-icon-violet"><ArrowRight className="h-4 w-4" /></span><div><h2 className="text-sm font-semibold">Latest transactions</h2><p className="mt-0.5 text-xs text-muted-foreground">Transfers and contract calls</p></div></div>
            <Button variant="ghost" size="sm" asChild><NetworkLink href="/transactions">All transactions<ArrowRight className="ml-1.5 h-3.5 w-3.5" /></NetworkLink></Button>
          </div>
          <div className="px-5 sm:px-6">
            <div className="pw-table-head grid grid-cols-[1fr_auto] gap-3 py-3 text-[10px] font-semibold uppercase tracking-[0.13em] text-muted-foreground"><span>Transaction / block</span><span className="text-right">Value</span></div>
            {txsLoading && isConfigured ? <LoadingRows /> : transactions.length ? <div className="divide-y divide-border/70">{transactions.map((tx) => <div key={tx.hash} className="grid grid-cols-[1fr_auto] items-center gap-3 py-4 text-sm">
              <div className="min-w-0"><NetworkLink href={`/tx/${tx.hash}`} className="font-mono text-xs font-semibold text-primary hover:underline">{formatHash(tx.hash)}</NetworkLink><div className="mt-1.5 flex items-center gap-2 text-[11px] text-muted-foreground"><span>Block</span><NetworkLink className="font-mono hover:text-primary" href={`/blocks/${tx.block_number}`}>{formatNumber(tx.block_number)}</NetworkLink><span>·</span><span>{tx.to_address ? 'Transfer / call' : 'Contract creation'}</span></div></div>
              <div className="text-right"><span className="whitespace-nowrap font-mono text-xs font-medium">{formatPW(tx.value)}</span><div className="mt-1 flex items-center justify-end gap-1 text-[10px] text-muted-foreground">{tx.status === 1 ? <ArrowUpRight className="h-3 w-3 text-emerald-600"/> : <ArrowDownRight className="h-3 w-3 text-rose-500"/>}{tx.status === 1 ? 'Success' : tx.status === 0 ? 'Failed' : 'Indexed'}</div></div>
            </div>)}</div> : <div className="py-8 text-center"><Activity className="mx-auto h-5 w-5 text-muted-foreground/50"/><p className="mt-2 text-sm font-medium">{isConfigured ? 'No indexed transactions yet' : 'Transaction data will appear here'}</p><p className="mt-1 text-xs text-muted-foreground">No fabricated activity is used in this preview.</p></div>}
          </div>
        </Card>
      </section>

      <section className="grid gap-4 md:grid-cols-3">
        <NetworkLink href="/validators" className="pw-feature-link"><Users className="h-4 w-4 text-primary"/><span><strong>Validator set</strong><small>Weights, uptime and rewards</small></span><ArrowRight className="ml-auto h-4 w-4 text-muted-foreground"/></NetworkLink>
        <NetworkLink href="/contracts" className="pw-feature-link"><ShieldCheck className="h-4 w-4 text-primary"/><span><strong>Contracts</strong><small>Verified protocol addresses</small></span><ArrowRight className="ml-auto h-4 w-4 text-muted-foreground"/></NetworkLink>
        <NetworkLink href="/stats" className="pw-feature-link"><Clock3 className="h-4 w-4 text-primary"/><span><strong>Network stats</strong><small>Indexing health and activity</small></span><ExternalLink className="ml-auto h-4 w-4 text-muted-foreground"/></NetworkLink>
      </section>
      {stats && <p className="text-right text-[11px] text-muted-foreground">Index height {formatNumber(stats.network.latestIndexed)} of {formatNumber(stats.network.chainHead)} · refreshed from the connected indexer</p>}
    </div>
  );
}
