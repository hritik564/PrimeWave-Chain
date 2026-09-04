import { Link } from "wouter"
import { Blocks, ArrowRightLeft, Activity, Users, ShieldAlert, Coins } from "lucide-react"
import { useStats, useBlocks, useTransactions } from "@/lib/api"
import { formatPW, formatAge, formatNumber, formatHash } from "@/lib/format"
import { useSettings } from "@/lib/settings"
import { MetricCard } from "@/components/pwcscan/metric-card"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { HashDisplay } from "@/components/pwcscan/hash-display"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { StatusBadge } from "@/components/pwcscan/status-badge"
import { ErrorState } from "@/components/pwcscan/error-state"

// VITE_NETWORK_LABEL: set to "Testnet" for testnet builds, leave unset for dev.
// This ensures the explorer NEVER displays "Mainnet" when running on a test network.
const networkLabel = import.meta.env.VITE_NETWORK_LABEL ?? ""

export default function Home() {
  const { autoRefresh } = useSettings()
  const configuredChainId = import.meta.env.VITE_CHAIN_ID?.trim() || undefined
  
  const { data: statsRes, isLoading: statsLoading, error: statsError, refetch: refetchStats } = useStats(autoRefresh ? 10000 : undefined)
  const { data: blocksRes, isLoading: blocksLoading } = useBlocks({ limit: 10 })
  const { data: txsRes, isLoading: txsLoading } = useTransactions({ limit: 10 })

  const stats = statsRes
  const chainId = stats?.network.chainId ?? configuredChainId
  const blocks = blocksRes?.data || []
  const txs = txsRes?.data || []

  if (statsError) {
    return (
      <div className="space-y-6">
        <ErrorState 
          title="Cannot connect to PrimeWave indexer" 
          message="The API might be offline or you need to set VITE_INDEXER_API_URL."
          onRetry={refetchStats} 
        />
      </div>
    )
  }

  return (
    <div className="space-y-8">
      {/* Hero Section */}
      <section className="bg-primary/5 rounded-3xl p-8 md:p-12 border border-primary/10 relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-primary/10 to-transparent pointer-events-none" />
        <div className="relative z-10 max-w-2xl">
          <h1 className="text-3xl md:text-5xl font-display font-bold tracking-tight mb-4 text-foreground">
            PrimeWave Explorer
          </h1>
          <p className="text-lg text-muted-foreground mb-6">
            The premier blockchain explorer for the PrimeWave ecosystem. Search blocks, transactions, validators, and more.
          </p>
          <div className="flex flex-wrap items-center gap-3">
            {networkLabel && (
              <Badge variant="outline" className="bg-orange-500/10 border-orange-500/40 text-orange-600 dark:text-orange-400 font-semibold backdrop-blur">
                🧪 {networkLabel}
              </Badge>
            )}
            <Badge variant="outline" className="bg-background/50 backdrop-blur">
              Chain ID: {chainId ?? "Unavailable"}
            </Badge>
            <Badge variant="outline" className="bg-background/50 backdrop-blur text-primary border-primary/20">
              {stats?.network.isSynced ? '🟢 Synced' : '🟡 Syncing...'}
            </Badge>
          </div>
        </div>
      </section>

      {/* Stats Grid */}
      <section className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <MetricCard
          title="Latest Block"
          value={formatNumber(stats?.network.currentBlock || 0)}
          icon={<Blocks className="h-5 w-5" />}
          isLoading={statsLoading}
        />
        <MetricCard
          title="Total Transactions"
          value={formatNumber(stats?.transactions.total || "0")}
          subtitle={stats?.transactions.tps_60s ? `${stats.transactions.tps_60s.toFixed(1)} TPS` : undefined}
          icon={<ArrowRightLeft className="h-5 w-5" />}
          isLoading={statsLoading}
        />
        <MetricCard
          title="Active Validators"
          value={formatNumber(stats?.validators.activeCount || "0")}
          icon={<Users className="h-5 w-5" />}
          isLoading={statsLoading}
        />
        <MetricCard
          title="RewardVault Remaining"
          value={stats ? formatPW(stats.rewardVault.totalFunded) : "0 PW"}
          subtitle={`Emission: ${stats ? formatPW(stats.rewardVault.emissionRate) : '0 PW'}/s`}
          icon={<ShieldAlert className="h-5 w-5" />}
          isLoading={statsLoading}
        />
        <MetricCard
          title="Fees Distributed"
          value={stats ? formatPW(stats.fees.totalDistributed) : "0 PW"}
          subtitle={`${stats ? formatPW(stats.fees.totalToValidators) : '0 PW'} to validators`}
          icon={<Coins className="h-5 w-5" />}
          isLoading={statsLoading}
        />
        <MetricCard
          title="Gas Latest Block"
          value={stats ? `${(Number(stats.gas.gasUsedLatestBlock) / 1000000).toFixed(2)}M` : "0"}
          subtitle={`Limit: ${stats ? (Number(stats.gas.gasLimitLatestBlock) / 1000000).toFixed(2) : '0'}M`}
          icon={<Activity className="h-5 w-5" />}
          isLoading={statsLoading}
        />
      </section>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Latest Blocks */}
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="flex items-center gap-2">
              <Blocks className="h-5 w-5 text-primary" />
              Latest Blocks
            </CardTitle>
            <Button variant="outline" size="sm" asChild>
              <Link href="/blocks">View All</Link>
            </Button>
          </CardHeader>
          <CardContent>
            <div className="divide-y">
              {blocksLoading ? (
                Array.from({ length: 5 }).map((_, i) => (
                  <div key={i} className="py-4 flex justify-between items-center">
                    <Skeleton className="h-10 w-24" />
                    <Skeleton className="h-10 w-32" />
                  </div>
                ))
              ) : blocks.length > 0 ? (
                blocks.map((block) => (
                  <div key={block.number} className="py-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3 group">
                    <div className="flex items-center gap-4">
                      <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center shrink-0 group-hover:bg-primary/10 transition-colors">
                        <Blocks className="h-4 w-4 text-muted-foreground group-hover:text-primary transition-colors" />
                      </div>
                      <div>
                        <Link href={`/blocks/${block.number}`} className="text-primary font-medium hover:underline">
                          {block.number}
                        </Link>
                        <p className="text-xs text-muted-foreground">{formatAge(block.timestamp_unix)}</p>
                      </div>
                    </div>
                    <div className="flex flex-col sm:items-end gap-1 text-sm">
                      <div className="flex items-center gap-1">
                        <span className="text-muted-foreground">Miner</span>
                        {block.coinbase ? <AddressDisplay address={block.coinbase} showCopy={false} /> : <span>-</span>}
                      </div>
                      <div className="text-xs text-muted-foreground">
                        {block.transaction_count} txns
                      </div>
                    </div>
                  </div>
                ))
              ) : (
                <div className="py-8 text-center text-muted-foreground text-sm">No blocks found</div>
              )}
            </div>
          </CardContent>
        </Card>

        {/* Latest Transactions */}
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="flex items-center gap-2">
              <ArrowRightLeft className="h-5 w-5 text-primary" />
              Latest Transactions
            </CardTitle>
            <Button variant="outline" size="sm" asChild>
              <Link href="/transactions">View All</Link>
            </Button>
          </CardHeader>
          <CardContent>
            <div className="divide-y">
              {txsLoading ? (
                Array.from({ length: 5 }).map((_, i) => (
                  <div key={i} className="py-4 flex justify-between items-center">
                    <Skeleton className="h-10 w-32" />
                    <Skeleton className="h-10 w-24" />
                  </div>
                ))
              ) : txs.length > 0 ? (
                txs.map((tx) => (
                  <div key={tx.hash} className="py-3 flex flex-col sm:flex-row sm:items-center justify-between gap-3 group">
                    <div className="flex items-start gap-4">
                      <div className="w-10 h-10 rounded-full bg-muted flex items-center justify-center shrink-0">
                        <span className="text-xs font-medium">Tx</span>
                      </div>
                      <div className="overflow-hidden">
                        <Link href={`/tx/${tx.hash}`} className="text-primary font-medium hover:underline block truncate max-w-[150px] sm:max-w-[200px]">
                          {formatHash(tx.hash)}
                        </Link>
                        <div className="flex items-center gap-2 text-xs text-muted-foreground mt-0.5">
                          <span>Block <Link href={`/blocks/${tx.block_number}`} className="hover:text-foreground">{tx.block_number}</Link></span>
                        </div>
                      </div>
                    </div>
                    <div className="flex flex-col sm:items-end gap-1 text-sm bg-muted/30 sm:bg-transparent p-2 sm:p-0 rounded-md">
                      <div className="flex items-center gap-1.5 justify-between w-full">
                        <span className="text-muted-foreground text-xs">From</span>
                        <AddressDisplay address={tx.from_address} showCopy={false} />
                      </div>
                      <div className="flex items-center gap-1.5 justify-between w-full">
                        <span className="text-muted-foreground text-xs">To</span>
                        {tx.to_address ? (
                          <AddressDisplay address={tx.to_address} showCopy={false} />
                        ) : (
                          <StatusBadge status="active" label="Contract Creation" className="text-[10px] px-1 py-0" />
                        )}
                      </div>
                      <div className="font-mono text-xs font-semibold">
                        {formatPW(tx.value)}
                      </div>
                    </div>
                  </div>
                ))
              ) : (
                <div className="py-8 text-center text-muted-foreground text-sm">No transactions found</div>
              )}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

function Badge({ children, className, variant }: any) {
  return (
    <div className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 ${className}`}>
      {children}
    </div>
  )
}
