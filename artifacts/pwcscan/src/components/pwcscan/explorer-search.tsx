import * as React from "react"
import { Search } from "lucide-react"
import { useLocation } from "wouter"
import { cn } from "@/lib/utils"
import { useNetwork } from "@/lib/network"
import { Input } from "@/components/ui/input"

type ExplorerSearchProps = {
  className?: string
  inputClassName?: string
  placeholder?: string
  onSearchSubmitted?: () => void
}

export function ExplorerSearch({
  className,
  inputClassName,
  placeholder = "Search by Address / Tx Hash / Block / Validator ID",
  onSearchSubmitted,
}: ExplorerSearchProps) {
  const [, setLocation] = useLocation()
  const { buildNetworkPath } = useNetwork()
  const [searchQuery, setSearchQuery] = React.useState("")
  const inputId = React.useId()

  const handleSearch = (event: React.FormEvent) => {
    event.preventDefault()
    const query = searchQuery.trim()

    if (query.length > 0) {
      setLocation(buildNetworkPath(`/search?q=${encodeURIComponent(query)}`))
      setSearchQuery("")
      onSearchSubmitted?.()
    }
  }

  return (
    <form onSubmit={handleSearch} className={cn("relative", className)} role="search">
      <label htmlFor={inputId} className="sr-only">
        Search PrimeWave Chain
      </label>
      <Search
        className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground"
        aria-hidden="true"
      />
      <Input
        id={inputId}
        value={searchQuery}
        onChange={(event) => setSearchQuery(event.target.value)}
        placeholder={placeholder}
        className={cn("w-full pl-9 pr-4", inputClassName)}
      />
    </form>
  )
}