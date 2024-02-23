// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { IBoosterFeeHandler } from "../interfaces/IBoosterFeeHandler.sol";

/**
 * @author Hyperlock
 * @notice Convert CRV to cvxCRV by swapping
 */
contract BoosterFeeHandlerSwap is IBoosterFeeHandler {
    using SafeERC20 for IERC20;

    function sell(address to, uint256 amountIn) external returns (uint256) {
        // TODO:
    }
}
