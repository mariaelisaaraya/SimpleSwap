// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title SimpleSwap - A simplified Uniswap-like token swap implementation
 * @dev Implements core swap functionality, liquidity provision, and price calculations
 */
contract SimpleSwap is ERC20 {
    // Struct to hold reserve amounts 
    struct Reserves {
        uint256 reserveA;
        uint256 reserveB;
    }
    
    // Struct for liquidity provision parameters
    struct LiquidityParams {
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
    }
    
    // Struct for swap parameters
    struct SwapData {
        uint256 amountIn;
        uint256 amountOut;
        address inputToken;
        address outputToken;
    }

    // Immutable token addresses for the pair 
    address public immutable tokenA;
    address public immutable tokenB;
    
    // Constants
    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    // Events
    event Mint(address indexed sender, uint256 amountA, uint256 amountB);
    event Burn(address indexed sender, uint256 amountA, uint256 amountB, address indexed to);
    event Swap(address indexed sender, uint256 amountIn, uint256 amountOut, address indexed to);

    // Errors
    error InsufficientLiquidity();
    error InvalidToken();
    error InvalidAddress();
    error InsufficientOutputAmount();
    error InvalidLiquidityProvision();
    error DeadlineExpired();
    error InvalidSwapRoute();
    error InsufficientLiquidityMinted();
    error InsufficientBAmount();
    error InsufficientAAmount();
    error TransferFailed();
    error TransferFromFailed();
    error InvalidConstructorArguments();

    // Modifiers
    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlineExpired();
        _;
    }

    modifier validAddress(address to) {
        if (to == address(0) || to == address(this)) revert InvalidAddress();
        _;
    }

    /**
     * @dev Initializes the contract with the token pair
     * @param _tokenA Address of the first token in the pair
     * @param _tokenB Address of the second token in the pair
     */
    constructor(address _tokenA, address _tokenB) ERC20("SimpleSwap LP Token", "SS-LP") {
        // Validation for constructor inputs
        if (_tokenA == address(0) || _tokenB == address(0) || _tokenA == _tokenB) {
            revert InvalidConstructorArguments();
        }
        // Assigning directly to immutable address variables
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    /**
     * @notice Adds liquidity to the token pair
     * @dev Implements requirement 1 from TP
     */
    function addLiquidity(
        address _tokenA_param, 
        address _tokenB_param, 
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) validAddress(to) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // Validate that the provided tokens match the immutable pair
        if (_tokenA_param != tokenA || _tokenB_param != tokenB) revert InvalidToken();
        return _addLiquidity(
            LiquidityParams(amountADesired, amountBDesired, amountAMin, amountBMin),
            to
        );
    }

    /**
     * @notice Removes liquidity from the token pair
     */
    function removeLiquidity(
        address _tokenA_param, 
        address _tokenB_param, 
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) validAddress(to) returns (uint256 amountA, uint256 amountB) {
        // Validate that the provided tokens match the immutable pair
        if (_tokenA_param != tokenA || _tokenB_param != tokenB) revert InvalidToken();
        return _removeLiquidity(liquidity, amountAMin, amountBMin, to);
    }

    /**
     * @notice Swaps an exact amount of tokens for another token
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) validAddress(to) returns (uint256[] memory amounts) {
        return _swapExactTokensForTokens(amountIn, amountOutMin, path, to);
    }

    /**
     * @notice Gets the price of one token in terms of the other
     */
    function getPrice(address _tokenA, address _tokenB) external view returns (uint256 price) {
        return _getPrice(_tokenA, _tokenB);
    }

    /**
     * @notice Calculates the amount of output tokens for a given input
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut) {
        return _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /**
     * @dev Internal implementation of addLiquidity
     */
    function _addLiquidity(
        LiquidityParams memory params,
        address to
    ) internal returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        if (params.amountADesired == 0 || params.amountBDesired == 0) revert InvalidLiquidityProvision();

        Reserves memory reserves = _getReserves();
        uint256 _totalSupply = totalSupply();

        (amountA, amountB) = _calculateLiquidityAmounts(params, reserves);
        liquidity = _mintNewLiquidity(to, amountA, amountB, reserves, _totalSupply);

        // Using the immutable token addresses directly
        _safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        _safeTransferFrom(tokenB, msg.sender, address(this), amountB);
        emit Mint(msg.sender, amountA, amountB);
    }

    /**
     * @dev Internal implementation of removeLiquidity
     */
    function _removeLiquidity(
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (liquidity == 0) revert InsufficientLiquidity();

        Reserves memory reserves = _getReserves();
        uint256 _totalSupply = totalSupply();

        (amountA, amountB) = _calculateWithdrawalAmounts(liquidity, reserves, _totalSupply);
        _validateWithdrawalAmounts(amountA, amountB, amountAMin, amountBMin);

        _burn(msg.sender, liquidity);
        // Using the immutable token addresses directly
        _transferWithdrawnTokens(tokenA, tokenB, amountA, amountB, to);

        emit Burn(msg.sender, amountA, amountB, to);
    }

    /**
     * @dev Internal implementation of swapExactTokensForTokens
     */
    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) internal returns (uint256[] memory amounts) {
        if (path.length != 2) revert InvalidSwapRoute();

        address inputToken = path[0];
        address outputToken = path[1];
        _validateSwapTokens(inputToken, outputToken);

        SwapData memory swapData = SwapData(amountIn, 0, inputToken, outputToken);
        swapData.amountOut = _executeSwap(swapData, to);

        amounts = new uint256[](2);
        amounts[0] = swapData.amountIn;
        amounts[1] = swapData.amountOut;

        if (swapData.amountOut < amountOutMin) revert InsufficientOutputAmount();
        emit Swap(msg.sender, swapData.amountIn, swapData.amountOut, to);
    }

    /**
     * @dev Gets current reserves of both tokens
     */
    function _getReserves() internal view returns (Reserves memory) {
        return Reserves(
            IERC20(tokenA).balanceOf(address(this)), // Using immutable tokenA
            IERC20(tokenB).balanceOf(address(this))  // Using immutable tokenB
        );
    }

    /**
     * @dev Validates that provided tokens match the pair
     */
    function _validateTokens(address _tokenA_param, address _tokenB_param) internal view {
        if (_tokenA_param != tokenA || _tokenB_param != tokenB) revert InvalidToken();
    }

    /**
     * @dev Calculates optimal liquidity amounts
     */
    function _calculateLiquidityAmounts(
        LiquidityParams memory params,
        Reserves memory reserves
    ) internal pure returns (uint256 amountA, uint256 amountB) {
        if (reserves.reserveA == 0 && reserves.reserveB == 0) {
            return (params.amountADesired, params.amountBDesired);
        }

        uint256 amountBOptimal = (params.amountADesired * reserves.reserveB) / reserves.reserveA;
        if (amountBOptimal <= params.amountBDesired) {
            if (amountBOptimal < params.amountBMin) revert InsufficientBAmount();
            return (params.amountADesired, amountBOptimal);
        }

        uint256 amountAOptimal = (params.amountBDesired * reserves.reserveA) / reserves.reserveB;
        if (amountAOptimal < params.amountAMin) revert InsufficientAAmount();
        return (amountAOptimal, params.amountBDesired);
    }

    /**
     * @dev Mints new liquidity tokens
     */
    function _mintNewLiquidity(
        address to,
        uint256 amountA,
        uint256 amountB,
        Reserves memory reserves,
        uint256 _totalSupply
    ) internal returns (uint256 liquidity) {
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            if (liquidity <= 0) revert InsufficientLiquidityMinted();
        } else {
            liquidity = Math.min(
                (amountA * _totalSupply) / reserves.reserveA,
                (amountB * _totalSupply) / reserves.reserveB
            );
        }
        _mint(to, liquidity);
    }

    /**
     * @dev Transfers tokens for liquidity provision
     */
    function _transferTokensForLiquidity(
        address _tokenA_param,
        address _tokenB_param,
        uint256 amountA,
        uint256 amountB
    ) internal {
        _safeTransferFrom(_tokenA_param, msg.sender, address(this), amountA);
        _safeTransferFrom(_tokenB_param, msg.sender, address(this), amountB);
    }

    /**
     * @dev Calculates withdrawal amounts
     */
    function _calculateWithdrawalAmounts(
        uint256 liquidity,
        Reserves memory reserves,
        uint256 _totalSupply
    ) internal pure returns (uint256 amountA, uint256 amountB) {
        amountA = (liquidity * reserves.reserveA) / _totalSupply;
        amountB = (liquidity * reserves.reserveB) / _totalSupply;
    }

    /**
     * @dev Validates withdrawal amounts against minimums
     */
    function _validateWithdrawalAmounts(
        uint256 amountA,
        uint256 amountB,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal pure {
        if (amountA < amountAMin || amountB < amountBMin) revert InsufficientOutputAmount();
    }

    /**
     * @dev Transfers withdrawn tokens to recipient
     */
    function _transferWithdrawnTokens(
        address _tokenA_param,
        address _tokenB_param,
        uint256 amountA,
        uint256 amountB,
        address to
    ) internal {
        _safeTransfer(_tokenA_param, to, amountA);
        _safeTransfer(_tokenB_param, to, amountB);
    }

    /**
     * @dev Validates swap token addresses 
     */
    function _validateSwapTokens(address inputToken, address outputToken) internal view {
        bool validInput = (inputToken == tokenA || inputToken == tokenB);
        bool validOutput = (outputToken == tokenA || outputToken == tokenB);
        if (!validInput || !validOutput || inputToken == outputToken) {
            revert InvalidToken();
        }
    }

    /**
     * @dev Executes the token swap
     */
    function _executeSwap(
        SwapData memory swapData,
        address to
    ) internal returns (uint256 amountOut) {
        Reserves memory reserves = _getReservesForSwap(swapData.inputToken, swapData.outputToken);
        amountOut = _getAmountOut(swapData.amountIn, reserves.reserveA, reserves.reserveB);

        _safeTransferFrom(swapData.inputToken, msg.sender, address(this), swapData.amountIn);
        _safeTransfer(swapData.outputToken, to, amountOut);
    }

    /**
     * @dev Gets reserves for swap based on token order 
     */
    function _getReservesForSwap(
        address inputToken,
        address outputToken
    ) internal view returns (Reserves memory) {
        if (inputToken == tokenA && outputToken == tokenB) {
            return _getReserves();
        }
        Reserves memory reserves = _getReserves();
        return Reserves(reserves.reserveB, reserves.reserveA);
    }

    /**
     * @dev Internal price calculation 
     */
    function _getPrice(address _tokenA_param, address _tokenB_param) internal view returns (uint256 price) {
        Reserves memory reserves = _getReserves();
        if (reserves.reserveA == 0 || reserves.reserveB == 0) revert InsufficientLiquidity();

        if (_tokenA_param == tokenA && _tokenB_param == tokenB) {
            return (reserves.reserveB * 1e18) / reserves.reserveA;
        } else if (_tokenA_param == tokenB && _tokenB_param == tokenA) {
            return (reserves.reserveA * 1e18) / reserves.reserveB;
        } else {
            revert InvalidToken();
        }
    }

    /**
     * @dev Internal amount out calculation
     */
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        if (amountIn == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;

        amountOut = numerator / denominator;
    }

    /**
     * @dev Safe ERC20 transfer helper
     */
    function _safeTransfer(
        address _token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        if (!(success && (data.length == 0 || abi.decode(data, (bool))))) revert TransferFailed();
    }

    /**
     * @dev Safe ERC20 transferFrom helper
     */
    function _safeTransferFrom(
        address _token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value)
        );
        if (!(success && (data.length == 0 || abi.decode(data, (bool))))) revert TransferFromFailed();
    }
}