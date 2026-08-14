import { useParams, Link } from "wouter"
import { CheckCircle2, XCircle } from "lucide-react"
import { useTransaction } from "@/lib/api"
import { formatPW, formatNumber, formatGasPercent } from "@/lib/format"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { HashDisplay } from "@/components/pwcscan/hash-display"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { StatusBadge } from "@/components/pwcscan/status-badge"
import { Skeleton } from "@/components/ui/skeleton"
import { ErrorState } from "@/components/pwcscan/error-state"
import { EmptyState } from "@/components/pwcscan/empty-state"
import { EventLogItem } from "@/components/pwcscan/event-log-item"

export default function TransactionDetail() {
  const { hash } = useParams()
  const { data: tx, isLoading, error, refetch } = useTransaction(hash || "")

  if (error) return <ErrorState onRetry={refetch} />
  if (isLoading) return <Skeleton className="h-[600px] w-full rounded-xl" />
  if (!tx) return <EmptyState type="not-found" title="Transaction not found" description={`Tx ${hash} could not be found.`} />

  const isSuccess = tx.status === 1;

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-2">
        <h1 className="text-3xl font-display font-bold tracking-tight mb-1 flex items-center gap-3">
          Transaction Details
        </h1>
      </div>

      <Tabs defaultValue="overview" className="w-full">
        <TabsList className="mb-4">
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="logs">
            Logs <span className="ml-1.5 bg-muted-foreground/20 text-muted-foreground text-[10px] px-1.5 py-0.5 rounded-full">{tx.decodedEvents?.length || tx.logs?.length || 0}</span>
          </TabsTrigger>
          <TabsTrigger value="raw">Raw Data</TabsTrigger>
        </TabsList>
        
        <TabsContent value="overview">
          <Card>
            <CardHeader className="border-b bg-muted/20 pb-4">
              <CardTitle>Transaction Info</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <dl className="divide-y">
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Transaction Hash:</dt>
                  <dd className="text-sm sm:col-span-3 font-mono break-all flex items-center gap-2">
                    <HashDisplay hash={tx.hash} />
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Status:</dt>
                  <dd className="text-sm sm:col-span-3 flex items-center gap-2">
                    {isSuccess ? (
                      <div className="flex items-center gap-1.5 text-emerald-600 dark:text-emerald-400 bg-emerald-500/10 px-2.5 py-1 rounded-md text-sm font-medium border border-emerald-500/20">
                        <CheckCircle2 className="h-4 w-4" />
                        Success
                      </div>
                    ) : (
                      <div className="flex items-center gap-1.5 text-destructive bg-destructive/10 px-2.5 py-1 rounded-md text-sm font-medium border border-destructive/20">
                        <XCircle className="h-4 w-4" />
                        Failed
                      </div>
                    )}
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Block:</dt>
                  <dd className="text-sm sm:col-span-3 flex items-center gap-2">
                    <Link href={`/blocks/${tx.block_number}`} className="text-primary hover:underline font-medium">
                      {tx.block_number}
                    </Link>
                  </dd>
                </div>
                
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors bg-muted/5">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">From:</dt>
                  <dd className="text-sm sm:col-span-3">
                    <AddressDisplay address={tx.from_address} showCopy />
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors bg-muted/5">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">To:</dt>
                  <dd className="text-sm sm:col-span-3 flex items-center gap-2">
                    {tx.to_address ? (
                      <AddressDisplay address={tx.to_address} showCopy />
                    ) : tx.created_contract ? (
                      <div className="flex items-center gap-2">
                        <span className="text-muted-foreground">Contract Creation:</span>
                        <AddressDisplay address={tx.created_contract} showCopy />
                      </div>
                    ) : (
                      <span>-</span>
                    )}
                  </dd>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Value:</dt>
                  <dd className="text-sm sm:col-span-3 font-mono font-semibold bg-muted/50 inline-block px-3 py-1 rounded-md w-fit">
                    {formatPW(tx.value)}
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Transaction Fee:</dt>
                  <dd className="text-sm sm:col-span-3 font-mono text-muted-foreground">
                    {tx.transaction_fee ? formatPW(tx.transaction_fee) : '-'}
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Gas Price:</dt>
                  <dd className="text-sm sm:col-span-3 text-muted-foreground text-xs font-mono">
                    {tx.gas_price ? formatPW(tx.gas_price) : '-'}
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Gas Usage:</dt>
                  <dd className="text-sm sm:col-span-3 flex items-center gap-2">
                    <span>{formatNumber(tx.receipt_gas_used)}</span>
                    <span className="text-muted-foreground text-xs">/ {formatNumber(tx.gas_limit)}</span>
                    <span className="text-muted-foreground text-xs">({formatGasPercent(tx.receipt_gas_used, tx.gas_limit)})</span>
                  </dd>
                </div>
                
                {tx.input && tx.input !== "0x" && (
                  <div className="grid grid-cols-1 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                    <dt className="text-sm font-medium text-muted-foreground">Input Data:</dt>
                    <dd className="text-sm">
                      <div className="bg-muted p-4 rounded-md font-mono text-xs overflow-x-auto max-h-[200px] overflow-y-auto break-all">
                        {tx.input}
                      </div>
                    </dd>
                  </div>
                )}
              </dl>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="logs">
          <Card>
            <CardHeader>
              <CardTitle>Event Logs</CardTitle>
            </CardHeader>
            <CardContent>
              {tx.decodedEvents && tx.decodedEvents.length > 0 ? (
                <div className="space-y-4">
                  {tx.decodedEvents.map((evt, idx) => (
                    <EventLogItem key={idx} event={evt} logIndex={idx} />
                  ))}
                </div>
              ) : tx.logs && tx.logs.length > 0 ? (
                <div className="space-y-4">
                  {tx.logs.map((log, idx) => (
                    <div key={idx} className="p-4 border rounded-md bg-muted/10 font-mono text-xs break-all">
                      <div className="text-primary mb-2">Log Index: {log.log_index}</div>
                      <div>Contract: {log.contract_address}</div>
                      <div>Topic 0: {log.topic0}</div>
                      {log.topic1 && <div>Topic 1: {log.topic1}</div>}
                      {log.topic2 && <div>Topic 2: {log.topic2}</div>}
                      {log.topic3 && <div>Topic 3: {log.topic3}</div>}
                      {log.data && <div className="mt-2 text-muted-foreground">Data: {log.data}</div>}
                    </div>
                  ))}
                </div>
              ) : (
                <EmptyState title="No logs found" description="This transaction did not emit any event logs." />
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="raw">
          <Card>
            <CardContent className="p-0">
              <pre className="p-6 overflow-auto max-h-[800px] text-xs font-mono bg-muted/20">
                {JSON.stringify(tx, null, 2)}
              </pre>
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
