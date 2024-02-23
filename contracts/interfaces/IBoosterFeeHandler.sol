// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface IBoosterFeeHandler {
    function sell(address to, uint256 amountIn) external returns (uint256);
}
