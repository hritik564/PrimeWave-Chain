import * as React from "react"
import { formatGasPercent } from "@/lib/format"
import { cn } from "@/lib/utils"

interface GasBarProps {
  used: string;
  limit: string;
  className?: string;
}

export function GasBar({ used, limit, className }: GasBarProps) {
  const percentStr = formatGasPercent(used, limit);
  const percentNum = parseFloat(percentStr);
  
  let color = "bg-primary"
  if (percentNum > 80) color = "bg-destructive"
  else if (percentNum > 50) color = "bg-amber-500"

  return (
    <div className={cn("flex flex-col gap-1 w-full max-w-[120px]", className)}>
      <div className="flex justify-between items-center text-[10px] text-muted-foreground">
        <span>{percentStr}</span>
      </div>
      <div className="h-1.5 w-full bg-secondary rounded-full overflow-hidden">
        <div 
          className={cn("h-full rounded-full", color)}
          style={{ width: `${Math.min(percentNum, 100)}%` }}
        />
      </div>
    </div>
  )
}
