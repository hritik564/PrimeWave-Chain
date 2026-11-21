# C00 versus C11 — no allocation policy selected

Sources: [C00 token distribution](PRIMEWAVE_TOKENOMICS.md#2-token-distribution)
and [C11 genesis allocations](PW-C11-GENESIS-FINALIZATION.md#21-initial-distribution-100m-pw).
Percentages use the common100,000,000 PW total. An absent category means no
separate allocation is specified, not permission to spend its funds elsewhere.

| Wallet/category | C00 PW | C00 % | C11 PW | C11 % |
|---|---:|---:|---:|---:|
| PWSwap liquidity wallet, locked36 months | 40,000,000 | 40% | Not specified | — |
| Treasury multisig/timelock | 15,000,000 | 15% | 25,000,000 | 25% |
| Team/development vesting wallet | 10,000,000 | 10% | 20,000,000 | 20% |
| Validator/staking RewardVault | 15,000,000 | 15% | 15,000,000 | 15% |
| Presale Phase1 wallet | 5,000,000 | 5% | Not separately specified | — |
| Presale Phase2 wallet | 7,500,000 | 7.5% | Not separately specified | — |
| Presale Phase3 wallet | 7,500,000 | 7.5% | Not separately specified | — |
| Community-sale wallet | Not separately specified | — | 20,000,000 | 20% |
| Ecosystem-partner wallet | Not specified | — | 10,000,000 | 10% |
| Reserve wallet | Not specified | — | 9,999,999 | 9.999999% |
| Deployer gas wallet | No separate grant | — | 1 | 0.000001% |
| Total | 100,000,000 | 100% | 100,000,000 | 100% |

**Additional conflict:** C00 allocates15M directly to a pre-funded RewardVault
at genesis. C11§2.2 says those15M are not a genesis vault allocation and are
funded after deployment from a separate funding account, despite listing the
vault in its initial-distribution table. Its genesis custody address is unresolved.
Do not double-count those15M or invent an additional deployer/treasury grant.

Uncontested:100M total,18 decimals,15M reward allocation, NativeMinter disabled,
and70/20/10 fee routing. C00 identifies treasury multisig/timelock, liquidity lock,
team vesting decision and no presale vesting; C11 specifies4-year team vesting.
All actual wallet addresses remain absent or placeholders; none are selected here.

Owner must explicitly confirm C00, explicitly approve the complete C11 revision,
or supply a fully reconciled100M table. Do not mix rows. The existing review
manifest carries C00 as a reference with `ownerApproved:false`; genesis review
keeps `selectedAllocationPolicy:null`. Neither is a production approval.
