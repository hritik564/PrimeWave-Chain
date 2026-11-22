import * as React from 'react';
import { createContext, useContext, useMemo, useEffect, useCallback, type ReactNode } from 'react';
import { Link, useLocation } from 'wouter';
import {
  getDefaultNetwork,
  getNetwork,
  isNetworkAvailable,
  isNetworkId,
  NETWORKS,
  type NetworkDefinition,
  type NetworkId,
} from './network-config';

const NETWORK_STORAGE_KEY = 'pwcscan-network';
const LEGACY_ROUTE_SEGMENTS = new Set([
  'blocks',
  'transactions',
  'tx',
  'address',
  'contract',
  'contracts',
  'validators',
  'validator',
  'staking',
  'rewards',
  'fees',
  'governance',
  'stats',
  'search',
]);

interface NetworkContextValue {
  networkId: NetworkId;
  network: NetworkDefinition;
  isConfigured: boolean;
  isNetworkScoped: boolean;
  invalidNetworkId: string | null;
  setNetwork: (id: NetworkId) => void;
  buildNetworkPath: (path: string, id?: NetworkId) => string;
}

const NetworkContext = createContext<NetworkContextValue | undefined>(undefined);

function pathnameOnly(location: string): string {
  return location.split('?')[0] || '/';
}

function firstPathSegment(location: string): string | null {
  return pathnameOnly(location).split('/').filter(Boolean)[0] ?? null;
}

function removeNetworkPrefix(path: string): string {
  const normalized = path.startsWith('/') ? path : `/${path}`;
  const segments = normalized.split('/');
  segments.splice(1, 1);
  const result = segments.join('/') || '/';
  return result.startsWith('/') ? result : `/${result}`;
}

export function NetworkProvider({ children }: { children: ReactNode }) {
  const [location, setLocation] = useLocation();
  const currentPath = pathnameOnly(location);
  const segment = firstPathSegment(location);
  const isNetworkScoped = isNetworkId(segment) && isNetworkAvailable(segment);
  const invalidNetworkId = segment && !isNetworkScoped
    ? isNetworkId(segment) || !LEGACY_ROUTE_SEGMENTS.has(segment)
      ? segment
      : null
    : null;

  const storedNetwork =
    typeof window !== 'undefined' ? window.localStorage.getItem(NETWORK_STORAGE_KEY) : null;
  const storedNetworkId = isNetworkId(storedNetwork) ? storedNetwork : null;
  const fallbackNetworkId =
    storedNetworkId && isNetworkAvailable(storedNetworkId)
      ? storedNetworkId
      : getDefaultNetwork();
  const networkId = currentPath === '/'
    ? 'mainnet'
    : isNetworkScoped
      ? segment
      : fallbackNetworkId;
  const network = getNetwork(networkId);

  const buildNetworkPath = useCallback((path: string, targetId: NetworkId = networkId): string => {
    const normalizedPath = path.startsWith('/') ? path : `/${path}`;
    const pathWithoutNetwork = isNetworkId(firstPathSegment(normalizedPath))
      ? removeNetworkPrefix(normalizedPath)
      : normalizedPath;
    return pathWithoutNetwork === '/'
      ? `/${targetId}`
      : `/${targetId}${pathWithoutNetwork}`;
  }, [networkId]);

  const setNetwork = useCallback((targetId: NetworkId) => {
    if (!isNetworkAvailable(targetId)) return;
    const target = getNetwork(targetId);
    setLocation(buildNetworkPath(location, target.id));
    window.localStorage.setItem(NETWORK_STORAGE_KEY, target.id);
  }, [buildNetworkPath, location, setLocation]);

  useEffect(() => {
    if (isNetworkScoped) {
      window.localStorage.setItem(NETWORK_STORAGE_KEY, networkId);
    }
  }, [isNetworkScoped, networkId]);

  const value = useMemo<NetworkContextValue>(
    () => ({
      networkId,
      network,
      isConfigured: network.status === 'configured',
      isNetworkScoped,
      invalidNetworkId,
      setNetwork,
      buildNetworkPath,
    }),
    [networkId, network, isNetworkScoped, invalidNetworkId, setNetwork, buildNetworkPath],
  );

  return <NetworkContext.Provider value={value}>{children}</NetworkContext.Provider>;
}

export function useNetwork(): NetworkContextValue {
  const context = useContext(NetworkContext);
  if (!context) {
    throw new Error('useNetwork must be used within a NetworkProvider');
  }
  return context;
}

type NetworkLinkProps = {
  href: string;
  children?: ReactNode;
  className?: string;
  onClick?: React.MouseEventHandler<HTMLAnchorElement>;
};

export function NetworkLink({ href, ...props }: NetworkLinkProps) {
  const { buildNetworkPath } = useNetwork();
  const BaseLink = Link as unknown as React.ComponentType<NetworkLinkProps>;
  return <BaseLink {...props} href={buildNetworkPath(href)} />;
}

export { NETWORKS };