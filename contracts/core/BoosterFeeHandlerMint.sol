// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { IBoosterFeeHandler } from "../interfaces/IBoosterFeeHandler.sol";
import { ICrvDepositor } from "../interfaces/ICrvDepositor.sol";

/**
 * @author Hyperlock
 * @notice Convert CRV to cvxCRV by depositing into crvDepositor
 */
contract BoosterFeeHandlerMint is IBoosterFeeHandler {
    using SafeERC20 for IERC20;

    address public immutable crv;
    address public immutable crvDepositor;

    constructor(address _crv, address _crvDepositor) {
        crv = _crv;
        crvDepositor = _crvDepositor;
    }

    function sell(address to, uint256 amountIn) external returns (uint256) {
        IERC20(crv).safeApprove(crvDepositor, 0);
        IERC20(crv).safeApprove(crvDepositor, amountIn);
        ICrvDepositor(crvDepositor).depositFor(to, amountIn, true, address(0));
        // CrvDepositor mints CRV:cvxCRV 1:1 so amountIn == amountOut
        return amountIn;
    }
}
