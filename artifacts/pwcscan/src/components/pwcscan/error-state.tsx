import * as React from "react"
import { AlertCircle, RefreshCw } from "lucide-react"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"

interface ErrorStateProps extends React.HTMLAttributes<HTMLDivElement> {
  title?: string;
  message?: string;
  onRetry?: () => void;
}

export function ErrorState({ 
  title = "Something went wrong", 
  message = "We couldn't load this data. Please try again.", 
  onRetry,
  className,
  ...props
}: ErrorStateProps) {
  return (
    <div 
      className={cn("flex flex-col items-center justify-center p-10 text-center border rounded-xl border-destructive/20 bg-destructive/5", className)}
      {...props}
    >
      <AlertCircle className="h-10 w-10 text-destructive/70 mb-4" />
      <h3 className="text-lg font-semibold tracking-tight text-foreground mb-2">{title}</h3>
      <p className="text-sm text-muted-foreground max-w-md mb-6">{message}</p>
      {onRetry && (
        <Button variant="outline" onClick={onRetry} className="gap-2 border-destructive/20 hover:bg-destructive/10">
          <RefreshCw className="h-4 w-4" />
          Retry
        </Button>
      )}
    </div>
  )
}
