import { NetworkDataMismatchError, useStats } from "@/lib/api"
import { ErrorState } from "@/components/pwcscan/error-state"
import { MetricCard } from "@/components/pwcscan/metric-card"
import { formatPW, formatNumber } from "@/lib/format"
import { Activity, Blocks, ArrowRightLeft, Users, ShieldAlert, Coins } from "lucide-react"

export default function Stats() {
  const { data: statsRes, isLoading, error, refetch } = useStats()
  const stats = statsRes

  if (error) {
    return (
      <ErrorState
        title={error instanceof NetworkDataMismatchError ? "Network data mismatch" : undefined}
        message={error instanceof Error ? error.message : undefined}
        onRetry={refetch}
      />
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-display font-bold tracking-tight mb-2">Network Statistics</h1>
        <p className="text-muted-foreground">Real-time metrics for the PrimeWave Chain.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-3 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <MetricCard
            title="Current Block"
            value={stats ? formatNumber(stats.network.currentBlock) : "Unavailable"}
            icon={<Blocks className="h-5 w-5" />}
            isLoading={isLoading}
          />
          <MetricCard
            title="Transactions"
            value={stats ? formatNumber(stats.transactions.total) : "Unavailable"}
            icon={<ArrowRightLeft className="h-5 w-5" />}
            isLoading={isLoading}
          />
          <MetricCard
            title="TPS (60s avg)"
            value={
              stats?.transactions.tps_60s === null || !stats
                ? "Unavailable"
                : stats.transactions.tps_60s.toFixed(2)
            }
            icon={<Activity className="h-5 w-5" />}
            isLoading={isLoading}
          />
          <MetricCard
            title="Active Validators"
            value={stats ? formatNumber(stats.validators.activeCount) : "Unavailable"}
            icon={<Users className="h-5 w-5" />}
            isLoading={isLoading}
          />
        </div>

        <MetricCard
          title="RewardVault Remaining"
          value={stats?.rewardVault.totalFunded === null || !stats ? "Unavailable" : formatPW(stats.rewardVault.totalFunded)}
          subtitle={stats?.rewardVault.emissionRate === null || !stats ? undefined : `Emission: ${formatPW(stats.rewardVault.emissionRate)}/s`}
          icon={<ShieldAlert className="h-5 w-5" />}
          isLoading={isLoading}
        />
        <MetricCard
          title="RewardVault Emitted"
          value={stats?.rewardVault.totalEmitted === null || !stats ? "Unavailable" : formatPW(stats.rewardVault.totalEmitted)}
          icon={<ShieldAlert className="h-5 w-5 text-primary" />}
          isLoading={isLoading}
        />
        <MetricCard
          title="Fees Distributed"
          value={stats?.fees.totalDistributed === null || !stats ? "Unavailable" : formatPW(stats.fees.totalDistributed)}
          icon={<Coins className="h-5 w-5" />}
          isLoading={isLoading}
        />
        <MetricCard
          title="Fees to Validators"
          value={stats?.fees.totalToValidators === null || !stats ? "Unavailable" : formatPW(stats.fees.totalToValidators)}
          icon={<Coins className="h-5 w-5 text-emerald-500" />}
          isLoading={isLoading}
        />
        <MetricCard
          title="Gas Limit (Latest Block)"
          value={stats?.gas.gasLimitLatestBlock === null || !stats ? "Unavailable" : formatNumber(stats.gas.gasLimitLatestBlock)}
          isLoading={isLoading}
        />
        <MetricCard
          title="Gas Used (Latest Block)"
          value={stats?.gas.gasUsedLatestBlock === null || !stats ? "Unavailable" : formatNumber(stats.gas.gasUsedLatestBlock)}
          isLoading={isLoading}
        />
      </div>

      <div className="mt-8 p-12 border rounded-xl bg-card text-center text-muted-foreground flex flex-col items-center">
        <Activity className="h-10 w-10 text-muted-foreground/30 mb-4" />
        <h3 className="text-lg font-medium text-foreground mb-2">Historical Charts</h3>
        <p className="max-w-md">Historical network metrics charting will be available in a future update once sufficient node data has been indexed.</p>
      </div>
    </div>
  )
}
