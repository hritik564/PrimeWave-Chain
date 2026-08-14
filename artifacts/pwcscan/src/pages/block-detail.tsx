import { useParams } from "wouter"
import { useBlock, useTransactions } from "@/lib/api"
import { formatAge, formatTimestamp, formatNumber, formatPW, formatGasPercent } from "@/lib/format"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"
import { HashDisplay } from "@/components/pwcscan/hash-display"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { GasBar } from "@/components/pwcscan/gas-bar"
import { Skeleton } from "@/components/ui/skeleton"
import { ErrorState } from "@/components/pwcscan/error-state"
import { EmptyState } from "@/components/pwcscan/empty-state"

export default function BlockDetail() {
  const { number } = useParams()
  const { data: block, isLoading, error, refetch } = useBlock(number || "")

  if (error) return <ErrorState onRetry={refetch} />
  if (isLoading) return <Skeleton className="h-[400px] w-full rounded-xl" />
  if (!block) return <EmptyState type="not-found" title="Block not found" description={`Block ${number} could not be found.`} />

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-display font-bold tracking-tight mb-1 flex items-center gap-3">
            Block <span className="text-muted-foreground text-2xl">#{block.number}</span>
          </h1>
          <p className="text-muted-foreground text-sm">
            Mined {formatAge(block.timestamp_unix)}
          </p>
        </div>
      </div>

      <Card>
        <CardHeader className="border-b bg-muted/20 pb-4">
          <CardTitle>Overview</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <dl className="divide-y">
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
              <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Timestamp:</dt>
              <dd className="text-sm sm:col-span-3 flex items-center gap-2">
                <span>{formatAge(block.timestamp_unix)}</span>
                <span className="text-muted-foreground">({formatTimestamp(block.timestamp_unix, false)})</span>
              </dd>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
              <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Transactions:</dt>
              <dd className="text-sm sm:col-span-3">
                <span className="font-semibold px-2 py-1 bg-primary/10 text-primary rounded-md">
                  {block.transaction_count}
                </span> transactions in this block
              </dd>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
              <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Fee Recipient (Miner):</dt>
              <dd className="text-sm sm:col-span-3">
                {block.coinbase ? <AddressDisplay address={block.coinbase} /> : <span>-</span>}
              </dd>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
              <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Gas Used:</dt>
              <dd className="text-sm sm:col-span-3 flex flex-col sm:flex-row gap-4 sm:items-center">
                <div className="flex items-center gap-2">
                  <span>{formatNumber(block.gas_used)}</span>
                  <span className="text-muted-foreground">({formatGasPercent(block.gas_used, block.gas_limit)})</span>
                </div>
                <GasBar used={block.gas_used} limit={block.gas_limit} className="w-full sm:max-w-[200px]" />
              </dd>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
              <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Gas Limit:</dt>
              <dd className="text-sm sm:col-span-3">{formatNumber(block.gas_limit)}</dd>
            </div>
            {block.base_fee_per_gas && (
              <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Base Fee Per Gas:</dt>
                <dd className="text-sm sm:col-span-3 font-mono">
                  {formatPW(block.base_fee_per_gas)}
                </dd>
              </div>
            )}
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
              <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Hash:</dt>
              <dd className="text-sm sm:col-span-3 break-all font-mono">
                <HashDisplay hash={block.hash} />
              </dd>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
              <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Parent Hash:</dt>
              <dd className="text-sm sm:col-span-3 break-all font-mono text-primary hover:underline cursor-pointer">
                <HashDisplay hash={block.parent_hash} />
              </dd>
            </div>
            {block.state_root && (
              <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">State Root:</dt>
                <dd className="text-sm sm:col-span-3 break-all font-mono">{block.state_root}</dd>
              </div>
            )}
          </dl>
        </CardContent>
      </Card>
    </div>
  )
}
