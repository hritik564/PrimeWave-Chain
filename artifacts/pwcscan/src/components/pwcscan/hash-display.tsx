import * as React from "react"
import { cn } from "@/lib/utils"
import { formatHash } from "@/lib/format"
import { useSettings } from "@/lib/settings"
import { CopyButton } from "./copy-button"

interface HashDisplayProps extends React.HTMLAttributes<HTMLDivElement> {
  hash: string;
  showCopy?: boolean;
}

export function HashDisplay({ hash, showCopy = true, className, ...props }: HashDisplayProps) {
  const { addressDisplay } = useSettings();
  const displayValue = addressDisplay === 'truncated' ? formatHash(hash) : hash;

  return (
    <div className={cn("inline-flex items-center gap-1.5", className)} {...props}>
      <span className="font-mono text-sm" title={hash}>
        {displayValue}
      </span>
      {showCopy && <CopyButton value={hash} />}
    </div>
  )
}
