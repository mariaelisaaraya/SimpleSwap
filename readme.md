![Course](https://img.shields.io/badge/Course-ETH_Kipu-blue)
![Mode](https://img.shields.io/badge/Mode-Online-lightgrey)
![Developer](https://img.shields.io/badge/Developer-3lisa-purple)
![State](https://img.shields.io/badge/State-Active-brightgreen)


# 📜 SimpleSwap - Uniswap-like DEX

---

**Version:** 1.0

**Network:** Compatible with EVM-compatible chains (e.g., Remix VM, Sepolia, Ethereum Mainnet)

**License:** MIT

---

## 📌 Essential Information

**Network:** Sepolia  

**Contract:**
  - **TokenA** [`0xBBeE036d5180e859Cd9db575d4A7fedceafd958f`](https://sepolia.etherscan.io/address/0xbbee036d5180e859cd9db575d4a7fedceafd958f#code)
  - **TokenB** [`0x640bff3107F2FD7711CBb4CCE5de02550f747CB3`](https://sepolia.etherscan.io/address/0x640bff3107f2fd7711cbb4cce5de02550f747cb3#code)
  - **SimpleSwap** 
**Owner:** `0x39581f1c36CfeBfB36934E583fb3e3CE92Ba6c58`  

---

## General Description

**SimpleSwap** is a basic Decentralized Exchange (DEX) smart contract inspired by the core functionalities of Uniswap V2. It enables users to:

* **Create and manage liquidity pools** for ERC-20 token pairs.
* **Perform token swaps** between assets within the pool.
* **Add and remove liquidity**, earning a share of trading fees.

This contract serves as a foundational example for understanding Automated Market Makers (AMMs) without relying on external Uniswap protocols.

---

## Setup and Usage

### 1. Requirements

* **Development Environment:** Remix IDE, Hardhat, or Foundry.
* **Dependencies:** OpenZeppelin Contracts.
  
    ```bash
    npm install @openzeppelin/contracts
    ```

### 2. Deployment

1.  **Compile Contracts:**
   
    Make sure you compile `SimpleSwap.sol` along with any mock ERC-20 token contracts (`MockTokenA.sol`, `MockTokenB.sol`) if you're using them for testing.
    
2.  **Deploy `SimpleSwap`:**
   
    The `SimpleSwap` contract's constructor requires the addresses of the two ERC-20 tokens (`tokenA_` and `tokenB_`) that will form the liquidity pair.

    **Example Deployment (Remix IDE):**
    * Deploy your `MockTokenA` and `MockTokenB` instances first to get their addresses.
    * Then deploy `SimpleSwap` using those two token addresses in the constructor parameters.

---

## 📖 Key Functionalities

### Add Liquidity (`addLiquidity`)

Allows users to contribute tokens to the liquidity pool, receiving LP (Liquidity Provider) tokens in return, representing their share of the pool.

```solidity
function addLiquidity(
    address tokenA_,
    address tokenB_,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
```

- `tokenA_`, `tokenB_`: Addresses of the two ERC-20 tokens for the pair.
- `amountADesired`, `amountBDesired`: The preferred amounts of Token A and Token B the user wishes to add.
- `amountAMin`, `amountBMin`: Minimum acceptable amounts of Token A and Token B to prevent unfavorable price changes or slippage during liquidity provision.
- `to`: The address where the minted LP tokens will be sent.
- `deadline`: The Unix timestamp after which the transaction will revert if not processed.
- Returns (`amountA`, `amountB`, `liquidity`): The actual amounts of Token A and Token B added, and the amount of LP tokens minted.

### Remove Liquidity (`removeLiquidity`)

Allows users to withdraw their proportional share of tokens from the liquidity pool by burning their LP tokens.

```solidity
function removeLiquidity(
    address tokenA_,
    address tokenB_,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
) external returns (uint256 amountA, uint256 amountB);
```

- `tokenA_`, `tokenB_`: Addresses of the two ERC-20 tokens in the pair.
- `liquidity`: The amount of LP tokens to burn.
- `amountAMin`, `amountBMin`: Minimum acceptable amounts of Token A and Token B to receive, to prevent slippage.
- `to`: The address where the withdrawn Token A and Token B will be sent.
- `deadline`: The Unix timestamp after which the transaction will revert.
- Returns (`amountA`, `amountB`): The amounts of Token A and Token B received after removing liquidity.

### Swap Tokens (`swapExactTokensForTokens`)

Executes a swap, allowing users to exchange a precise amount of one token for another.

```solidity
function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
) external returns (uint256[] memory amounts);
```

- `amountIn`: The exact amount of the input token the user wants to swap.
- `amountOutMin`: The minimum acceptable amount of the output token to receive, to prevent excessive slippage.
- `path`: An array of token addresses defining the swap route. For SimpleSwap, this array must have a length of 2: [`InputTokenAddress`, `OutputTokenAddress`].
- `to`: The address where the output tokens will be sent.
- `deadline`: The Unix timestamp after which the transaction will revert.
- Returns (`amounts`): A dynamic array containing two elements: [`amountIn`, `amountOut`].
