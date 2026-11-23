import { useEffect } from "react"
import { useParams } from "wouter"
import { FileCode, Activity, ArrowRightLeft, ArrowUpRight, ArrowDownRight, Award, Coins } from "lucide-react"
import { useAddress, useAddressTransactions, useStakingByAddress, useRewardsByAddress } from "@/lib/api"
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
import { StatusBadge } from "@/components/pwcscan/status-badge"
import { AddressDisplay } from "@/components/pwcscan/address-display"
import { Transaction, StakingPosition, RewardEvent } from "@/lib/api"
import { useCursorPagination } from "@/hooks/use-cursor-pagination"

export default function AddressDetail() {
  const { address } = useParams()
  const { data: addrRes, isLoading, error, refetch } = useAddress(address || "")

  const txPagination = useCursorPagination<string>()
  const txCursor = txPagination.cursor
  const { data: txsRes, isLoading: txsLoading } = useAddressTransactions(address || "", { limit: 20, cursor: txCursor })

  const rewardsPagination = useCursorPagination<number>()
  const rewardsCursor = rewardsPagination.cursor
  const { data: rewardsRes, isLoading: rewardsLoading } = useRewardsByAddress(address || "", { limit: 20, cursor: rewardsCursor })

  const { data: stakingRes, isLoading: stakingLoading } = useStakingByAddress(address || "")

  useEffect(() => {
    txPagination.reset()
    rewardsPagination.reset()
  }, [address, txPagination.reset, rewardsPagination.reset])

  if (error) return <ErrorState onRetry={refetch} />
  if (isLoading) return <Skeleton className="h-[400px] w-full rounded-xl" />

  const addr = addrRes
  if (!addr) return <EmptyState type="not-found" title="Address not found" description={`Address ${address} has no history on this network.`} />

  const txColumns = [
    {
      key: "hash",
      header: "Tx Hash",
      render: (tx: Transaction) => (
        <div className="flex items-center gap-2">
          {tx.status === 1 ? (
            <StatusBadge status="success" label="" className="w-2 h-2 p-0 rounded-full" />
          ) : (
            <StatusBadge status="failed" label="" className="w-2 h-2 p-0 rounded-full" />
          )}
          <NetworkLink href={`/tx/${tx.hash}`} className="font-mono text-primary hover:underline">
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
      key: "direction",
      header: "Type",
      render: (tx: Transaction) => {
        const isOut = tx.from_address.toLowerCase() === address?.toLowerCase();
        return isOut ? (
          <Badge variant="outline" className="bg-amber-500/10 text-amber-700 dark:text-amber-400 border-amber-500/20 gap-1 rounded-sm px-1.5 py-0">
            <ArrowUpRight className="h-3 w-3" /> OUT
          </Badge>
        ) : (
          <Badge variant="outline" className="bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border-emerald-500/20 gap-1 rounded-sm px-1.5 py-0">
            <ArrowDownRight className="h-3 w-3" /> IN
          </Badge>
        )
      }
    },
    {
      key: "to_from",
      header: "From / To",
      render: (tx: Transaction) => {
        const isOut = tx.from_address.toLowerCase() === address?.toLowerCase();
        if (isOut) {
          return tx.to_address ? <AddressDisplay address={tx.to_address} /> : <span className="text-xs">Contract Creation</span>
        }
        return <AddressDisplay address={tx.from_address} />
      }
    },
    {
      key: "value",
      header: "Value",
      render: (tx: Transaction) => <span className="font-mono text-xs">{formatPW(tx.value)}</span>
    }
  ]

  const rewardColumns = [
    {
      key: "tx",
      header: "Tx Hash",
      render: (evt: RewardEvent) => (
        <NetworkLink href={`/tx/${evt.tx_hash}`} className="font-mono text-primary hover:underline">
          {formatHash(evt.tx_hash)}
        </NetworkLink>
      )
    },
    {
      key: "block",
      header: "Block",
      render: (evt: RewardEvent) => (
        <NetworkLink href={`/blocks/${evt.block_number}`} className="text-primary hover:underline">
          {evt.block_number}
        </NetworkLink>
      )
    },
    {
      key: "amount",
      header: "Amount",
      render: (evt: RewardEvent) => <span className="font-mono text-xs font-medium text-emerald-600 dark:text-emerald-400">+{evt.amount ? formatPW(evt.amount) : '0 PW'}</span>
    }
  ]

  const stakingColumns = [
    {
      key: "val",
      header: "Validator",
      render: (pos: StakingPosition) => (
        <NetworkLink href={`/validator/${pos.validation_id}`} className="font-mono text-primary hover:underline">
          {formatHash(pos.validation_id)}
        </NetworkLink>
      )
    },
    {
      key: "amount",
      header: "Stake Amount",
      render: (pos: StakingPosition) => <span className="font-mono text-xs font-semibold">{formatPW(pos.amount)}</span>
    },
    {
      key: "status",
      header: "Status",
      render: (pos: StakingPosition) => pos.is_returned ? (
        <StatusBadge status="inactive" label={`Returned at block ${pos.return_block}`} />
      ) : (
        <StatusBadge status="active" label="Active Stake" />
      )
    }
  ]

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center gap-2">
          {addr.is_contract && (
            <Badge variant="outline" className="bg-primary/10 text-primary border-primary/20 gap-1.5 px-2 py-1">
              <FileCode className="h-3.5 w-3.5" />
              Contract
            </Badge>
          )}
          {addr.protocol_name && (
            <Badge variant="outline" className="bg-indigo-500/10 text-indigo-700 dark:text-indigo-400 border-indigo-500/20 px-2 py-1">
              {addr.protocol_name}
            </Badge>
          )}
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <h1 className="text-2xl sm:text-3xl font-mono font-bold break-all tracking-tight text-foreground bg-card border rounded-lg px-4 py-2 shadow-sm">
            {address}
          </h1>
          <div className="flex items-center gap-1">
            <CopyButton value={address || ""} className="h-9 w-9 bg-card border shadow-sm" />
            <QRModal value={address || ""} title="Address QR Code" />
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Card className="bg-gradient-to-br from-card to-primary/[0.04]">
          <CardContent className="p-6">
            <div className="flex items-center gap-3 mb-2">
              <div className="p-2 bg-primary/10 text-primary rounded-lg"><Coins className="h-5 w-5" /></div>
              <h3 className="font-medium text-muted-foreground">Native PW balance</h3>
            </div>
            <div className="text-2xl font-display font-bold">{addr.native_balance_wei == null ? 'Unavailable' : formatPW(addr.native_balance_wei)}</div>
            <div className="mt-2 text-xs text-muted-foreground">
              {addr.native_balance_wei == null ? 'Live balance unavailable' : 'Reported by the configured indexer'}
            </div>
          </CardContent>
        </Card>
        <Card className="bg-gradient-to-br from-card to-muted/20">
          <CardContent className="p-6">
            <div className="flex items-center gap-3 mb-2">
              <div className="p-2 bg-primary/10 text-primary rounded-lg">
                <ArrowRightLeft className="h-5 w-5" />
              </div>
              <h3 className="font-medium text-muted-foreground">Transactions</h3>
            </div>
            <div className="text-3xl font-display font-bold">{formatNumber(addr.tx_count)}</div>
            <div className="flex gap-4 mt-2 text-sm text-muted-foreground">
              <span className="flex items-center gap-1"><ArrowUpRight className="h-3 w-3" /> {formatNumber(addr.sent_count)} sent</span>
              <span className="flex items-center gap-1"><ArrowDownRight className="h-3 w-3" /> {formatNumber(addr.received_count)} rec</span>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center gap-3 mb-2">
              <div className="p-2 bg-muted text-muted-foreground rounded-lg">
                <Activity className="h-5 w-5" />
              </div>
              <h3 className="font-medium text-muted-foreground">First Seen</h3>
            </div>
            <div className="text-xl font-semibold mb-1">Block <NetworkLink href={`/blocks/${addr.first_seen_block}`} className="text-primary hover:underline">{addr.first_seen_block}</NetworkLink></div>
            {addr.creation_tx && (
              <div className="text-xs text-muted-foreground truncate">
                Created in: <NetworkLink href={`/tx/${addr.creation_tx}`} className="hover:underline">{formatHash(addr.creation_tx)}</NetworkLink>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center gap-3 mb-2">
              <div className="p-2 bg-muted text-muted-foreground rounded-lg">
                <Activity className="h-5 w-5" />
              </div>
              <h3 className="font-medium text-muted-foreground">Last Active</h3>
            </div>
            <div className="text-xl font-semibold mb-1">Block <NetworkLink href={`/blocks/${addr.last_seen_block}`} className="text-primary hover:underline">{addr.last_seen_block}</NetworkLink></div>
          </CardContent>
        </Card>
      </div>

      <Tabs defaultValue="transactions" className="w-full">
        <TabsList className="mb-4">
          <TabsTrigger value="transactions">Transactions</TabsTrigger>
          <TabsTrigger value="staking">Staking Positions</TabsTrigger>
          <TabsTrigger value="rewards">Rewards</TabsTrigger>
        </TabsList>

        <TabsContent value="transactions">
          <Card>
            <CardHeader className="py-4 border-b">
              <CardTitle className="text-lg">Transaction History</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <DataTable
                columns={txColumns}
                data={txsRes?.data}
                isLoading={txsLoading}
                keyExtractor={(tx) => tx.hash}
                className="border-0 shadow-none rounded-none"
                pagination={{
                  hasPrev: txPagination.hasPrevious,
                  hasNext: !!txsRes?.pagination?.nextCursor,
                  onPrev: txPagination.goPrevious,
                  onNext: () => txPagination.goNext(txsRes?.pagination?.nextCursor)
                }}
              />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="staking">
          <Card>
            <CardHeader className="py-4 border-b">
              <CardTitle className="text-lg">Staking Positions</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <DataTable
                columns={stakingColumns}
                data={stakingRes?.positions}
                isLoading={stakingLoading}
                keyExtractor={(pos) => `${pos.validation_id}-${pos.stake_block}`}
                className="border-0 shadow-none rounded-none"
                emptyTitle="No stakes found"
                emptyDescription="This address has not staked any PW."
              />
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="rewards">
          <Card>
            <CardHeader className="py-4 border-b">
              <CardTitle className="text-lg">Reward History</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <DataTable
                columns={rewardColumns}
                data={rewardsRes?.data.events}
                isLoading={rewardsLoading}
                keyExtractor={(evt) => evt.tx_hash + evt.id}
                className="border-0 shadow-none rounded-none"
                emptyTitle="No rewards claimed"
                emptyDescription="This address has not claimed any rewards."
                pagination={{
                  hasPrev: rewardsPagination.hasPrevious,
                  hasNext: !!rewardsRes?.pagination?.nextCursor,
                  onPrev: rewardsPagination.goPrevious,
                  onNext: () => rewardsPagination.goNext(rewardsRes?.pagination?.nextCursor)
                }}
              />
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  )
}
