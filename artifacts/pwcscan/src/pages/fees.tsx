import { useState } from "react"
import { Link } from "wouter"
import { Coins, Flame, Briefcase } from "lucide-react"
import { useFees, useStats } from "@/lib/api"
import { formatPW, formatHash } from "@/lib/format"
import { DataTable } from "@/components/pwcscan/data-table"
import { ErrorState } from "@/components/pwcscan/error-state"
import { MetricCard } from "@/components/pwcscan/metric-card"
import { FeeEvent } from "@/lib/api"
import { Card, CardContent } from "@/components/ui/card"

export default function Fees() {
  const [cursor, setCursor] = useState<number | undefined>(undefined)
  const { data: feesRes, isLoading, error, refetch } = useFees({ limit: 25, cursor })
  const { data: statsRes } = useStats()
  
  const stats = statsRes

  if (error) return <ErrorState onRetry={refetch} />

  const columns = [
    {
      key: "tx",
      header: "Tx Hash",
      render: (evt: FeeEvent) => (
        <Link href={`/tx/${evt.tx_hash}`} className="font-mono text-primary hover:underline">
          {formatHash(evt.tx_hash)}
        </Link>
      )
    },
    {
      key: "block",
      header: "Block",
      render: (evt: FeeEvent) => (
        <Link href={`/blocks/${evt.block_number}`} className="text-primary hover:underline">
          {evt.block_number}
        </Link>
      )
    },
    {
      key: "total",
      header: "Total Fee",
      render: (evt: FeeEvent) => <span className="font-mono font-medium text-xs">{formatPW(evt.total_amount)}</span>
    },
    {
      key: "validator",
      header: "To Validators (70%)",
      render: (evt: FeeEvent) => <span className="font-mono text-xs text-emerald-600 dark:text-emerald-400">{formatPW(evt.validator_share)}</span>
    },
    {
      key: "treasury",
      header: "To Treasury (20%)",
      render: (evt: FeeEvent) => <span className="font-mono text-xs text-blue-600 dark:text-blue-400">{formatPW(evt.treasury_share)}</span>
    },
    {
      key: "burn",
      header: "Burned (10%)",
      render: (evt: FeeEvent) => <span className="font-mono text-xs text-destructive">{formatPW(evt.burn_share)}</span>
    }
  ]

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4">
        <div>
          <h1 className="text-3xl font-display font-bold tracking-tight mb-2">Fee Distribution</h1>
          <p className="text-muted-foreground">Transaction fees on PrimeWave are distributed among validators, treasury, and a burn address.</p>
        </div>

        <Card className="bg-card border-none shadow-none mb-2 overflow-visible">
          <CardContent className="p-0">
            <div className="flex h-6 rounded-full overflow-hidden w-full mb-2">
              <div className="bg-emerald-500 h-full w-[70%]" title="Validators 70%"></div>
              <div className="bg-blue-500 h-full w-[20%]" title="Treasury 20%"></div>
              <div className="bg-red-500 h-full w-[10%]" title="Burn 10%"></div>
            </div>
            <div className="flex justify-between text-xs text-muted-foreground font-medium px-1">
              <span className="text-emerald-600 dark:text-emerald-400">Validators (70%)</span>
              <span className="text-blue-600 dark:text-blue-400 -ml-16">Treasury (20%)</span>
              <span className="text-red-600 dark:text-red-400">Burn (10%)</span>
            </div>
          </CardContent>
        </Card>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-2">
          <MetricCard 
            title="Total Distributed"
            value={stats ? formatPW(stats.fees.totalDistributed) : "-"}
            icon={<Coins className="h-5 w-5" />}
          />
          <MetricCard 
            title="To Validators"
            value={stats ? formatPW(stats.fees.totalToValidators) : "-"}
          />
          <MetricCard 
            title="To Treasury"
            value={feesRes?.summary ? formatPW(feesRes.summary.total_treasury) : "-"}
            icon={<Briefcase className="h-5 w-5" />}
          />
          <MetricCard 
            title="Burned"
            value={feesRes?.summary ? formatPW(feesRes.summary.total_burn) : "-"}
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
          data={feesRes?.events}
          isLoading={isLoading}
          keyExtractor={(evt) => `${evt.tx_hash}-${evt.id}`}
          className="border-0 shadow-none"
        />
      </div>
    </div>
  )
}
