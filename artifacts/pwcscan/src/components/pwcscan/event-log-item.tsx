import * as React from "react"
import { ChevronDown, ChevronUp } from "lucide-react"
import { cn } from "@/lib/utils"
import { DecodedEvent } from "@/lib/api"
import { Button } from "@/components/ui/button"

interface EventLogItemProps {
  event: DecodedEvent;
  logIndex?: number;
}

export function EventLogItem({ event, logIndex }: EventLogItemProps) {
  const [expanded, setExpanded] = React.useState(false)
  const isExpandable = event.decoded_json && Object.keys(event.decoded_json).length > 0;

  return (
    <div className="border rounded-lg overflow-hidden bg-card mb-4 last:mb-0">
      <div 
        className={cn("px-4 py-3 flex items-center justify-between", isExpandable && "cursor-pointer hover:bg-muted/50")}
        onClick={() => isExpandable && setExpanded(!expanded)}
      >
        <div className="flex items-center gap-3">
          {logIndex !== undefined && (
            <div className="w-8 h-8 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center text-xs font-medium">
              {logIndex}
            </div>
          )}
          <div>
            <div className="font-semibold text-sm">{event.event_name}</div>
            <div className="text-xs text-muted-foreground font-mono mt-0.5 max-w-[200px] sm:max-w-md md:max-w-xl truncate">
              {event.contract_address}
            </div>
          </div>
        </div>
        {isExpandable && (
          <Button variant="ghost" size="icon" className="h-8 w-8 text-muted-foreground shrink-0">
            {expanded ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </Button>
        )}
      </div>
      
      {expanded && isExpandable && (
        <div className="px-4 py-3 border-t bg-muted/20 font-mono text-xs overflow-x-auto">
          <pre className="text-foreground">
            {JSON.stringify(event.decoded_json, null, 2)}
          </pre>
        </div>
      )}
    </div>
  )
}
