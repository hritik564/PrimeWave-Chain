import { useState } from "react"
import { Link } from "wouter"
import { Shield, ShieldAlert, ArrowUpRight, ArrowDownRight } from "lucide-react"
import { useStaking, useStats } from "@/lib/api"
import { formatPW, formatHash, formatEmissionRate } from "@/lib/format"
import { DataTable } from "@/components/pwcscan/data-table"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { ErrorState } from "@/components/pwcscan/error-state"
import { MetricCard } from "@/components/pwcscan/metric-card"
import { StakingEvent } from "@/lib/api"
import { Badge } from "@/components/ui/badge"

export default function Staking() {
  const [cursor, setCursor] = useState<number | undefined>(undefined)
  const { data: stakingRes, isLoading, error, refetch } = useStaking({ limit: 25, cursor })
  const { data: statsRes } = useStats()
  
  const stats = statsRes

  if (error) return <ErrorState onRetry={refetch} />

  const columns = [
    {
      key: "tx",
      header: "Tx Hash",
      render: (evt: StakingEvent) => (
        <Link href={`/tx/${evt.tx_hash}`} className="font-mono text-primary hover:underline">
          {formatHash(evt.tx_hash)}
        </Link>
      )
    },
    {
      key: "event",
      header: "Action",
      render: (evt: StakingEvent) => {
        if (evt.event_name === "StakeAdded") {
          return <Badge variant="outline" className="bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border-emerald-500/20 gap-1"><ArrowUpRight className="h-3 w-3" /> Stake Added</Badge>
        }
        if (evt.event_name === "StakeReturned") {
          return <Badge variant="outline" className="bg-amber-500/10 text-amber-700 dark:text-amber-400 border-amber-500/20 gap-1"><ArrowDownRight className="h-3 w-3" /> Stake Returned</Badge>
        }
        return <Badge variant="outline">{evt.event_name}</Badge>
      }
    },
    {
      key: "validator",
      header: "Validator",
      render: (evt: StakingEvent) => evt.validation_id ? (
        <Link href={`/validator/${evt.validation_id}`} className="font-mono text-primary hover:underline">
          {formatHash(evt.validation_id)}
        </Link>
      ) : <span>-</span>
    },
    {
      key: "address",
      header: "Staker",
      render: (evt: StakingEvent) => <AddressDisplay address={evt.address} />
    },
    {
      key: "amount",
      header: "Amount",
      render: (evt: StakingEvent) => <span className="font-mono font-medium text-xs">{formatPW(evt.amount)}</span>
    }
  ]

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4">
        <div>
          <h1 className="text-3xl font-display font-bold tracking-tight mb-2">Staking</h1>
          <p className="text-muted-foreground">Validator staking activities on PrimeWave.</p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-2">
          <MetricCard 
            title="Active Validators"
            value={stats?.validators.activeCount || "-"}
            icon={<Shield className="h-5 w-5" />}
          />
          <MetricCard 
            title="Total Staking Emitted"
            value={stats ? formatPW(stats.rewardVault.totalEmitted) : "-"}
          />
          <MetricCard 
            title="Emission Rate"
            value={stats ? formatEmissionRate(stats.rewardVault.emissionRate) : "-"}
          />
          <MetricCard 
            title="RewardVault Remaining"
            value={stats ? formatPW(stats.rewardVault.totalFunded) : "-"}
            icon={<ShieldAlert className="h-5 w-5" />}
          />
        </div>
      </div>

      <div className="bg-card rounded-xl border">
        <div className="px-6 py-4 border-b">
          <h2 className="text-lg font-semibold">Recent Staking Events</h2>
        </div>
        <DataTable 
          columns={columns}
          data={stakingRes?.data}
          isLoading={isLoading}
          keyExtractor={(evt) => `${evt.tx_hash}-${evt.id}`}
          className="border-0 shadow-none"
          pagination={{
            hasPrev: false,
            hasNext: !!stakingRes?.pagination?.nextCursor,
            onPrev: () => setCursor(undefined),
            onNext: () => {
              if (stakingRes?.pagination?.nextCursor) setCursor(stakingRes.pagination.nextCursor)
            }
          }}
        />
      </div>
    </div>
  )
}
