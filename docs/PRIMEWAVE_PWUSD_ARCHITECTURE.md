# PrimeWave Chain — PWUSD Architecture
**Sprint PW-C00 | Status: DESIGN DOCUMENT — NOT FOR PRODUCTION**

---

## 1. Overview

PrimeWave USD (PWUSD) is the PrimeWave ecosystem's settlement asset. It is a separate ERC-20 token deployed on PrimeWave Chain. It is NOT the native gas asset (that is PW).

| Parameter | Value |
|---|---|
| Name | PrimeWave USD |
| Ticker | PWUSD |
| Standard | ERC-20 (OpenZeppelin) |
| Chain | PrimeWave Chain (native) |
| Maximum Supply | None fixed at launch |
| Gas Token | NO — PW is used for gas |

---

## 2. Intended Uses

PWUSD is used for:
- PWSwap settlement (PW/PWUSD trading pair)
- ROI income distribution
- Binary Matching income
- Binary Orbit income
- Level income
- Salary income
- Future P2P settlement

PWUSD is NOT and MUST NOT be represented as:
- Tether USDT
- Any USD-backed stablecoin with external redemption guarantees
- The native PrimeWave blockchain asset

---

## 3. Monetary Authority Architecture

### 3.1 Role Design

One designated **Monetary Authority** address holds the sole authority to mint and burn PWUSD.

The Monetary Authority is a dedicated role with narrowly scoped permissions:

```solidity
interface IPWUSD {
    function mint(address to, uint256 amount) external; // MonetaryAuthority only
    function burn(address from, uint256 amount) external; // MonetaryAuthority only
}
```

### 3.2 What the Monetary Authority CANNOT Do

The Monetary Authority role MUST NOT grant any of the following:

| Forbidden Action | Rationale |
|---|---|
| Withdraw Treasury funds | Separate treasury role |
| Transfer arbitrary user funds | User sovereignty |
| Modify arbitrary user balances | User sovereignty |
| Manage validators | Separate validator governance |
| Upgrade the blockchain protocol | Separate upgrade governance |
| Control emergency security measures | Separate emergency multisig |
| Manipulate PWSwap reserves | DEX is permissionless |

### 3.3 Role Separation Summary

```
PrimeWave Governance Roles (MUST be strictly separate):

┌─────────────────────┐    ┌──────────────────────┐
│  Monetary Authority  │    │  Treasury Multisig   │
│  (PWUSD mint/burn)  │    │  (Treasury funds)    │
└─────────────────────┘    └──────────────────────┘

┌─────────────────────┐    ┌──────────────────────┐
│  Validator Manager  │    │  Emergency Multisig  │
│  Admin (validators) │    │  (Emergency pause)   │
└─────────────────────┘    └──────────────────────┘

┌─────────────────────┐
│  Protocol Admin     │
│  (Upgrades/Timelock)│
└─────────────────────┘
```

No single address or multisig holds more than ONE of these roles.

---

## 4. PWUSD Contract Design

### 4.1 Recommended Implementation

```solidity
contract PWUSD is ERC20, AccessControl {
    bytes32 public constant MONETARY_AUTHORITY_ROLE = keccak256("MONETARY_AUTHORITY_ROLE");

    event Minted(address indexed to, uint256 amount, uint256 timestamp);
    event Burned(address indexed from, uint256 amount, uint256 timestamp);

    function mint(address to, uint256 amount)
        external
        onlyRole(MONETARY_AUTHORITY_ROLE)
    {
        _mint(to, amount);
        emit Minted(to, amount, block.timestamp);
    }

    function burn(address from, uint256 amount)
        external
        onlyRole(MONETARY_AUTHORITY_ROLE)
    {
        _burn(from, amount);
        emit Burned(from, amount, block.timestamp);
    }
}
```

### 4.2 Audit Requirements

Every PWUSD mint and burn MUST:
- Emit a named event (`Minted` / `Burned`) with `to/from`, `amount`, and `timestamp`
- Be visible in the block explorer
- Be indexable by the PrimeWave Dex indexer
- Be attributable to the calling Monetary Authority address

### 4.3 Upgradeability

PWUSD should be deployed behind an upgradeable proxy (OpenZeppelin Transparent Proxy or UUPS) with:
- Upgrade controlled by Protocol Admin (multisig + timelock)
- Monetary Authority cannot trigger upgrades

---

## 5. Operational Guidelines

### 5.1 Minting Policy (Operational — not enforced on-chain in V1)

Mints should:
- Be tied to documented business events (income distribution cycle, etc.)
- Be logged in PrimeWave's internal operational records
- Be consistent with PrimeWave's economic model

### 5.2 Future: USDT Redemption

The long-term objective is that PWUSD can be redeemed for actual USDT through the PrimeWave application. This is a future feature that requires:
- A separate USDT reserve custodial arrangement
- Legal/regulatory review
- Integration with the PrimeWave application's payment rails

This is NOT part of PW-C00 or early sprints.

---

## 6. Risk Controls

| Risk | Mitigation |
|---|---|
| Monetary Authority key compromise | Use a multisig for the Monetary Authority role (not a single EOA) |
| Excessive minting | On-chain supply monitoring + governance alert thresholds |
| Unauthorized burn | Auditable events; Monetary Authority is a multisig |
| Role escalation | AccessControl with DEFAULT_ADMIN_ROLE separate from MONETARY_AUTHORITY_ROLE |
| Replay attacks | Standard EIP-712 nonce-based mechanisms (if permit functions added) |

---

*This document is a PW-C00 design specification. No production deployment has occurred.*
