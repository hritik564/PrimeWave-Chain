# PrimeWave Chain — PWSwap Integration Boundary
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Overview

PWSwap is PrimeWave's decentralized exchange (DEX). It is a separate project from PrimeWave Chain but is architecturally dependent on it.

This document defines the **interface boundary** between PrimeWave Chain and the PWSwap project.

> **Scope of PW-C00:** This document defines the interface only. PWSwap contracts are NOT built in PW-C00.

---

## 2. PWSwap Identity

| Parameter | Value |
|---|---|
| Name | PWSwap |
| Type | AMM DEX (Automated Market Maker) |
| Model | Constant-product (Uniswap V2 architecture) |
| Trading Pair (V1) | PW / PWUSD |
| Swap Fee | 0.30% |
| Fee Recipient | 100% to PrimeWave Treasury |
| Initial PW Liquidity | 40,000,000 PW |
| Initial PWUSD Liquidity | 2,000,000 PWUSD |
| Implied Initial PW Price | $0.05 per PW |
| Initial Liquidity Lock | 36 months |

---

## 3. Architecture Boundary

```
PrimeWave Chain
├── PW (native gas token)
├── PWUSD (ERC-20)
└── PWSwap contracts (separate project, deployed ON PrimeWave Chain)
    ├── PWSwapFactory.sol
    ├── PWSwapPair.sol    (PW/PWUSD pair)
    └── PWSwapRouter.sol
```

PWSwap is deployed ON PrimeWave Chain as smart contracts. The chain itself does not know about PWSwap — it is just another contract.

---

## 4. Required Contract Interface

PWSwap must expose standard AMM events for compatibility with the PrimeWave Dex indexer:

### 4.1 Required Events

```solidity
// On PWSwapPair
event Swap(
    address indexed sender,
    uint256 amount0In,
    uint256 amount1In,
    uint256 amount0Out,
    uint256 amount1Out,
    address indexed to
);

event Sync(uint112 reserve0, uint112 reserve1);

event Mint(address indexed sender, uint256 amount0, uint256 amount1);   // LP add
event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to); // LP remove
```

These events are the data source for PrimeWave Dex market analytics.

### 4.2 Required View Functions

```solidity
// On PWSwapPair
function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
function price0CumulativeLast() external view returns (uint256); // TWAP
function price1CumulativeLast() external view returns (uint256); // TWAP
function totalSupply() external view returns (uint256);          // LP tokens

// On PWSwapFactory
function getPair(address tokenA, address tokenB) external view returns (address pair);
```

---

## 5. PrimeWave Chain Interface Requirements for PWSwap

For PWSwap to function on PrimeWave Chain, the chain must provide:

| Requirement | How Provided |
|---|---|
| PW as native token | Genesis allocation |
| PWUSD as ERC-20 | PWUSD contract deployed |
| Standard EVM execution | Subnet-EVM |
| Gas payment in PW | Native chain behavior |
| No arbitrary price-setting by admin | PWSwap contract design (no setPrice function) |

---

## 6. PWSwap Required Features (for future implementation)

When PWSwap is built, it MUST include:

| Feature | Purpose |
|---|---|
| Slippage protection | Minimum amount out parameter on all swaps |
| Minimum received protection | Revert if output < minimum |
| Liquidity accounting | Accurate LP token issuance |
| LP accounting | Proper LP share tracking |
| Fee accounting | 0.30% fee captured and routed |
| TWAP/reference price | Price oracle capability |
| Emergency controls | Pause mechanism (multisig controlled) |
| Proper events | Full Swap/Mint/Burn/Sync events |
| Strong invariant testing | k = x*y must hold |

PWSwap MUST NOT have:
- Arbitrary administrator price-setting function
- Admin ability to drain liquidity without LP token burn
- Unconstrained fee changes (fees should be governance-controlled with timelock)

---

## 7. Initial Liquidity Process

1. At mainnet launch, 40,000,000 PW and 2,000,000 PWUSD are available for liquidity
2. The PWSwap deployment is completed and verified
3. PrimeWave Treasury (multisig) adds initial liquidity via `PWSwapRouter.addLiquidity()`
4. Resulting LP tokens are sent to a 36-month time-lock contract
5. LP tokens cannot be redeemed until the lock expires

This process ensures the initial market has deep liquidity and no rug-pull risk during the lock period.

---

## 8. What Is NOT Built in PW-C00

- PWSwap contracts (no implementation)
- PWSwap frontend
- LP token contracts
- PWSwap testing suite

These are separate project deliverables for the PrimeWave Swap project.

---

*This document is a PW-C00 design specification. No production deployment has occurred.*
