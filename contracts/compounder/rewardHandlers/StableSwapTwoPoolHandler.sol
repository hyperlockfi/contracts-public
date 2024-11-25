// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts-0.8/utils/math/Math.sol";
import { IPancakeStableSwapTwoPool } from "../../interfaces/IPancakeStableSwapTwoPool.sol";
import { HandlerBase } from "./HandlerBase.sol";

/**
 * @title   StableSwapTwoPoolHandler
 * @author  Hyperlock Finance
 * @notice  Stable swaps handler for uniswap style router.
 */
contract StableSwapTwoPoolHandler is HandlerBase {
    using SafeERC20 for IERC20;

    /// @dev The pancakeStableSwapTwoPool address
    IPancakeStableSwapTwoPool public immutable pancakeStableSwapTwoPool;

    /// @dev The token in index within the stable pool;
    uint256 private tokenInIndex;

    /// @dev The token out index within the stable pool;
    uint256 private tokenOutIndex;

    /// @dev Limit of the amount of tokens to be sold in a single harvest
    uint256 public sellLimit;

    event SetSellLimit(uint256 limit);

    /**
     * @param _strategy The strategy address
     * @param _tokenIn The token address to be swapped
     * @param _tokenOut The token to obtain after the swap
     * @param _pancakeStableSwapTwoPool The stable swap two pool address
     */
    constructor(
        address _strategy,
        address _tokenIn,
        address _tokenOut,
        address _pancakeStableSwapTwoPool
    ) HandlerBase(_strategy, _tokenIn, _tokenOut) {
        pancakeStableSwapTwoPool = IPancakeStableSwapTwoPool(_pancakeStableSwapTwoPool);

        if (pancakeStableSwapTwoPool.coins(0) == _tokenIn) {
            tokenInIndex = 0;
            tokenOutIndex = 1;
        } else {
            tokenOutIndex = 0;
            tokenInIndex = 1;
        }

        require(pancakeStableSwapTwoPool.coins(tokenInIndex) == _tokenIn, "!tokens");
        require(pancakeStableSwapTwoPool.coins(tokenOutIndex) == _tokenOut, "!tokens");
    }

    function setSellLimit(uint256 limit) external onlyOwner {
        sellLimit = limit;
        emit SetSellLimit(limit);
    }

    function _swapTokenInForTokenOut(uint256 _amount) internal {
        pancakeStableSwapTwoPool.exchange(tokenInIndex, tokenOutIndex, _amount, 0);
    }

    /// @notice Set the approvals for the stable pool
    function setApprovals() external {
        IERC20(tokenIn).safeApprove(address(pancakeStableSwapTwoPool), 0);
        IERC20(tokenIn).safeApprove(address(pancakeStableSwapTwoPool), type(uint256).max);
    }

    /// @notice Swap the tokenIn to tokenOut and send it to the strategy
    /// @dev Only strategy can call this function, managge slippage at strategy level
    function sell() external override onlyStrategy {
        uint256 bal = IERC20(tokenIn).balanceOf(address(this));
        uint256 amountIn = sellLimit == 0 ? bal : Math.min(bal, sellLimit);

        _swapTokenInForTokenOut(amountIn);
        IERC20(tokenOut).safeTransfer(strategy, IERC20(tokenOut).balanceOf(address(this)));

        uint256 remianingTokenIn = IERC20(tokenIn).balanceOf(address(this));
        if (remianingTokenIn > 0) {
            IERC20(tokenIn).safeTransfer(strategy, remianingTokenIn);
        }
    }
}
