// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./VirtualBalanceRewardPool.sol";
import "@openzeppelin/contracts-0.6/proxy/Clones.sol";

/**
 * @title   VirtualRewardFacotry
 * @author  Aura Finance
 */
contract VirtualRewardFactory {
    address immutable implementation;

    constructor(address _implementation) public {
        implementation = _implementation;
    }

    function createVirtualReward(
        address _deposits,
        address _reward,
        address _operator
    ) external returns (address) {
        VirtualBalanceRewardPool rewardPool = VirtualBalanceRewardPool(Clones.clone(implementation));
        rewardPool.init(_deposits, _reward, _operator);
        return address(rewardPool);
    }
}
