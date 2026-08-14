import * as React from "react"
import { cn } from "@/lib/utils"

interface ReserveBarProps {
  funded: string;
  emitted: string;
  className?: string;
}

export function ReserveBar({ funded, emitted, className }: ReserveBarProps) {
  let percent = 0;
  try {
    const f = BigInt(funded);
    const e = BigInt(emitted);
    if (f > 0n) {
      percent = Number((e * 10000n) / f) / 100;
    }
  } catch (err) {}

  return (
    <div className={cn("flex flex-col gap-2 w-full", className)}>
      <div className="flex justify-between items-end text-sm">
        <div className="space-y-0.5">
          <p className="text-muted-foreground text-xs">Emitted</p>
          <p className="font-medium text-primary">{percent.toFixed(2)}%</p>
        </div>
        <div className="space-y-0.5 text-right">
          <p className="text-muted-foreground text-xs">Remaining</p>
          <p className="font-medium">{(100 - percent).toFixed(2)}%</p>
        </div>
      </div>
      <div className="h-3 w-full bg-secondary rounded-full overflow-hidden relative">
        <div 
          className="absolute left-0 top-0 h-full bg-primary rounded-full transition-all duration-1000"
          style={{ width: `${Math.min(percent, 100)}%` }}
        />
      </div>
    </div>
  )
}
