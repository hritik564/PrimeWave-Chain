import * as React from "react"
import { NavBar } from "./NavBar"
import { useNetwork } from "@/lib/network"
import { useStats } from "@/lib/api"

function MainnetStatusBanner() {
  const { network } = useNetwork()
  const { data: stats, isFetching, error } = useStats()
  if (network.id !== 'mainnet') return null
  const status = network.status !== 'configured'
    ? 'NOT LAUNCHED'
    : error ? 'UNAVAILABLE'
      : stats ? (stats.network.isSynced ? 'LIVE' : 'SYNCING')
        : isFetching ? 'CONNECTING' : 'UNAVAILABLE'
  return <div className="mx-auto w-full max-w-[1320px] px-4 pt-3 sm:px-6" role="status" aria-live="polite" data-testid="mainnet-status">
    <div className="flex flex-col gap-1 rounded-lg border bg-card/70 px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
      <span className="text-sm font-semibold">PrimeWave Mainnet · {status}</span>
      <span className="text-xs text-muted-foreground">{status === 'LIVE' ? 'Identity verified; indexer reports synchronized data.' : status === 'SYNCING' ? 'Identity verified; indexer is catching up.' : 'Unverified or unavailable chain data is hidden.'}</span>
    </div>
  </div>
}

export function AppLayout({ children }: { children: React.ReactNode }) {
  const { network } = useNetwork()
  return (
    <div className="min-h-[100dvh] flex flex-col bg-background text-foreground selection:bg-primary/15">
      <NavBar />
      <MainnetStatusBanner />
      <main className="mx-auto w-full max-w-[1320px] flex-1 px-4 py-7 sm:px-6 sm:py-9">
        {children}
      </main>
      <footer className="mt-auto border-t bg-card/70 py-6">
        <div className="mx-auto flex w-full max-w-[1320px] flex-col items-center justify-between gap-3 px-4 text-xs text-muted-foreground sm:flex-row sm:px-6">
          <div className="flex items-center gap-2">
            <div className="grid h-6 w-6 place-items-center rounded-md bg-primary/10">
              <span className="font-display text-[10px] font-bold text-primary">PW</span>
            </div>
            <span>© {new Date().getFullYear()} PWCScan · PrimeWave {network.label} explorer</span>
          </div>
          <div className="flex items-center gap-4">
            <span>Chain ID {network.chainId ?? "pending"}</span>
            <span className="h-1 w-1 rounded-full bg-muted-foreground/50" />
            <span>Native asset {network.nativeCurrency.symbol}</span>
          </div>
        </div>
      </footer>
    </div>
  )
}
