import { NetworkLink } from "@/lib/network"
import { useBlocks } from "@/lib/api"
import { useCursorPagination } from "@/hooks/use-cursor-pagination"
import { formatNumber, formatAge, formatGasPercent } from "@/lib/format"
import { DataTable } from "@/components/pwcscan/data-table"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { GasBar } from "@/components/pwcscan/gas-bar"
import { ErrorState } from "@/components/pwcscan/error-state"
import { Block } from "@/lib/api"

export default function Blocks() {
  const { cursor, hasPrevious, goPrevious, goNext } = useCursorPagination()
  const { data: res, isLoading, error, refetch } = useBlocks({ limit: 25, cursor })

  if (error) {
    return <ErrorState onRetry={refetch} />
  }

  const columns = [
    {
      key: "number",
      header: "Block",
      render: (b: Block) => (
        <NetworkLink href={`/blocks/${b.number}`} className="font-medium text-primary hover:underline">
          {b.number}
        </NetworkLink>
      )
    },
    {
      key: "age",
      header: "Age",
      render: (b: Block) => <span className="text-muted-foreground">{formatAge(b.timestamp_unix)}</span>
    },
    {
      key: "txns",
      header: "Txns",
      render: (b: Block) => <span>{b.transaction_count}</span>
    },
    {
      key: "miner",
      header: "Miner",
      render: (b: Block) => b.coinbase ? <AddressDisplay address={b.coinbase} /> : <span>-</span>
    },
    {
      key: "gas",
      header: "Gas Used",
      render: (b: Block) => (
        <div className="flex flex-col gap-1 w-32">
          <div className="text-xs">{formatNumber(b.gas_used)}</div>
          <GasBar used={b.gas_used} limit={b.gas_limit} />
        </div>
      )
    },
    {
      key: "limit",
      header: "Gas Limit",
      render: (b: Block) => <span className="text-xs">{formatNumber(b.gas_limit)}</span>
    }
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-display font-bold tracking-tight mb-2">Blocks</h1>
        <p className="text-muted-foreground">List of all blocks mined on the PrimeWave network.</p>
      </div>

      <DataTable 
        columns={columns}
        data={res?.data}
        isLoading={isLoading}
        keyExtractor={(b) => b.hash}
        pagination={{
          hasPrev: hasPrevious,
          hasNext: !!res?.pagination?.nextCursor,
          onPrev: goPrevious,
          onNext: () => goNext(res?.pagination?.nextCursor),
          label: "Showing latest blocks"
        }}
      />
    </div>
  )
}
