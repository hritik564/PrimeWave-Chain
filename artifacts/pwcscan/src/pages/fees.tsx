import { NetworkLink } from "@/lib/network"
import { useCursorPagination } from "@/hooks/use-cursor-pagination"
import { Coins, Flame, Briefcase } from "lucide-react"
import { useFees, useStats, type FeeEvent, type FeesOverview } from "@/lib/api"
import { formatPW, formatHash } from "@/lib/format"
import { DataTable } from "@/components/pwcscan/data-table"
import { ErrorState } from "@/components/pwcscan/error-state"
import { MetricCard } from "@/components/pwcscan/metric-card"
import { Card, CardContent } from "@/components/ui/card"

function allocationPercentages(summary: FeesOverview["summary"]): {
  validators: number;
  treasury: number;
  burn: number;
} | null {
  if (!summary) return null
  try {
    const validatorShare = BigInt(summary.total_validator)
    const treasuryShare = BigInt(summary.total_treasury)
    const burnShare = BigInt(summary.total_burn)
    const totalShares = validatorShare + treasuryShare + burnShare
    if (totalShares <= 0n) return null
    const percent = (share: bigint) => Number((share * 10_000n) / totalShares) / 100
    return {
      validators: percent(validatorShare),
      treasury: percent(treasuryShare),
      burn: percent(burnShare),
    }
  } catch {
    return null
  }
}

export default function Fees() {
  const { cursor, hasPrevious, goPrevious, goNext } = useCursorPagination()
  const { data: feesRes, isLoading, error, refetch } = useFees({ limit: 25, cursor })
  const { data: statsRes } = useStats()
  
  const stats = statsRes
  const summary = feesRes?.data.summary ?? null
  const allocation = allocationPercentages(summary)

  if (error) return <ErrorState onRetry={refetch} />

  const columns = [
    {
      key: "tx",
      header: "Tx Hash",
      render: (evt: FeeEvent) => (
        <NetworkLink href={`/tx/${evt.tx_hash}`} className="font-mono text-primary hover:underline">
          {formatHash(evt.tx_hash)}
        </NetworkLink>
      )
    },
    {
      key: "block",
      header: "Block",
      render: (evt: FeeEvent) => (
        <NetworkLink href={`/blocks/${evt.block_number}`} className="text-primary hover:underline">
          {evt.block_number}
        </NetworkLink>
      )
    },
    {
      key: "total",
      header: "Total Fee",
      render: (evt: FeeEvent) => <span className="font-mono font-medium text-xs">{formatPW(evt.total_amount)}</span>
    },
    {
      key: "validator",
      header: "To Validators",
      render: (evt: FeeEvent) => <span className="font-mono text-xs text-emerald-600 dark:text-emerald-400">{formatPW(evt.validator_share)}</span>
    },
    {
      key: "treasury",
      header: "To Treasury",
      render: (evt: FeeEvent) => <span className="font-mono text-xs text-blue-600 dark:text-blue-400">{formatPW(evt.treasury_share)}</span>
    },
    {
      key: "burn",
      header: "Burned",
      render: (evt: FeeEvent) => <span className="font-mono text-xs text-destructive">{formatPW(evt.burn_share)}</span>
    }
  ]

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4">
        <div>
          <h1 className="text-3xl font-display font-bold tracking-tight mb-2">Fee Distribution</h1>
          <p className="text-muted-foreground">Distribution amounts come from indexed FeeDistributed events.</p>
        </div>

        <Card className="bg-card border-none shadow-none mb-2 overflow-visible">
          <CardContent className="p-0">
            {allocation ? (
              <>
                <div className="flex h-6 w-full overflow-hidden rounded-full">
                  <div className="h-full bg-emerald-500" style={{ width: `${allocation.validators}%` }} />
                  <div className="h-full bg-blue-500" style={{ width: `${allocation.treasury}%` }} />
                  <div className="h-full bg-red-500" style={{ width: `${allocation.burn}%` }} />
                </div>
                <div className="flex flex-wrap justify-between gap-2 px-1 pt-2 text-xs font-medium text-muted-foreground">
                  <span className="text-emerald-600 dark:text-emerald-400">Validators ({allocation.validators.toFixed(2)}%)</span>
                  <span className="text-blue-600 dark:text-blue-400">Treasury ({allocation.treasury.toFixed(2)}%)</span>
                  <span className="text-red-600 dark:text-red-400">Burn ({allocation.burn.toFixed(2)}%)</span>
                </div>
              </>
            ) : (
              <p className="text-sm text-muted-foreground">
                Allocation data is unavailable until the FeeDistributor is configured and the indexer is synchronized.
              </p>
            )}
          </CardContent>
        </Card>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-2">
          <MetricCard 
            title="Total Distributed"
            value={stats?.fees.totalDistributed === null || !stats ? "Unavailable" : formatPW(stats.fees.totalDistributed)}
            icon={<Coins className="h-5 w-5" />}
          />
          <MetricCard 
            title="To Validators"
            value={stats?.fees.totalToValidators === null || !stats ? "Unavailable" : formatPW(stats.fees.totalToValidators)}
          />
          <MetricCard 
            title="To Treasury"
            value={summary ? formatPW(summary.total_treasury) : "Unavailable"}
            icon={<Briefcase className="h-5 w-5" />}
          />
          <MetricCard 
            title="Burned"
            value={summary ? formatPW(summary.total_burn) : "Unavailable"}
            icon={<Flame className="h-5 w-5 text-destructive" />}
          />
        </div>
      </div>

      <div className="bg-card rounded-xl border">
        <div className="px-6 py-4 border-b">
          <h2 className="text-lg font-semibold">Recent Fee Distributions</h2>
        </div>
        <DataTable 
          columns={columns}
          data={feesRes?.data.events}
          isLoading={isLoading}
          keyExtractor={(evt) => `${evt.tx_hash}-${evt.id}`}
          className="border-0 shadow-none"
          pagination={{
            hasPrev: hasPrevious,
            hasNext: !!feesRes?.pagination.nextCursor,
            onPrev: goPrevious,
            onNext: () => goNext(feesRes?.pagination.nextCursor),
          }}
        />
      </div>
    </div>
  )
}
