// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IStashRewardDistro {
    function fundPool(
        uint256 pid,
        address token,
        uint256 amount,
        uint256 period
    ) external;

    function createMerklCampaign(
        address pool,
        address token,
        uint256 amount,
        uint256 periods
    ) external;
}
