import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { CircleHelp } from "lucide-react"

export default function Governance() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-display font-bold tracking-tight mb-2">PrimeWave Governance</h1>
        <p className="text-muted-foreground">Governance records will appear when they are available from the verified indexer.</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <CircleHelp className="h-5 w-5 text-muted-foreground" />
            Governance data unavailable
          </CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            The current explorer API does not provide governance configuration, proposal status, or verified multisig and timelock state. No governance settings or activity are inferred.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
