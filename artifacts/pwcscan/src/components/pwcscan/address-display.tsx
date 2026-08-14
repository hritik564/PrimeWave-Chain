import * as React from "react"
import { cn } from "@/lib/utils"
import { formatAddress } from "@/lib/format"
import { useSettings } from "@/lib/settings"
import { CopyButton } from "./copy-button"

interface AddressDisplayProps extends React.HTMLAttributes<HTMLDivElement> {
  address: string;
  showCopy?: boolean;
}

export function AddressDisplay({ address, showCopy = true, className, ...props }: AddressDisplayProps) {
  const { addressDisplay } = useSettings();
  const displayValue = addressDisplay === 'truncated' ? formatAddress(address) : address;

  return (
    <div className={cn("inline-flex items-center gap-1.5", className)} {...props}>
      <span className="font-mono text-sm group relative" title={address}>
        {displayValue}
      </span>
      {showCopy && <CopyButton value={address} />}
    </div>
  )
}
