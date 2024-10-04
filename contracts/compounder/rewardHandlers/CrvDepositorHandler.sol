// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { ICrvDepositor } from "../../interfaces/ICrvDepositor.sol";
import { HandlerBase } from "./HandlerBase.sol";

/**
 * @title   CrvDepositorHandler
 * @author  Hyperlock Finance
 * @notice  Stable swaps handler for uniswap style router.
 */
contract CrvDepositorHandler is HandlerBase {
    using SafeERC20 for IERC20;

    /// @dev The crvDepositor address
    ICrvDepositor public immutable crvDepositor;

    /**
     * @param _strategy The strategy address
     * @param _crv The token address to be swapped
     * @param _cvxCrv The token to obtain after the swap
     * @param _crvDepositor The  crvDepositor address
     */
    constructor(
        address _strategy,
        address _crv,
        address _cvxCrv,
        address _crvDepositor
    ) HandlerBase(_strategy, _crv, _cvxCrv) {
        crvDepositor = ICrvDepositor(_crvDepositor);
    }

    /// @notice Set the approvals for crvDepositor
    function setApprovals() external {
        IERC20(tokenIn).safeApprove(address(crvDepositor), 0);
        IERC20(tokenIn).safeApprove(address(crvDepositor), type(uint256).max);
    }

    /// @notice Swap crv for cvxCrv by calling crvDepositor, sends cvxCrv to strategy
    /// @dev Only strategy can call this function, managge slippage at strategy level
    function sell() external override onlyStrategy {
        uint256 _amount = IERC20(tokenIn).balanceOf(address(this));
        crvDepositor.depositFor(address(this), _amount, false, address(0));
        IERC20(tokenOut).safeTransfer(strategy, IERC20(tokenOut).balanceOf(address(this)));
    }
}
