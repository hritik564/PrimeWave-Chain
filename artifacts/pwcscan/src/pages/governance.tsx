import { useFees } from "@/lib/api"
import { ErrorState } from "@/components/pwcscan/error-state"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { ShieldCheck, Clock, CheckCircle } from "lucide-react"

export default function Governance() {
  const { error, refetch } = useFees({ limit: 1 }) // Just pinging api for network status test
  
  if (error) return <ErrorState onRetry={refetch} />

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-display font-bold tracking-tight mb-2">PrimeWave Governance</h1>
        <p className="text-muted-foreground">Protocol governance parameters and recent proposals.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card className="bg-gradient-to-br from-card to-primary/5">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <ShieldCheck className="h-5 w-5 text-primary" />
              Emergency Multisig
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold font-display mb-2">3-of-5</div>
            <p className="text-sm text-muted-foreground">
              Core protocol upgrades and emergency pauses are governed by a 3-of-5 multisignature wallet controlled by the PrimeWave foundation and key ecosystem partners.
            </p>
          </CardContent>
        </Card>

        <Card className="bg-gradient-to-br from-card to-amber-500/5">
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Clock className="h-5 w-5 text-amber-500" />
              Timelock Controller
            </CardTitle>
          </CardHeader>
          <CardContent>
            <div className="text-3xl font-bold font-display mb-2">48 Hours</div>
            <p className="text-sm text-muted-foreground">
              All non-emergency protocol changes enforce a mandatory 48-hour timelock delay before execution to ensure community visibility and security.
            </p>
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="border-b">
          <CardTitle>Recent Governance Activity</CardTitle>
        </CardHeader>
        <CardContent className="p-12 text-center text-muted-foreground">
          <CheckCircle className="h-10 w-10 text-muted-foreground/30 mx-auto mb-4" />
          <p className="text-lg font-medium">No recent proposals</p>
          <p className="text-sm max-w-md mx-auto mt-2">
            The network is operating normally. Governance events will appear here when new proposals are created or executed.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
