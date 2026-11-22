import { useState } from "react"
import { NetworkLink } from "@/lib/network"
import { FileCode, Search, BadgeCheck, CircleHelp } from "lucide-react"
import { useContracts } from "@/lib/api"
import { useCursorPagination } from "@/hooks/use-cursor-pagination"
import { DataTable } from "@/components/pwcscan/data-table"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { Badge } from "@/components/ui/badge"
import { ErrorState } from "@/components/pwcscan/error-state"
import { Contract } from "@/lib/api"
import { Button } from "@/components/ui/button"

export default function Contracts() {
  const { cursor, hasPrevious, goPrevious, goNext, reset } = useCursorPagination<string>()
  const [knownOnly, setKnownOnly] = useState(true)
  
  const { data: res, isLoading, error, refetch } = useContracts({ limit: 25, cursor, known_only: knownOnly })

  if (error) return <ErrorState onRetry={refetch} />

  const columns = [
    {
      key: "address",
      header: "Contract Address",
      render: (c: Contract) => (
        <div className="flex items-center gap-2">
          <FileCode className="h-4 w-4 text-muted-foreground" />
          <NetworkLink href={`/contract/${c.address}`} className="font-mono font-medium text-primary hover:underline">
            <AddressDisplay address={c.address} showCopy={false} />
          </NetworkLink>
        </div>
      )
    },
    {
      key: "protocol",
      header: "Protocol / Name",
      render: (c: Contract) => c.protocol_name ? (
        <Badge variant="outline" className="bg-indigo-500/10 text-indigo-700 dark:text-indigo-400 border-indigo-500/20">
          {c.protocol_name}
        </Badge>
      ) : (
        <span className="text-muted-foreground text-xs italic">Unknown</span>
      )
    },
    {
      key: "verification",
      header: "Source Status",
      render: (c: Contract) => c.is_verified ? (
        <Badge variant="outline" className="gap-1 border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300">
          <BadgeCheck className="h-3.5 w-3.5" />
          Verified
        </Badge>
      ) : (
        <span className="inline-flex items-center gap-1 text-xs text-muted-foreground">
          <CircleHelp className="h-3.5 w-3.5" />
          Unverified
        </span>
      )
    },
    {
      key: "txs",
      header: "Tx Count",
      render: (c: Contract) => <span>{c.tx_count}</span>
    },
    {
      key: "creation",
      header: "Creation",
      render: (c: Contract) => c.creation_block !== null ? (
        <div className="flex flex-col">
          <NetworkLink href={`/blocks/${c.creation_block}`} className="text-primary hover:underline text-sm">
            Block {c.creation_block}
          </NetworkLink>
        </div>
      ) : <span>Unavailable</span>
    }
  ]

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-display font-bold tracking-tight mb-2">Contracts</h1>
          <p className="text-muted-foreground">Directory of smart contracts deployed on PrimeWave.</p>
        </div>
        <div className="flex bg-muted p-1 rounded-lg w-fit">
          <Button 
            variant="ghost" 
            size="sm"
            className={knownOnly ? "bg-background shadow-sm" : ""}
          onClick={() => { setKnownOnly(true); reset() }}
          >
            Known Protocols
          </Button>
          <Button 
            variant="ghost" 
            size="sm"
            className={!knownOnly ? "bg-background shadow-sm" : ""}
          onClick={() => { setKnownOnly(false); reset() }}
          >
            All Contracts
          </Button>
        </div>
      </div>

      <p className="text-sm text-muted-foreground">
        The indexer provides a contract verification flag and activity metadata. Source code, ABI, and read-only contract calls are not currently served.
      </p>

      <DataTable 
        columns={columns}
        data={res?.data}
        isLoading={isLoading}
        keyExtractor={(c) => c.address}
        pagination={{
          hasPrev: hasPrevious,
          hasNext: !!res?.pagination?.nextCursor,
          onPrev: goPrevious,
          onNext: () => goNext(res?.pagination?.nextCursor),
        }}
      />
    </div>
  )
}
