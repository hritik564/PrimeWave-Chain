import { NetworkLink } from "@/lib/network"
import { ShieldCheck, Activity } from "lucide-react"
import { useStats } from "@/lib/api"
import { formatPW, formatEmissionRate } from "@/lib/format"
import { MetricCard } from "@/components/pwcscan/metric-card"
import { ReserveBar } from "@/components/pwcscan/reserve-bar"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"
import { ErrorState } from "@/components/pwcscan/error-state"
import { Skeleton } from "@/components/ui/skeleton"

export default function Rewards() {
  const { data: statsRes, isLoading, error, refetch } = useStats()
  const stats = statsRes

  if (error) return <ErrorState onRetry={refetch} />

  const funded = stats?.rewardVault.totalFunded;
  const emitted = stats?.rewardVault.totalEmitted;

  if (isLoading) {
    return <Skeleton className="h-[420px] w-full rounded-xl" />
  }
  if (!stats || funded === null || funded === undefined ||
    emitted === null || emitted === undefined ||
    stats.rewardVault.emissionRate === null) {
    return (
      <ErrorState
        title="Reward data unavailable"
        message="The indexer has not returned verified RewardVault data for this network."
        onRetry={refetch}
      />
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col gap-4">
        <div>
          <h1 className="text-3xl font-display font-bold tracking-tight mb-2 flex items-center gap-3">
            <ShieldCheck className="h-8 w-8 text-primary" />
            PrimeWave RewardVault
          </h1>
          <p className="text-muted-foreground">Distribution of rewards to network participants.</p>
        </div>

        <Card className="mb-4">
          <CardHeader className="pb-2 border-b bg-muted/10">
            <CardTitle className="text-lg">Vault Reserves</CardTitle>
          </CardHeader>
          <CardContent className="pt-6">
            <ReserveBar funded={funded} emitted={emitted} className="mb-4" />
            <p className="text-sm text-muted-foreground text-center">
              The RewardVault automatically distributes PW to active validators and stakers.
            </p>
          </CardContent>
        </Card>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <MetricCard 
            title="Total Funded"
            value={formatPW(funded)}
            isLoading={isLoading}
          />
          <MetricCard 
            title="Total Emitted"
            value={formatPW(emitted)}
            isLoading={isLoading}
            className="border-primary/20 bg-primary/5"
          />
          <MetricCard 
            title="Remaining"
            value={formatPW((BigInt(funded) - BigInt(emitted)).toString())}
            isLoading={isLoading}
          />
          <MetricCard 
            title="Emission Rate"
            value={formatEmissionRate(stats.rewardVault.emissionRate)}
            icon={<Activity className="h-5 w-5" />}
            isLoading={isLoading}
          />
        </div>
      </div>
      
      <div className="text-center text-muted-foreground mt-10">
        Individual reward claim history is not available from the current indexer. View indexed totals on <NetworkLink href="/validators" className="text-primary hover:underline">validator pages</NetworkLink>.
      </div>
    </div>
  )
}
