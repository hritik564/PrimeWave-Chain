import { useParams } from "wouter";
import { FileCode, BadgeCheck, CircleHelp } from "lucide-react";
import { useContract } from "@/lib/api";
import { NetworkLink } from "@/lib/network";
import { formatHash, formatNumber } from "@/lib/format";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { CopyButton } from "@/components/pwcscan/copy-button";
import { HashDisplay } from "@/components/pwcscan/hash-display";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/pwcscan/error-state";
import { EmptyState } from "@/components/pwcscan/empty-state";

export default function ContractDetail() {
  const { address } = useParams();
  const {
    data: contract,
    isLoading,
    error,
    refetch,
  } = useContract(address ?? "");

  if (error) return <ErrorState onRetry={refetch} />;
  if (isLoading) return <Skeleton className="h-[480px] w-full rounded-xl" />;
  if (!contract) {
    return (
      <EmptyState
        type="not-found"
        title="Contract not found"
        description={`No indexed contract record exists for ${address ?? "this address"}.`}
      />
    );
  }

  return (
    <div className="space-y-6">
      <header className="space-y-3">
        <div className="flex flex-wrap items-center gap-2">
          <Badge variant="outline" className="gap-1.5">
            <FileCode className="h-3.5 w-3.5" />
            Contract
          </Badge>
          {contract.is_known_protocol && contract.protocol_name && (
            <Badge variant="outline">{contract.protocol_name}</Badge>
          )}
          {contract.is_verified ? (
            <Badge variant="outline" className="gap-1 border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300">
              <BadgeCheck className="h-3.5 w-3.5" />
              Registry marked verified
            </Badge>
          ) : (
            <Badge variant="outline" className="gap-1 text-muted-foreground">
              <CircleHelp className="h-3.5 w-3.5" />
              Unverified
            </Badge>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="break-all rounded-lg border bg-card px-4 py-2 font-mono text-xl font-bold shadow-sm sm:text-2xl">
            {address}
          </h1>
          <CopyButton value={address ?? ""} className="h-9 w-9 bg-card border shadow-sm" />
        </div>
      </header>

      <Card>
        <CardHeader className="border-b bg-muted/20">
          <CardTitle>Contract Overview</CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          <dl className="divide-y">
            <div className="grid grid-cols-1 gap-2 p-4 sm:grid-cols-4 sm:p-6">
              <dt className="text-sm font-medium text-muted-foreground">Transactions</dt>
              <dd className="text-sm sm:col-span-3">{formatNumber(contract.tx_count)}</dd>
            </div>
            <div className="grid grid-cols-1 gap-2 p-4 sm:grid-cols-4 sm:p-6">
              <dt className="text-sm font-medium text-muted-foreground">Creation block</dt>
              <dd className="text-sm sm:col-span-3">
                {contract.creation_block === null
                  ? "Unavailable"
                  : <NetworkLink href={`/blocks/${contract.creation_block}`} className="text-primary hover:underline">
                      {formatNumber(contract.creation_block)}
                    </NetworkLink>}
              </dd>
            </div>
            <div className="grid grid-cols-1 gap-2 p-4 sm:grid-cols-4 sm:p-6">
              <dt className="text-sm font-medium text-muted-foreground">Creation transaction</dt>
              <dd className="break-all text-sm sm:col-span-3">
                {contract.creation_tx
                  ? <NetworkLink href={`/tx/${contract.creation_tx}`} className="text-primary hover:underline">
                      <HashDisplay hash={contract.creation_tx} />
                    </NetworkLink>
                  : "Unavailable"}
              </dd>
            </div>
          </dl>
        </CardContent>
      </Card>

      <section className="space-y-3">
        <div>
          <h2 className="text-xl font-semibold">Recent decoded events</h2>
          <p className="text-sm text-muted-foreground">Latest indexed events for this contract.</p>
        </div>
        {contract.recentEvents?.length ? (
          <div className="space-y-3">
            {contract.recentEvents.map((event, index) => (
              <Card key={`${event.tx_hash ?? "event"}-${index}`}>
                <CardContent className="flex flex-col gap-2 p-4 sm:flex-row sm:items-center sm:justify-between">
                  <div className="min-w-0">
                    <p className="font-medium">{event.event_name}</p>
                    <p className="break-all font-mono text-xs text-muted-foreground">
                      {event.event_signature}
                    </p>
                  </div>
                  <div className="flex shrink-0 flex-col gap-1 text-sm sm:items-end">
                    {event.block_number !== undefined && (
                      <NetworkLink href={`/blocks/${event.block_number}`} className="text-primary hover:underline">
                        Block {formatNumber(event.block_number)}
                      </NetworkLink>
                    )}
                    {event.tx_hash && (
                      <NetworkLink href={`/tx/${event.tx_hash}`} className="font-mono text-primary hover:underline">
                        {formatHash(event.tx_hash)}
                      </NetworkLink>
                    )}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        ) : (
          <EmptyState title="No decoded events found" description="The indexer has no decoded events for this contract." />
        )}
        <p className="text-xs text-muted-foreground">
          The current API does not serve source code, ABI files, or read-only contract calls.
        </p>
      </section>
    </div>
  );
}
