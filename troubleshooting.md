# 🛠️ Common Error Encountered & How I Solved It

This document outlines the key issue I faced while developing `SimpleSwap.sol` and how I solved it. It may help future developers understand a common Solidity pitfall and how to avoid it.

---

## 1️⃣ CompilerError: Stack too deep

**Description:**  

Solidity's EVM stack is limited to 16 variables per context. The `addLiquidity` function had too many input parameters and local variables, causing this compile-time error.

**Symptom:**  

```bash
Stack too deep. Try removing local variables.
```

**Cause:** 

- `addLiquidity` has 8 input parameters.

- Additional local variables pushed the total beyond the stack depth limit.

*First Attempt (Failed)*:

- I extracted part of the logic into _calculateAndVerifyLiquidityAmounts. → Still failed because the input parameters alone exceeded the stack limit.

**Final Solution:**

I [enabled](https://stackoverflow.com/questions/76470827/how-do-i-run-via-ir-in-remix) the Intermediate Representation (IR) compiler backend and the optimizer in [Remix](https://remix-ide.readthedocs.io/en/latest/compile.html#advanced-compiler-configurations):

```bash
{
  "optimizer": { "enabled": true, "runs": 200 },
  "viaIR": true
}
```

This allowed the compiler to optimize stack usage and eliminate the error.

*Additional Refactor (Optional but Useful)*:

I moved minting logic into _transferAndMintLiquidity to make the code more modular and readable. While not required by IR, it’s a clean coding practice

## 2️⃣ Runtime Error: `ERC20InvalidReceiver`

**Description:**  

This runtime error occurs when attempting to mint or transfer ERC20 tokens to the zero address.

**Cause:** 

`_mint(address(0), MINIMUM_LIQUIDITY);`

This line was intended to mimic Uniswap V2’s behavior of burning the minimum liquidity, but OpenZeppelin's ERC20 implementation does not allow minting to the zero address.

**Symptom:**  

```bash
Error: transaction reverted with reason string 'ERC20InvalidReceiver'
```

**Final Solution:**

Instead of minting to address(0), I simply subtracted MINIMUM_LIQUIDITY from the calculated liquidity:

```bash
liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
_mint(to, liquidity);
```

This preserved the desired burn logic without violating ERC20 rules.

## 3️⃣ Swap Revert: InsufficientOutputAmount

**Description:**  

This error occurs when the output of a swap is less than the user-specified amountOutMin.

**Cause:** 

- *Slippage*: Reserves may change slightly between read and execution.

- *Rounding*: Integer division in Solidity.

- *Fees*: The 0.3% swap fee affects final amountOut, which must be considered.

**Symptom:**

`Transaction reverted with custom error 'InsufficientOutputAmount()'`

**Test Solution**:

To bypass this during testing, I set amountOutMin = 1. This allowed the transaction to succeed as long as the actual output was greater than zero.

**Production Suggestion(I think):**

In a real deployment, amountOutMin should include a slippage buffer:

`amountOutMin = expectedAmountOut * 99 / 100; // 1% slippage tolerance`
