import * as React from "react"
import { Badge } from "@/components/ui/badge"
import { cn } from "@/lib/utils"

export type StatusType = "success" | "failed" | "pending" | "active" | "inactive" | "paused"

interface StatusBadgeProps extends React.HTMLAttributes<HTMLDivElement> {
  status: StatusType;
  label?: string;
}

export function StatusBadge({ status, label, className, ...props }: StatusBadgeProps) {
  const styles: Record<StatusType, string> = {
    success: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400 border-emerald-500/20",
    failed: "bg-destructive/15 text-destructive dark:text-destructive border-destructive/20",
    pending: "bg-amber-500/15 text-amber-700 dark:text-amber-400 border-amber-500/20",
    active: "bg-blue-500/15 text-blue-700 dark:text-blue-400 border-blue-500/20",
    inactive: "bg-muted text-muted-foreground border-border",
    paused: "bg-orange-500/15 text-orange-700 dark:text-orange-400 border-orange-500/20",
  }

  const defaultLabels: Record<StatusType, string> = {
    success: "Success",
    failed: "Failed",
    pending: "Pending",
    active: "Active",
    inactive: "Inactive",
    paused: "Paused",
  }

  return (
    <Badge
      variant="outline"
      className={cn("px-2 py-0.5 rounded-full font-medium text-xs", styles[status], className)}
      {...props}
    >
      {label || defaultLabels[status]}
    </Badge>
  )
}

export function ValidatorStatusBadge({ status, className }: { status: number, className?: string }) {
  const map: Record<number, { type: StatusType, label: string }> = {
    0: { type: "inactive", label: "Unknown" },
    1: { type: "pending", label: "Pending Added" },
    2: { type: "active", label: "Active" },
    3: { type: "pending", label: "Pending Removed" },
    4: { type: "inactive", label: "Completed" },
    5: { type: "failed", label: "Invalidated" },
  }
  const s = map[status] || map[0]
  return <StatusBadge status={s.type} label={s.label} className={className} />
}
