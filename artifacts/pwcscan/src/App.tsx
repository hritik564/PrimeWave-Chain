import * as React from 'react';
import { type ReactNode } from 'react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ErrorBoundary } from '@/components/error-boundary';
import { Toaster } from '@/components/ui/toaster';
import { TooltipProvider } from '@/components/ui/tooltip';
import { SettingsProvider } from '@/lib/settings';

import {
  Route,
  Switch,
  useLocation,
  Router as WouterRouter,
} from 'wouter';

import { AppLayout } from '@/components/layout/AppLayout';
import { NetworkLink, NetworkProvider, useNetwork } from '@/lib/network';
import { AlertTriangle, Clock3 } from 'lucide-react';
import { Button } from '@/components/ui/button';

import Home from '@/pages/home';
import Blocks from '@/pages/blocks';
import BlockDetail from '@/pages/block-detail';
import Transactions from '@/pages/transactions';
import TransactionDetail from '@/pages/transaction-detail';
import AddressDetail from '@/pages/address-detail';
import Contracts from '@/pages/contracts';
import Validators from '@/pages/validators';
import ValidatorDetail from '@/pages/validator-detail';
import Staking from '@/pages/staking';
import Rewards from '@/pages/rewards';
import Fees from '@/pages/fees';
import Governance from '@/pages/governance';
import Stats from '@/pages/stats';
import SearchResults from '@/pages/search';
import NotFound from '@/pages/not-found';

const queryClient = new QueryClient();

function NetworkUnavailableState() {
  const { network } = useNetwork();
  const isMainnet = network.id === 'mainnet';

  return (
    <div className="min-h-[60vh] flex flex-col items-center justify-center text-center px-4">
      <div className="w-16 h-16 bg-muted/50 rounded-full flex items-center justify-center mb-6">
        <Clock3 className="h-8 w-8 text-muted-foreground" />
      </div>
      <h1 className="text-3xl font-display font-bold tracking-tight mb-2">
        {network.label}
      </h1>
      <h2 className="text-xl text-foreground font-medium mb-4">
        {isMainnet ? 'Configuration pending' : 'Indexer endpoint unavailable'}
      </h2>
      <p className="text-muted-foreground max-w-md">
        {isMainnet
          ? 'Mainnet network identity and explorer endpoints will appear here after the architecture and deployment are finalized.'
          : `${network.label} is registered, but its explorer indexer endpoint is not configured for this preview.`}
      </p>
      <p className="text-sm text-muted-foreground mt-3">
        {isMainnet
          ? `No ${network.label} data source is configured.`
          : `Set VITE_${network.id.toUpperCase()}_INDEXER_API_URL to connect this network.`}
      </p>
    </div>
  );
}

function InvalidNetworkState() {
  const { invalidNetworkId } = useNetwork();

  return (
    <div className="min-h-[60vh] flex flex-col items-center justify-center text-center px-4">
      <AlertTriangle className="h-10 w-10 text-amber-500 mb-5" />
      <h1 className="text-3xl font-display font-bold tracking-tight mb-2">
        Invalid network
      </h1>
      <p className="text-muted-foreground max-w-md mb-6">
        “{invalidNetworkId}” is not a supported PrimeWave network. Use Testnet
        or Mainnet in the URL.
      </p>
      <Button asChild>
        <NetworkLink href="/testnet">Go to Testnet</NetworkLink>
      </Button>
    </div>
  );
}

function LegacyRouteRedirect() {
  const [location, setLocation] = useLocation();
  const { buildNetworkPath } = useNetwork();

  React.useEffect(() => {
    setLocation(buildNetworkPath(location));
  }, [buildNetworkPath, location, setLocation]);

  return (
    <div className="min-h-[60vh] flex items-center justify-center text-muted-foreground">
      Loading network…
    </div>
  );
}

function NetworkRoutes() {
  const { isNetworkScoped, invalidNetworkId, isConfigured } = useNetwork();

  if (invalidNetworkId) {
    return <InvalidNetworkState />;
  }

  if (!isNetworkScoped) {
    return <LegacyRouteRedirect />;
  }

  return (
    <AppLayout>
      <RoutedErrorBoundary>
        {isConfigured ? (
          <Switch>
            <Route path="/:networkId" component={Home} />
            <Route path="/:networkId/blocks" component={Blocks} />
            <Route path="/:networkId/blocks/:number" component={BlockDetail} />
            <Route path="/:networkId/transactions" component={Transactions} />
            <Route path="/:networkId/tx/:hash" component={TransactionDetail} />
            <Route path="/:networkId/address/:address" component={AddressDetail} />
            <Route path="/:networkId/contract/:address" component={AddressDetail} />
            <Route path="/:networkId/contracts" component={Contracts} />
            <Route path="/:networkId/validators" component={Validators} />
            <Route path="/:networkId/validator/:id" component={ValidatorDetail} />
            <Route path="/:networkId/staking" component={Staking} />
            <Route path="/:networkId/rewards" component={Rewards} />
            <Route path="/:networkId/fees" component={Fees} />
            <Route path="/:networkId/governance" component={Governance} />
            <Route path="/:networkId/stats" component={Stats} />
            <Route path="/:networkId/search" component={SearchResults} />
            <Route component={NotFound} />
          </Switch>
        ) : (
          <NetworkUnavailableState />
        )}
      </RoutedErrorBoundary>
    </AppLayout>
  );
}

function RoutedErrorBoundary({ children }: { children: ReactNode }) {
  const [location] = useLocation();
  return <ErrorBoundary resetKey={location}>{children}</ErrorBoundary>;
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <SettingsProvider>
        <TooltipProvider>
          <WouterRouter base={import.meta.env.BASE_URL.replace(/\/$/, '')}>
            <NetworkProvider>
              <NetworkRoutes />
            </NetworkProvider>
          </WouterRouter>
          <Toaster />
        </TooltipProvider>
      </SettingsProvider>
    </QueryClientProvider>
  );
}

export default App;
