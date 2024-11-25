// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts-0.8/utils/math/Math.sol";
import { IUniswapV3SwapRouter } from "../../interfaces/IUniswapV3SwapRouter.sol";
import { HandlerBase } from "./HandlerBase.sol";

/**
 * @title   UniswapV3SwapHandler
 * @author  AuraFinance
 * @notice  Single swaps handler for uniswap v3 router.
 */
contract UniswapV3SwapHandler is HandlerBase {
    using SafeERC20 for IERC20;

    /// @dev The uniswapV3Router address
    IUniswapV3SwapRouter public immutable uniswapV3Router;

    /// @dev The uniswap pool fee tier, ie 500 = 0.05%
    uint24 public immutable poolFee;

    /// @dev Limit of the amount of tokens to be sold in a single harvest
    uint256 public sellLimit;

    event SetSellLimit(uint256 limit);

    /**
     * @param _strategy The strategy address
     * @param _tokenIn The token address to be swapped
     * @param _tokenOut The token to obtain after the swap
     * @param _uniswapV3Router The Uniswap V3 swap router address
     * @param _poolFee  The uniswap pool fee tier, ie 500 = 0.05%
     */
    constructor(
        address _strategy,
        address _tokenIn,
        address _tokenOut,
        address _uniswapV3Router,
        uint24 _poolFee
    ) HandlerBase(_strategy, _tokenIn, _tokenOut) {
        uniswapV3Router = IUniswapV3SwapRouter(_uniswapV3Router);
        poolFee = _poolFee;
    }

    function setSellLimit(uint256 limit) external onlyOwner {
        sellLimit = limit;
        emit SetSellLimit(limit);
    }

    function _swapTokenInForTokenOut(uint256 _amount) internal {
        // The strategy can set the min out or revert the tx if needed
        IUniswapV3SwapRouter.ExactInputSingleParams memory params = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp + 1,
            amountIn: _amount,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        uniswapV3Router.exactInputSingle(params);
    }

    /// @notice Set the approvals for the uniswap router
    function setApprovals() external {
        IERC20(tokenIn).safeApprove(address(uniswapV3Router), 0);
        IERC20(tokenIn).safeApprove(address(uniswapV3Router), type(uint256).max);
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
