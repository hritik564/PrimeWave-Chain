import { useState } from "react"
import { NetworkLink } from "@/lib/network"
import { Server, ShieldCheck, Zap } from "lucide-react"
import { useValidators, useStats } from "@/lib/api"
import { formatPW, formatHash, formatNumber } from "@/lib/format"
import { DataTable } from "@/components/pwcscan/data-table"
import { ValidatorStatusBadge } from "@/components/pwcscan/status-badge"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { ErrorState } from "@/components/pwcscan/error-state"
import { MetricCard } from "@/components/pwcscan/metric-card"
import { Validator } from "@/lib/api"
import { Button } from "@/components/ui/button"
import { useCursorPagination } from "@/hooks/use-cursor-pagination"

export default function Validators() {
  const [statusFilter, setStatusFilter] = useState<number | undefined>(undefined)
  const pagination = useCursorPagination<string>()
  const { data: valsRes, isLoading, error, refetch } = useValidators({
    status: statusFilter,
    limit: 25,
    cursor: pagination.cursor,
  })
  const { data: statsRes } = useStats()

  if (error) return <ErrorState onRetry={refetch} />

  const columns = [
    {
      key: "id",
      header: "Validator ID",
      render: (v: Validator) => (
        <div className="flex items-center gap-2">
          <Server className="h-4 w-4 text-muted-foreground" />
          <NetworkLink href={`/validator/${v.validation_id}`} className="font-mono font-medium text-primary hover:underline">
            {formatHash(v.validation_id)}
          </NetworkLink>
        </div>
      )
    },
    {
      key: "status",
      header: "Status",
      render: (v: Validator) => <ValidatorStatusBadge status={v.status} />
    },
    {
      key: "recipient",
      header: "Reward Recipient",
      render: (v: Validator) => <AddressDisplay address={v.reward_recipient} />
    },
    {
      key: "uptime",
      header: "Uptime",
      render: (v: Validator) => (
        <span className={v.uptime_bips > 9900 ? "text-emerald-600 dark:text-emerald-400 font-medium" : "text-amber-600 font-medium"}>
          {(v.uptime_bips / 100).toFixed(2)}%
        </span>
      )
    },
    {
      key: "fees",
      header: "Total Claimed",
      render: (v: Validator) => <span className="font-mono text-xs">{formatPW(v.total_fees_claimed)}</span>
    }
  ]

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4">
        <div>
          <h1 className="text-3xl font-display font-bold tracking-tight mb-2">Validators</h1>
          <p className="text-muted-foreground">Network validators securing PrimeWave Chain.</p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-2">
          <MetricCard 
            title="Active Validators"
            value={statsRes ? formatNumber(statsRes.validators.activeCount) : "Unavailable"}
            icon={<ShieldCheck className="h-5 w-5" />}
          />
          <MetricCard 
            title="Total Validator Rewards"
            value={statsRes ? formatPW(statsRes.fees.totalToValidators) : "Unavailable"}
            icon={<Zap className="h-5 w-5" />}
          />
        </div>
        
        <div className="flex bg-muted p-1 rounded-lg w-fit">
          <Button 
            variant="ghost" 
            size="sm"
            className={statusFilter === undefined ? "bg-background shadow-sm" : ""}
            onClick={() => { setStatusFilter(undefined); pagination.reset() }}
          >
            All
          </Button>
          <Button 
            variant="ghost" 
            size="sm"
            className={statusFilter === 2 ? "bg-background shadow-sm" : ""}
            onClick={() => { setStatusFilter(2); pagination.reset() }}
          >
            Active
          </Button>
          <Button 
            variant="ghost" 
            size="sm"
            className={statusFilter === 1 ? "bg-background shadow-sm" : ""}
            onClick={() => { setStatusFilter(1); pagination.reset() }}
          >
            Pending
          </Button>
        </div>
      </div>

      <DataTable 
        columns={columns}
        data={valsRes?.data}
        isLoading={isLoading}
        keyExtractor={(v) => v.validation_id}
        pagination={{
          hasPrev: pagination.hasPrevious,
          hasNext: !!valsRes?.pagination.nextCursor,
          onPrev: pagination.goPrevious,
          onNext: () => pagination.goNext(valsRes?.pagination.nextCursor),
        }}
      />
    </div>
  )
}
