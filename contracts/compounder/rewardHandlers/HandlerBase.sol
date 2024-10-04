// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { IRewardHandler } from "../../interfaces/balancer/IRewardHandler.sol";

/**
 * @title   HandlerBase
 * @author  llama.airforce
 */
contract HandlerBase is IRewardHandler {
    using SafeERC20 for IERC20;
    address public owner;
    address public pendingOwner;
    /// @notice The strategy address
    address public immutable strategy;
    /// @notice The token address to be swapped
    address public immutable tokenIn;
    /// @notice The token to obtain after the swap
    address public immutable tokenOut;

    /// @param _strategy  The strategy address
    /// @param _tokenIn  The token address to be swapped
    /// @param _tokenOut  The token to obtain after the swap
    constructor(
        address _strategy,
        address _tokenIn,
        address _tokenOut
    ) {
        strategy = _strategy;
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
        owner = msg.sender;
    }

    /// @notice Set the pending owner, it requires to call applyPendingOwner to take effect
    /// @param _po  The new owner address
    function setPendingOwner(address _po) external onlyOwner {
        pendingOwner = _po;
    }

    /// @notice Apply the pending owner
    function applyPendingOwner() external onlyOwner {
        require(pendingOwner != address(0), "invalid owner");
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    /// @notice Rescue tokens from the contract, excluding the tokenIn
    /// @param _token  The token address to rescue
    /// @param _to  The address to send the tokens to
    function rescueToken(address _token, address _to) external onlyOwner {
        require(_token != tokenIn, "not allowed");
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_to, _balance);
    }

    /// @notice Sells the tokenIn for the tokenOut
    function sell() external virtual onlyStrategy {}

    modifier onlyOwner() {
        require((msg.sender == owner), "owner only");
        _;
    }

    modifier onlyStrategy() {
        require((msg.sender == strategy), "strategy only");
        _;
    }

    receive() external payable {}
}
