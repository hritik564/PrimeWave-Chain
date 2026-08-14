import * as React from "react"
import { SearchX, FileQuestion, Activity, Inbox } from "lucide-react"
import { cn } from "@/lib/utils"

export type EmptyStateType = "no-data" | "not-found" | "no-results" | "coming-soon"

interface EmptyStateProps extends React.HTMLAttributes<HTMLDivElement> {
  title: string;
  description: string;
  type?: EmptyStateType;
  icon?: React.ReactNode;
}

export function EmptyState({ title, description, type = "no-data", icon, className, ...props }: EmptyStateProps) {
  const getIcon = () => {
    if (icon) return icon;
    switch (type) {
      case "not-found": return <FileQuestion className="h-10 w-10 text-muted-foreground/50" />
      case "no-results": return <SearchX className="h-10 w-10 text-muted-foreground/50" />
      case "coming-soon": return <Activity className="h-10 w-10 text-muted-foreground/50" />
      default: return <Inbox className="h-10 w-10 text-muted-foreground/50" />
    }
  }

  return (
    <div 
      className={cn("flex flex-col items-center justify-center p-12 text-center border rounded-xl border-dashed bg-card/50", className)}
      {...props}
    >
      <div className="bg-muted/50 p-4 rounded-full mb-4">
        {getIcon()}
      </div>
      <h3 className="text-lg font-semibold tracking-tight text-foreground mb-1">{title}</h3>
      <p className="text-sm text-muted-foreground max-w-sm">{description}</p>
    </div>
  )
}
