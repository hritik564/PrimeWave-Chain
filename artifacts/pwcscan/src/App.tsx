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

function Router() {
  return (
    <AppLayout>
      <RoutedErrorBoundary>
        <Switch>
          <Route path="/" component={Home} />
          <Route path="/blocks" component={Blocks} />
          <Route path="/blocks/:number" component={BlockDetail} />
          <Route path="/transactions" component={Transactions} />
          <Route path="/tx/:hash" component={TransactionDetail} />
          <Route path="/address/:address" component={AddressDetail} />
          <Route path="/contract/:address" component={AddressDetail} />
          <Route path="/contracts" component={Contracts} />
          <Route path="/validators" component={Validators} />
          <Route path="/validator/:id" component={ValidatorDetail} />
          <Route path="/staking" component={Staking} />
          <Route path="/rewards" component={Rewards} />
          <Route path="/fees" component={Fees} />
          <Route path="/governance" component={Governance} />
          <Route path="/stats" component={Stats} />
          <Route path="/search" component={SearchResults} />
          <Route component={NotFound} />
        </Switch>
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
            <Router />
          </WouterRouter>
          <Toaster />
        </TooltipProvider>
      </SettingsProvider>
    </QueryClientProvider>
  );
}

export default App;
