import * as React from "react"
import { ChevronLeft, ChevronRight } from "lucide-react"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"

interface PaginationProps {
  onPrev?: () => void;
  onNext?: () => void;
  hasPrev: boolean;
  hasNext: boolean;
  label?: string;
  className?: string;
}

export function Pagination({ onPrev, onNext, hasPrev, hasNext, label, className }: PaginationProps) {
  if (!hasPrev && !hasNext && !label) return null;

  return (
    <div className={cn("flex items-center justify-between py-4", className)}>
      <div className="text-sm text-muted-foreground flex-1">
        {label && <span>{label}</span>}
      </div>
      <div className="flex items-center gap-2">
        <Button 
          variant="outline" 
          size="sm" 
          onClick={onPrev} 
          disabled={!hasPrev}
          className="gap-1 h-8"
        >
          <ChevronLeft className="h-4 w-4" />
          <span>Previous</span>
        </Button>
        <Button 
          variant="outline" 
          size="sm" 
          onClick={onNext} 
          disabled={!hasNext}
          className="gap-1 h-8"
        >
          <span>Next</span>
          <ChevronRight className="h-4 w-4" />
        </Button>
      </div>
    </div>
  )
}
