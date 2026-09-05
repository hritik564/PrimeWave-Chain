import { useState } from "react"
import { useParams } from "wouter"
import { Server, Activity, ArrowRightLeft } from "lucide-react"
import { useValidator, useValidatorEvents } from "@/lib/api"
import { NetworkLink } from "@/lib/network"
import { formatPW, formatAge, formatHash, formatNumber } from "@/lib/format"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Badge } from "@/components/ui/badge"
import { CopyButton } from "@/components/pwcscan/copy-button"
import { QRModal } from "@/components/pwcscan/qr-modal"
import { DataTable } from "@/components/pwcscan/data-table"
import { Skeleton } from "@/components/ui/skeleton"
import { ErrorState } from "@/components/pwcscan/error-state"
import { EmptyState } from "@/components/pwcscan/empty-state"
import { ValidatorStatusBadge } from "@/components/pwcscan/status-badge"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { ValidatorEvent } from "@/lib/api"
import { EventLogItem } from "@/components/pwcscan/event-log-item"
import { Button } from "@/components/ui/button"

export default function ValidatorDetail() {
  const { id } = useParams()
  const { data: val, isLoading, error, refetch } = useValidator(id || "")

  const [cursor, setCursor] = useState<number | undefined>(undefined)
  const { data: eventsRes, isLoading: eventsLoading } = useValidatorEvents(id || "", { limit: 20, cursor })

  if (error) return <ErrorState onRetry={refetch} />
  if (isLoading) return <Skeleton className="h-[400px] w-full rounded-xl" />
  if (!val) return <EmptyState type="not-found" title="Validator not found" description={`Validator ${id} could not be found.`} />

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-2">
          <ValidatorStatusBadge status={val.status} className="text-sm px-3 py-1" />
          {val.is_active_in_vault && (
            <Badge variant="outline" className="bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border-emerald-500/20 px-3 py-1">
              Active in Vault
            </Badge>
          )}
        </div>
        
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-3 bg-card border rounded-lg px-4 py-2 shadow-sm">
            <Server className="h-6 w-6 text-muted-foreground" />
            <h1 className="text-xl sm:text-2xl font-mono font-bold break-all tracking-tight text-foreground">
              {val.validation_id}
            </h1>
          </div>
          <div className="flex items-center gap-1">
            <CopyButton value={val.validation_id} className="h-9 w-9 bg-card border shadow-sm" />
            <QRModal value={val.validation_id} title="Validator ID" />
          </div>
        </div>
      </div>

      <Tabs defaultValue="overview" className="w-full">
        <TabsList className="mb-4">
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="events">Events</TabsTrigger>
        </TabsList>
        
        <TabsContent value="overview">
          <Card>
            <CardHeader className="border-b bg-muted/20 pb-4">
              <CardTitle>Validator Info</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <dl className="divide-y">
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Reward Recipient:</dt>
                  <dd className="text-sm sm:col-span-3">
                    <AddressDisplay address={val.reward_recipient} showCopy />
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Uptime:</dt>
                  <dd className="text-sm sm:col-span-3 flex items-center gap-2">
                    <span className={val.uptime_bips > 9900 ? "text-emerald-600 font-semibold" : "text-amber-600 font-semibold"}>
                      {(val.uptime_bips / 100).toFixed(2)}%
                    </span>
                    <span className="text-xs text-muted-foreground">({val.uptime_bips} bips)</span>
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors bg-muted/5">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">ACP99 Weight:</dt>
                  <dd className="text-sm sm:col-span-3 font-mono">
                    {formatPW(val.acp99_weight)}
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Vault Base Weight:</dt>
                  <dd className="text-sm sm:col-span-3 font-mono">
                    {formatPW(val.vault_base_weight)}
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors bg-muted/5">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Total Fees Claimed:</dt>
                  <dd className="text-sm sm:col-span-3 font-mono font-semibold text-primary">
                    {formatPW(val.total_fees_claimed)}
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">First Seen Block:</dt>
                  <dd className="text-sm sm:col-span-3">
                    <NetworkLink href={`/blocks/${val.first_seen_block}`} className="text-primary hover:underline">
                      {val.first_seen_block}
                    </NetworkLink>
                  </dd>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-4 gap-2 p-4 sm:p-6 hover:bg-muted/10 transition-colors">
                  <dt className="text-sm font-medium text-muted-foreground sm:col-span-1">Last Updated Block:</dt>
                  <dd className="text-sm sm:col-span-3">
                    <NetworkLink href={`/blocks/${val.last_updated_block}`} className="text-primary hover:underline">
                      {val.last_updated_block}
                    </NetworkLink>
                  </dd>
                </div>
              </dl>
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="events">
          <Card>
            <CardHeader className="py-4 border-b">
              <CardTitle className="text-lg">Validator Events</CardTitle>
            </CardHeader>
            <CardContent className="p-4">
              {eventsLoading ? (
                <div className="space-y-4">
                  <Skeleton className="h-16 w-full" />
                  <Skeleton className="h-16 w-full" />
                </div>
              ) : eventsRes?.data && eventsRes.data.length > 0 ? (
                <div className="space-y-4">
                  {eventsRes.data.map((evt) => (
                    <div key={evt.id} className="border rounded-lg overflow-hidden bg-card">
                      <div className="px-4 py-3 bg-muted/20 border-b flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                        <div className="font-semibold text-sm">{evt.event_name}</div>
                        <div className="flex items-center gap-4 text-xs text-muted-foreground">
                          <NetworkLink href={`/blocks/${evt.block_number}`} className="hover:underline">Block {evt.block_number}</NetworkLink>
                          <NetworkLink href={`/tx/${evt.tx_hash}`} className="hover:underline font-mono">{formatHash(evt.tx_hash)}</NetworkLink>
                        </div>
                      </div>
                      <div className="px-4 py-3 font-mono text-xs overflow-x-auto">
                        <pre className="text-foreground">
                          {JSON.stringify(evt.event_data, null, 2)}
                        </pre>
                      </div>
                    </div>
                  ))}
                  
                  {eventsRes.pagination.nextCursor && (
                    <div className="pt-4 flex justify-center border-t mt-4">
                      <Button variant="outline" onClick={() => setCursor(eventsRes.pagination.nextCursor!)}>
                        Load More
                      </Button>
                    </div>
                  )}
                </div>
              ) : (
                <EmptyState title="No events found" description="This validator has no recorded events." />
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
