// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/// @title PancakeStableSwapTwoPool
interface IPancakeStableSwapTwoPool {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy
    ) external payable;

    function coins(uint256 index) external returns (address);
}
