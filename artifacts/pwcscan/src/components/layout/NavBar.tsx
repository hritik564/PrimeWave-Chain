import * as React from "react"
import { useState } from "react"
import { useLocation } from "wouter"
import { Search, Menu, Sun, Moon, Settings, Database, Activity, RefreshCw, ChevronDown, Check, Globe2 } from "lucide-react"
import { cn } from "@/lib/utils"
import { useSettings } from "@/lib/settings"
import { useStats } from "@/lib/api"
import { NETWORKS, NetworkLink, useNetwork } from "@/lib/network"
import type { NetworkId } from "@/lib/network-config"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Dialog, DialogContent, DialogTrigger } from "@/components/ui/dialog"

const NAV_LINKS = [
  { href: "/", label: "Home" },
  { href: "/blocks", label: "Blocks" },
  { href: "/transactions", label: "Transactions" },
  { href: "/contracts", label: "Contracts" },
  { href: "/validators", label: "Validators" },
  { href: "/staking", label: "Staking" },
  { href: "/rewards", label: "RewardVault" },
  { href: "/fees", label: "Fees" },
  { href: "/governance", label: "Governance" },
  { href: "/stats", label: "Stats" },
]

function NetworkSwitcher({ compact = false }: { compact?: boolean }) {
  const { networkId: selectedNetwork, network: currentNetwork, setNetwork } = useNetwork()
  const networkOptions = (Object.keys(NETWORKS) as NetworkId[]).map((id) => NETWORKS[id])

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="outline"
          size={compact ? "sm" : "default"}
          className={cn(
            "gap-2 border-dashed bg-background/80 font-semibold shadow-sm",
            compact ? "h-9 w-full justify-between px-3" : "h-10 rounded-full px-3 sm:px-4"
          )}
          aria-label={`Switch network, currently ${currentNetwork.label}`}
        >
          <span className={cn("flex items-center gap-2 rounded-full border px-2 py-0.5", currentNetwork.visual.badgeClass)}>
            <span className="h-1.5 w-1.5 rounded-full bg-current" aria-hidden="true" />
            <span>{currentNetwork.label}</span>
          </span>
          {!compact && currentNetwork.chainId && (
            <span className="hidden text-xs font-normal text-muted-foreground sm:inline">
              Chain {currentNetwork.chainId}
            </span>
          )}
          {!compact && !currentNetwork.chainId && (
            <span className="hidden text-xs font-normal text-muted-foreground sm:inline">
              Not configured
            </span>
          )}
          <ChevronDown className="h-4 w-4 text-muted-foreground" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-64">
        <DropdownMenuLabel className="flex items-center gap-2">
          <Globe2 className="h-4 w-4 text-muted-foreground" />
          Select network
        </DropdownMenuLabel>
        <DropdownMenuSeparator />
        {networkOptions.map((network) => (
          <DropdownMenuItem
            key={network.id}
            onSelect={() => setNetwork(network.id)}
            className="flex items-start gap-3 py-3"
          >
            <span className={cn("mt-0.5 h-2.5 w-2.5 shrink-0 rounded-full", network.status === "configured" ? "bg-current" : "bg-muted-foreground/40", network.visual.badgeClass)} />
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="flex items-center justify-between gap-2 font-medium">
                <span>{network.label}</span>
                {selectedNetwork === network.id && <Check className="h-4 w-4 text-primary" />}
              </span>
              <span className="text-xs text-muted-foreground">
                {network.chainId ? `${network.description} · Chain ${network.chainId}` : network.description}
              </span>
              <span className="text-[11px] text-muted-foreground">
                {network.status === "configured" ? "Configured" : "Configuration pending"}
              </span>
            </span>
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

export function NavBar() {
  const [location, setLocation] = useLocation()
  const [searchQuery, setSearchQuery] = useState("")
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const { theme, setTheme, autoRefresh, setAutoRefresh } = useSettings()
  const { buildNetworkPath } = useNetwork()

  // Use a longer refetch interval for the navbar to avoid excessive calls
  const { data: stats } = useStats(autoRefresh ? 30000 : undefined)

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault()
    if (searchQuery.trim().length > 0) {
      setLocation(buildNetworkPath(`/search?q=${encodeURIComponent(searchQuery.trim())}`))
      setSearchQuery("")
      setMobileMenuOpen(false)
    }
  }

  return (
    <header className="sticky top-0 z-40 w-full border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="container mx-auto px-4 h-16 flex items-center justify-between gap-4">
        <div className="flex items-center gap-6">
          <NetworkLink href="/" className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-primary flex items-center justify-center">
              <Database className="h-4 w-4 text-primary-foreground" />
            </div>
            <span className="font-display font-bold text-xl hidden sm:inline-block tracking-tight text-foreground">
              PWCScan
            </span>
          </NetworkLink>

          <nav className="hidden md:flex items-center gap-1">
            {NAV_LINKS.slice(1, 5).map((link) => (
              <NetworkLink
                key={link.href}
                href={link.href}
                className={cn(
                  "px-3 py-2 rounded-md text-sm font-medium transition-colors hover:bg-muted hover:text-foreground",
                  location === buildNetworkPath(link.href) ? "bg-muted text-foreground" : "text-muted-foreground"
                )}
              >
                {link.label}
              </NetworkLink>
            ))}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button variant="ghost" size="sm" className="font-medium text-muted-foreground">
                  More
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="start">
                {NAV_LINKS.slice(5).map((link) => (
                  <DropdownMenuItem key={link.href} asChild>
                    <NetworkLink href={link.href} className="w-full cursor-pointer">
                      {link.label}
                    </NetworkLink>
                  </DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
          </nav>
        </div>

        <div className="flex-1 max-w-xl hidden sm:block">
          <form onSubmit={handleSearch} className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search by Address / Tx Hash / Block / Validator ID"
              className="w-full pl-9 pr-4 bg-muted/50 border-transparent focus:bg-background h-10"
            />
          </form>
        </div>

        <div className="flex items-center gap-2 shrink-0">
          {stats && !stats.network.isSynced && (
            <div className="hidden lg:flex items-center gap-1.5 px-3 py-1 rounded-full bg-amber-500/10 border border-amber-500/20 text-amber-600 dark:text-amber-400 text-xs font-medium">
              <RefreshCw className="h-3 w-3 animate-spin" />
              Syncing...
            </div>
          )}

          <div className="hidden sm:block">
            <NetworkSwitcher />
          </div>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" className="h-9 w-9 rounded-full">
                <Settings className="h-5 w-5 text-muted-foreground" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuLabel>Appearance</DropdownMenuLabel>
              <div className="flex items-center justify-between px-2 py-1.5">
                <span className="text-sm">Theme</span>
                <div className="flex gap-1 bg-muted p-0.5 rounded-md">
                  <Button
                    variant="ghost"
                    size="icon"
                    className={cn("h-7 w-7 rounded-sm", theme === "light" && "bg-background shadow-sm")}
                    onClick={() => setTheme("light")}
                  >
                    <Sun className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className={cn("h-7 w-7 rounded-sm", theme === "dark" && "bg-background shadow-sm")}
                    onClick={() => setTheme("dark")}
                  >
                    <Moon className="h-4 w-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    className={cn("h-7 w-7 rounded-sm", theme === "system" && "bg-background shadow-sm")}
                    onClick={() => setTheme("system")}
                  >
                    <Settings className="h-4 w-4" />
                  </Button>
                </div>
              </div>
              <DropdownMenuSeparator />
              <DropdownMenuLabel>Preferences</DropdownMenuLabel>
              <DropdownMenuItem onClick={() => setAutoRefresh(!autoRefresh)} className="justify-between">
                <span>Auto-refresh Data</span>
                <span className={cn("text-xs font-medium px-1.5 py-0.5 rounded", autoRefresh ? "bg-primary/20 text-primary" : "bg-muted text-muted-foreground")}>
                  {autoRefresh ? "ON" : "OFF"}
                </span>
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <div className="sm:hidden">
            <NetworkSwitcher compact />
          </div>
          <Dialog open={mobileMenuOpen} onOpenChange={setMobileMenuOpen}>
            <DialogTrigger asChild>
              <Button variant="ghost" size="icon" className="md:hidden h-9 w-9">
                <Menu className="h-5 w-5" />
              </Button>
            </DialogTrigger>
            <DialogContent className="fixed inset-y-0 right-0 z-50 h-full w-3/4 max-w-sm rounded-none border-l sm:max-w-sm p-0 m-0 translate-x-0 translate-y-0 shadow-2xl flex flex-col slide-in-from-right data-[state=closed]:slide-out-to-right">
              <div className="p-4 border-b flex items-center justify-between bg-card">
                <span className="font-display font-bold text-lg">PWCScan Menu</span>
              </div>
              <div className="p-4 border-b bg-muted/20">
                <NetworkSwitcher compact />
              </div>
              <div className="p-4 border-b bg-muted/20">
                <form onSubmit={handleSearch} className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <Input
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    placeholder="Search..."
                    className="w-full pl-9"
                  />
                </form>
              </div>
              <div className="flex-1 overflow-y-auto p-2">
                <div className="flex flex-col space-y-1">
                  {NAV_LINKS.map((link) => (
                    <NetworkLink
                      key={link.href}
                      href={link.href}
                      onClick={() => setMobileMenuOpen(false)}
                      className={cn(
                        "px-4 py-3 rounded-md text-sm font-medium transition-colors",
                        location === buildNetworkPath(link.href) ? "bg-primary/10 text-primary" : "hover:bg-muted"
                      )}
                    >
                      {link.label}
                    </NetworkLink>
                  ))}
                </div>
              </div>
            </DialogContent>
          </Dialog>
        </div>
      </div>
    </header>
  )
}