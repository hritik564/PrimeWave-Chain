import * as React from "react"
import { NavBar } from "./NavBar"
import { useNetwork } from "@/lib/network"
import { useStats } from "@/lib/api"

function MainnetStatusBanner() {
  const { network } = useNetwork()
  const { data: stats, isFetching, error } = useStats()

  if (network.id !== "mainnet") return null

  let status = "CONNECTING"
  let detail = "Checking the configured Mainnet endpoint and genesis identity."

  if (network.status !== "configured") {
    status = "NOT LAUNCHED"
    detail = "No verified Mainnet launch configuration is available. Mainnet data remains disabled."
  } else if (error) {
    status = "UNAVAILABLE"
    detail = "The indexer could not verify the configured Chain ID and genesis identity."
  } else if (
    stats &&
    stats.network.latestIndexed > stats.network.chainHead
  ) {
    status = "DEGRADED"
    detail = "Indexer height is ahead of the reported chain head; data is not considered reliable."
  } else if (stats) {
    status = stats.network.isSynced ? "LIVE" : "SYNCING"
    detail = stats.network.isSynced
      ? "Network identity is verified and the indexer reports synchronized data."
      : "Network identity is verified; the indexer is still catching up."
  } else if (!isFetching) {
    status = "UNAVAILABLE"
    detail = "No verified Mainnet status is available."
  }

  const statusColor =
    status === "LIVE"
      ? "text-emerald-700 dark:text-emerald-300"
      : status === "NOT LAUNCHED" || status === "UNAVAILABLE" || status === "DEGRADED"
        ? "text-amber-700 dark:text-amber-300"
        : "text-muted-foreground"

  return (
    <div
      className="container mx-auto px-4 pt-4"
      role="status"
      aria-live="polite"
      data-testid="mainnet-status"
    >
      <div className="flex flex-col gap-1 rounded-lg border bg-card/70 px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-2">
          <span className={`h-2 w-2 rounded-full bg-current ${statusColor}`} aria-hidden="true" />
          <span className="text-sm font-semibold">PrimeWave Mainnet</span>
          <span className={`text-xs font-bold tracking-wide ${statusColor}`}>{status}</span>
        </div>
        <p className="text-xs text-muted-foreground sm:max-w-[70%] sm:text-right">{detail}</p>
      </div>
    </div>
  )
}

export function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-[100dvh] flex flex-col bg-background text-foreground">
      <NavBar />
      <MainnetStatusBanner />
      <main className="flex-1 container mx-auto px-4 py-8">
        {children}
      </main>
      <footer className="border-t py-8 bg-card mt-auto">
        <div className="container mx-auto px-4 flex flex-col md:flex-row items-center justify-between gap-4 text-sm text-muted-foreground">
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 rounded bg-primary/20 flex items-center justify-center">
              <span className="text-primary font-bold text-xs">PW</span>
            </div>
            <span>© {new Date().getFullYear()} PrimeWave Chain Explorer. All rights reserved.</span>
          </div>
          <div className="flex items-center gap-6">
            <a href="#" className="hover:text-foreground transition-colors">API</a>
            <a href="#" className="hover:text-foreground transition-colors">Terms</a>
            <a href="#" className="hover:text-foreground transition-colors">Privacy</a>
          </div>
        </div>
      </footer>
    </div>
  )
}
