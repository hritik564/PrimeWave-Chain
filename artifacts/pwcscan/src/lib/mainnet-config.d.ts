export declare const PRIMEWAVE_MAINNET_CHAIN_ID: 735;
export declare const PRIMEWAVE_MAINNET_SUBNET_ID: '24Bvo25NiZTeC95Q7kMwW116kp5su7yj43QyKagrZZULhrmYkF';
export declare const PRIMEWAVE_MAINNET_BLOCKCHAIN_ID: '6YLeDTNiHRJefJQQTRms3EkWn4D2Rhcwv5PC547vg6KbLc3jF';
export interface MainnetNetworkConfig {
  chainId: 735;
  subnetId: string;
  blockchainId: string | null;
  nativeCurrency: { name: string; symbol: string; decimals: 18 };
  rpcUrl: string | null;
  websocketUrl: string | null;
  indexerApiUrl: string | null;
  status: 'configured' | 'unconfigured';
  description: string;
}
export type MainnetConfigEnv = Record<string, string | undefined>;
export declare function buildMainnetNetwork(env: MainnetConfigEnv): MainnetNetworkConfig;
