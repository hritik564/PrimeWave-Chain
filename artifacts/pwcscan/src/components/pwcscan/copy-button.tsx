import * as React from "react"
import { Copy, Check } from "lucide-react"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"

export interface CopyButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  value: string;
}

export const CopyButton = React.forwardRef<HTMLButtonElement, CopyButtonProps>(
  ({ value, className, ...props }, ref) => {
    const [copied, setCopied] = React.useState(false)

    const handleCopy = (e: React.MouseEvent<HTMLButtonElement>) => {
      e.preventDefault()
      e.stopPropagation()
      navigator.clipboard.writeText(value)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }

    return (
      <Button
        ref={ref}
        variant="ghost"
        size="icon"
        className={cn("h-6 w-6 text-muted-foreground hover:text-foreground", className)}
        onClick={handleCopy}
        title="Copy to clipboard"
        {...props}
      >
        {copied ? <Check className="h-3 w-3" /> : <Copy className="h-3 w-3" />}
        <span className="sr-only">Copy</span>
      </Button>
    )
  }
)
CopyButton.displayName = "CopyButton"
