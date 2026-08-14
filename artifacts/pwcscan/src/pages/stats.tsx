import { useStats } from "@/lib/api"
import { ErrorState } from "@/components/pwcscan/error-state"
import { MetricCard } from "@/components/pwcscan/metric-card"
import { formatPW, formatNumber } from "@/lib/format"
import { Activity, Blocks, ArrowRightLeft, Users, ShieldAlert, Coins } from "lucide-react"

export default function Stats() {
  const { data: statsRes, isLoading, error, refetch } = useStats()
  const stats = statsRes

  if (error) return <ErrorState onRetry={refetch} />

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
            value={formatNumber(stats?.network.currentBlock || 0)}
            icon={<Blocks className="h-5 w-5" />}
            isLoading={isLoading}
          />
          <MetricCard
            title="Transactions"
            value={formatNumber(stats?.transactions.total || "0")}
            icon={<ArrowRightLeft className="h-5 w-5" />}
            isLoading={isLoading}
          />
          <MetricCard
            title="TPS (60s avg)"
            value={stats?.transactions.tps_60s ? stats.transactions.tps_60s.toFixed(2) : "0.00"}
            icon={<Activity className="h-5 w-5" />}
            isLoading={isLoading}
          />
          <MetricCard
            title="Active Validators"
            value={formatNumber(stats?.validators.activeCount || "0")}
            icon={<Users className="h-5 w-5" />}
            isLoading={isLoading}
          />
        </div>

        <MetricCard
          title="RewardVault Remaining"
          value={stats ? formatPW(stats.rewardVault.totalFunded) : "0 PW"}
          subtitle={`Emission: ${stats ? formatPW(stats.rewardVault.emissionRate) : '0 PW'}/s`}
          icon={<ShieldAlert className="h-5 w-5" />}
          isLoading={isLoading}
        />
        <MetricCard
          title="RewardVault Emitted"
          value={stats ? formatPW(stats.rewardVault.totalEmitted) : "0 PW"}
          icon={<ShieldAlert className="h-5 w-5 text-primary" />}
          isLoading={isLoading}
        />
        <MetricCard
          title="Fees Distributed"
          value={stats ? formatPW(stats.fees.totalDistributed) : "0 PW"}
          icon={<Coins className="h-5 w-5" />}
          isLoading={isLoading}
        />
        <MetricCard
          title="Fees to Validators"
          value={stats ? formatPW(stats.fees.totalToValidators) : "0 PW"}
          icon={<Coins className="h-5 w-5 text-emerald-500" />}
          isLoading={isLoading}
        />
        <MetricCard
          title="Gas Limit (Latest Block)"
          value={stats ? formatNumber(stats.gas.gasLimitLatestBlock) : "0"}
          isLoading={isLoading}
        />
        <MetricCard
          title="Gas Used (Latest Block)"
          value={stats ? formatNumber(stats.gas.gasUsedLatestBlock) : "0"}
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
