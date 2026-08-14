import * as React from "react"
import { cn } from "@/lib/utils"
import { EmptyState } from "./empty-state"
import { Skeleton } from "@/components/ui/skeleton"
import { Pagination } from "./pagination"

interface Column<T> {
  key: string;
  header: React.ReactNode;
  render: (item: T) => React.ReactNode;
  className?: string;
}

interface DataTableProps<T> {
  columns: Column<T>[];
  data?: T[];
  isLoading?: boolean;
  keyExtractor: (item: T) => string;
  emptyTitle?: string;
  emptyDescription?: string;
  className?: string;
  pagination?: {
    hasPrev: boolean;
    hasNext: boolean;
    onPrev: () => void;
    onNext: () => void;
    label?: string;
  };
}

export function DataTable<T>({ 
  columns, 
  data, 
  isLoading, 
  keyExtractor, 
  emptyTitle = "No data found", 
  emptyDescription = "There are no records to display here.",
  className,
  pagination
}: DataTableProps<T>) {

  if (!isLoading && (!data || data.length === 0)) {
    return <EmptyState title={emptyTitle} description={emptyDescription} className="my-4" />
  }

  return (
    <div className={cn("w-full space-y-4", className)}>
      <div className="rounded-xl border bg-card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left">
            <thead className="bg-muted/50 border-b">
              <tr>
                {columns.map((col) => (
                  <th key={col.key} className={cn("px-4 py-3 font-medium text-muted-foreground whitespace-nowrap", col.className)}>
                    {col.header}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y">
              {isLoading ? (
                Array.from({ length: 5 }).map((_, i) => (
                  <tr key={`skeleton-${i}`} className="bg-card">
                    {columns.map((col) => (
                      <td key={`skeleton-${i}-${col.key}`} className={cn("px-4 py-3", col.className)}>
                        <Skeleton className="h-5 w-full max-w-[80%]" />
                      </td>
                    ))}
                  </tr>
                ))
              ) : (
                data?.map((item) => (
                  <tr key={keyExtractor(item)} className="bg-card hover:bg-muted/30 transition-colors">
                    {columns.map((col) => (
                      <td key={`${keyExtractor(item)}-${col.key}`} className={cn("px-4 py-3 align-middle", col.className)}>
                        {col.render(item)}
                      </td>
                    ))}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
      
      {pagination && (
        <Pagination 
          hasPrev={pagination.hasPrev}
          hasNext={pagination.hasNext}
          onPrev={pagination.onPrev}
          onNext={pagination.onNext}
          label={pagination.label}
        />
      )}
    </div>
  )
}
