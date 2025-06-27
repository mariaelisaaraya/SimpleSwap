// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

library TransferHelper {
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }
}

contract SimpleSwap is ERC20 {
    address public immutable tokenA;
    address public immutable tokenB;
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    event Mint(address indexed sender, uint256 amountA, uint256 amountB);
    event Burn(address indexed sender, uint256 amountA, uint256 amountB, address indexed to);
    event Swap(address indexed sender, uint256 amountIn, uint256 amountOut, address indexed to);

    error InsufficientLiquidity();
    error InvalidToken();
    error InvalidAddress();
    error InsufficientOutputAmount();
    error InvalidLiquidityProvision();
    error DeadlineExpired();
    error InvalidSwapRoute();
    error InsufficientLiquidityMinted();

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        _;
    }

    modifier validAddress(address to) {
        if (to == address(0) || to == address(this)) revert InvalidAddress();
        _;
    }

    constructor(address tokenA_, address tokenB_) ERC20("SimpleSwap LP Token", "SS-LP") {
        tokenA = tokenA_;
        tokenB = tokenB_;
    }

    /**
     * @notice Returns the current reserves of tokenA and tokenB in the pool.
     * @return reserveA The balance of tokenA in the contract.
     * @return reserveB The balance of tokenB in the contract.
     */
    function getReserves() public view returns (uint256 reserveA, uint256 reserveB) {
        reserveA = IERC20(tokenA).balanceOf(address(this));
        reserveB = IERC20(tokenB).balanceOf(address(this));
    }

    /**
     * @notice Allows users to add liquidity to the token pair.
     * @param _tokenA Address of the first token in the pair.
     * @param _tokenB Address of the second token in the pair.
     * @param amountADesired Desired amount of token A to add.
     * @param amountBDesired Desired amount of token B to add.
     * @param amountAMin Minimum acceptable amount of token A to add.
     * @param amountBMin Minimum acceptable amount of token B to add.
     * @param to Address where LP tokens will be minted.
     * @param deadline Timestamp by which the transaction must be processed.
     * @return amountA Actual amount of token A added.
     * @return amountB Actual amount of token B added.
     * @return liquidity Amount of LP tokens minted.
     */
    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) validAddress(to) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        if (_tokenA != tokenA || _tokenB != tokenB) revert InvalidToken();
        if (amountADesired == 0 || amountBDesired == 0) revert InvalidLiquidityProvision();

        (uint256 reserveA, uint256 reserveB) = getReserves();
        uint256 _totalSupply = totalSupply();

        (amountA, amountB) = _calculateAndVerifyLiquidityAmounts(
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            reserveA,
            reserveB
        );

        //New helper function to handle LP transfers and minting
        liquidity = _transferAndMintLiquidity(
            _tokenA,
            _tokenB,
            amountA,
            amountB,
            to,
            reserveA,
            reserveB,
            _totalSupply
        );

        emit Mint(msg.sender, amountA, amountB);
    }

    /**
     * @dev Internal function to calculate and verify the optimal amounts for liquidity provision.
     * This helps reduce stack depth in the external addLiquidity function.
     * @param amountADesired Desired amount of token A to add.
     * @param amountBDesired Desired amount of token B to add.
     * @param amountAMin Minimum acceptable amount of token A to add.
     * @param amountBMin Minimum acceptable amount of token B to add.
     * @param reserveA Current reserve of token A.
     * @param reserveB Current reserve of token B.
     * @return amountA_ Actual amount of token A to add.
     * @return amountB_ Actual amount of token B to add.
     */
    function _calculateAndVerifyLiquidityAmounts(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 reserveA,
        uint256 reserveB
    ) private pure returns (uint256 amountA_, uint256 amountB_) {
        if (reserveA == 0 && reserveB == 0) {
            amountA_ = amountADesired;
            amountB_ = amountBDesired;
        } else {
            uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert InvalidLiquidityProvision();
                amountA_ = amountADesired;
                amountB_ = amountBOptimal;
            } else {
                uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
                if (amountAOptimal < amountAMin) revert InvalidLiquidityProvision();
                amountA_ = amountAOptimal;
                amountB_ = amountBDesired;
            }
        }

        if (amountA_ == 0 || amountB_ == 0) revert InvalidLiquidityProvision();
    }

    /**
     * @dev Internal function to handle token transfers and LP token minting during liquidity provision.
     * This further reduces stack depth in the addLiquidity function.
     * @param _tokenA Address of token A.
     * @param _tokenB Address of token B.
     * @param amountA Actual amount of token A to transfer.
     * @param amountB Actual amount of token B to transfer.
     * @param to Address to mint LP tokens to.
     * @param reserveA Current reserve of token A before adding.
     * @param reserveB Current reserve of token B before adding.
     * @param _totalSupply Current total supply of LP tokens.
     * @return liquidity Amount of LP tokens minted.
     */
    function _transferAndMintLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 amountA,
        uint256 amountB,
        address to,
        uint256 reserveA,
        uint256 reserveB,
        uint256 _totalSupply
    ) private returns (uint256 liquidity) {
        TransferHelper.safeTransferFrom(_tokenA, msg.sender, address(this), amountA);
        TransferHelper.safeTransferFrom(_tokenB, msg.sender, address(this), amountB);

        liquidity = _mintLiquidity(to, amountA, amountB, reserveA, reserveB, _totalSupply);
    }


    /**
     * @notice Allows users to remove liquidity from the pool.
     * @param _tokenA Address of the first token in the pair.
     * @param _tokenB Address of the second token in the pair.
     * @param liquidity Amount of LP tokens to burn.
     * @param amountAMin Minimum acceptable amount of token A to receive.
     * @param amountBMin Minimum acceptable amount of token B to receive.
     * @param to Address where the withdrawn tokens will be sent.
     * @param deadline Timestamp by which the transaction must be processed.
     * @return amountA Actual amount of token A received.
     * @return amountB Actual amount of token B received.
     */
    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) validAddress(to) returns (uint256 amountA, uint256 amountB) {
        if (_tokenA != tokenA || _tokenB != tokenB) revert InvalidToken();
        if (liquidity == 0) revert InsufficientLiquidity();

        (uint256 reserveA, uint256 reserveB) = getReserves();
        uint256 _totalSupply = totalSupply();

        amountA = (liquidity * reserveA) / _totalSupply;
        amountB = (liquidity * reserveB) / _totalSupply;

        if (amountA < amountAMin || amountB < amountBMin) revert InsufficientOutputAmount();

        _burn(msg.sender, liquidity);
        TransferHelper.safeTransfer(tokenA, to, amountA);
        TransferHelper.safeTransfer(tokenB, to, amountB);

        emit Burn(msg.sender, amountA, amountB, to);
    }

    /**
     * @notice Swaps an exact amount of an input token for an output token.
     * @param amountIn Amount of input token to swap.
     * @param amountOutMin Minimum acceptable amount of output token to receive.
     * @param path Array containing the input token address and the output token address.
     * @param to Address where the output tokens will be sent.
     * @param deadline Timestamp by which the transaction must be processed.
     * @return amounts Array containing the actual input amount and output amount.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) validAddress(to) returns (uint256[] memory amounts) {
        if (path.length != 2) revert InvalidSwapRoute();

        address inputToken = path[0];
        address outputToken = path[1];

        if ((inputToken != tokenA && inputToken != tokenB) || (outputToken != tokenA && outputToken != tokenB) || (inputToken == outputToken)) {
            revert InvalidToken();
        }

        uint256 amountOut = _performSwap(amountIn, inputToken, outputToken, to);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        if (amountOut < amountOutMin) revert InsufficientOutputAmount();
        emit Swap(msg.sender, amountIn, amountOut, to);
    }

    /**
     * @dev Internal function to handle the core swap logic and token transfers.
     * This helps reduce stack depth in the external swap function.
     * @param amountIn Amount of input token to swap.
     * @param inputToken Address of the input token.
     * @param outputToken Address of the output token.
     * @param to Address where the output tokens will be sent.
     * @return amountOut Calculated amount of output token received.
     */
    function _performSwap(
        uint256 amountIn,
        address inputToken,
        address outputToken,
        address to
    ) private returns (uint256 amountOut) {
        (uint256 reserveIn, uint256 reserveOut) = _getReservesForSwap(inputToken, outputToken);
        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

        TransferHelper.safeTransferFrom(inputToken, msg.sender, address(this), amountIn);
        TransferHelper.safeTransfer(outputToken, to, amountOut);
    }

    /**
     * @notice Returns the price of tokenA in terms of tokenB.
     * @param _tokenA Address of the first token.
     * @param _tokenB Address of the second token.
     * @return price Price of tokenA in terms of tokenB (with 18 decimal places).
     */
    function getPrice(address _tokenA, address _tokenB) external view returns (uint256 price) {
        (uint256 reserveA, uint256 reserveB) = getReserves();
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();

        if (_tokenA == tokenA && _tokenB == tokenB) {
            return (reserveB * 1e18) / reserveA;
        } else if (_tokenA == tokenB && _tokenB == tokenA) {
            return (reserveA * 1e18) / reserveB;
        } else {
            revert InvalidToken();
        }
    }

    /**
     * @notice Calculates the amount of output tokens received for a given input amount.
     * @param amountIn Amount of input token.
     * @param reserveIn Current reserve of the input token.
     * @param reserveOut Current reserve of the output token.
     * @return amountOut Calculated amount of output token to receive.
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;

        amountOut = numerator / denominator;
    }

    /**
     * @dev Internal function to mint liquidity tokens.
     * @param to Address to mint LP tokens to.
     * @param amountA Actual amount of token A added.
     * @param amountB Actual amount of token B added.
     * @param reserveA Current reserve of token A before adding liquidity.
     * @param reserveB Current reserve of token B before adding liquidity.
     * @param _totalSupply Current total supply of LP tokens.
     * @return liquidity Amount of LP tokens minted.
     */
    function _mintLiquidity(
        address to,
        uint256 amountA,
        uint256 amountB,
        uint256 reserveA,
        uint256 reserveB,
        uint256 _totalSupply
    ) internal returns (uint256 liquidity) {
        if (_totalSupply == 0) {
            // PRIMERA LIQUIDEZ:
            liquidity = Math.sqrt(amountA * amountB);
            if (liquidity <= MINIMUM_LIQUIDITY) revert InsufficientLiquidityMinted();

            // Originally: _mint(address(0), MINIMUM_LIQUIDITY); 
            // I simply don't mint this amount to anyone. 
            // The MINIMUM_LIQUIDITY is conceptually "burned" by not being minted.
            liquidity -= MINIMUM_LIQUIDITY; // It is discounted from the total liquidity to be minted
        } else {
            // ADD SUBSEQUENT LIQUIDITY
            liquidity = Math.min(
                (amountA * _totalSupply) / reserveA,
                (amountB * _totalSupply) / reserveB
            );
        }

        if (liquidity == 0) revert InsufficientLiquidityMinted();

        _mint(to, liquidity); // Mint the remaining liquidity to the 'to' address
        return liquidity;
    }

    /**
     * @dev Internal function to get reserves for a swap, validating tokens.
     * @param inputToken The address of the input token.
     * @param outputToken The address of the output token.
     * @return reserveIn The reserve of the input token.
     * @return reserveOut The reserve of the output token.
     */
    function _getReservesForSwap(
        address inputToken,
        address outputToken
    ) private view returns (uint256 reserveIn, uint256 reserveOut) {
        if (inputToken == tokenA && outputToken == tokenB) {
            return (IERC20(tokenA).balanceOf(address(this)), IERC20(tokenB).balanceOf(address(this)));
        } else if (inputToken == tokenB && outputToken == tokenA) {
            return (IERC20(tokenB).balanceOf(address(this)), IERC20(tokenA).balanceOf(address(this)));
        }
        revert InvalidToken();
    }
}