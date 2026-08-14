import { useEffect } from "react"
import { useLocation } from "wouter"
import { useSearch } from "@/lib/api"
import { Skeleton } from "@/components/ui/skeleton"
import { EmptyState } from "@/components/pwcscan/empty-state"

export default function SearchResults() {
  const [location, setLocation] = useLocation()
  
  // Extract query from URL
  const query = typeof window !== 'undefined' 
    ? new URLSearchParams(window.location.search).get('q') 
    : '';

  const { data: searchRes, isLoading } = useSearch(query || "")

  useEffect(() => {
    if (searchRes && searchRes.type !== 'not_found' && searchRes.type !== 'invalid_format') {
      const type = searchRes.type
      const resultData = searchRes.data as any
      
      if (type === 'block') setLocation(`/blocks/${resultData.number}`)
      else if (type === 'transaction') setLocation(`/tx/${resultData.hash}`)
      else if (type === 'address') setLocation(`/address/${resultData.address}`)
      else if (type === 'validator') setLocation(`/validator/${resultData.validation_id}`)
    }
  }, [searchRes, setLocation])

  if (!query) {
    return <EmptyState type="no-results" title="No Search Query" description="Please enter an address, tx hash, or block number." />
  }

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center py-20 space-y-4">
        <Skeleton className="h-12 w-12 rounded-full" />
        <h2 className="text-xl font-medium animate-pulse">Searching PrimeWave Chain...</h2>
        <p className="text-muted-foreground">{query}</p>
      </div>
    )
  }

  return (
    <EmptyState 
      type="no-results" 
      title="No Results Found" 
      description={`We couldn't find any blocks, transactions, or addresses matching "${query}".`} 
    />
  )
}
