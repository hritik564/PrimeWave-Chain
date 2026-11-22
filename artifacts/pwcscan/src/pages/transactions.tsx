import { NetworkLink } from "@/lib/network"
import { useTransactions } from "@/lib/api"
import { useCursorPagination } from "@/hooks/use-cursor-pagination"
import { formatAge, formatPW, formatHash } from "@/lib/format"
import { DataTable } from "@/components/pwcscan/data-table"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { StatusBadge } from "@/components/pwcscan/status-badge"
import { ErrorState } from "@/components/pwcscan/error-state"
import { Transaction } from "@/lib/api"

export default function Transactions() {
  const { cursor, hasPrevious, goPrevious, goNext } = useCursorPagination<string>()
  const { data: res, isLoading, error, refetch } = useTransactions({ limit: 25, cursor })

  if (error) return <ErrorState onRetry={refetch} />

  const columns = [
    {
      key: "hash",
      header: "Tx Hash",
      render: (tx: Transaction) => (
        <div className="flex items-center gap-2">
          {tx.status === 1 ? (
            <StatusBadge status="success" label="" className="w-2 h-2 p-0 rounded-full" />
          ) : tx.status === 0 ? (
            <StatusBadge status="failed" label="" className="w-2 h-2 p-0 rounded-full" />
          ) : (
            <StatusBadge status="pending" label="Receipt unavailable" className="text-[10px]" />
          )}
          <NetworkLink href={`/tx/${tx.hash}`} className="font-mono font-medium text-primary hover:underline">
            {formatHash(tx.hash)}
          </NetworkLink>
        </div>
      )
    },
    {
      key: "block",
      header: "Block",
      render: (tx: Transaction) => (
          <NetworkLink href={`/blocks/${tx.block_number}`} className="text-primary hover:underline">
          {tx.block_number}
          </NetworkLink>
      )
    },
    {
      key: "age",
      header: "Age",
      render: (tx: Transaction) => tx.timestamp_unix === undefined || tx.timestamp_unix === null
        ? <span className="text-muted-foreground">Unavailable</span>
        : <span className="text-muted-foreground">{formatAge(tx.timestamp_unix)}</span>
    },
    {
      key: "from",
      header: "From",
      render: (tx: Transaction) => <AddressDisplay address={tx.from_address} />
    },
    {
      key: "to",
      header: "To",
      render: (tx: Transaction) => tx.to_address ? (
        <AddressDisplay address={tx.to_address} />
      ) : (
        <StatusBadge status="active" label="Contract Creation" className="text-[10px] px-1.5 py-0.5" />
      )
    },
    {
      key: "value",
      header: "Value",
      render: (tx: Transaction) => <span className="font-mono text-xs font-medium">{formatPW(tx.value)}</span>
    },
    {
      key: "fee",
      header: "Txn Fee",
      render: (tx: Transaction) => (
        <span className="text-xs text-muted-foreground">
          {tx.transaction_fee === null ? "Unavailable" : formatPW(tx.transaction_fee)}
        </span>
      )
    }
  ]

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-display font-bold tracking-tight mb-2">Transactions</h1>
        <p className="text-muted-foreground">List of all transactions on the PrimeWave network.</p>
      </div>

      <DataTable 
        columns={columns}
        data={res?.data}
        isLoading={isLoading}
        keyExtractor={(tx) => tx.hash}
        pagination={{
          hasPrev: hasPrevious,
          hasNext: !!res?.pagination?.nextCursor,
          onPrev: goPrevious,
          onNext: () => goNext(res?.pagination?.nextCursor),
          label: "Showing latest transactions"
        }}
      />
    </div>
  )
}
