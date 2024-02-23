// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "./interfaces/IProxyFactory.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/utils/Address.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";

/**
 * @title   StashFactoryV2
 * @author  ConvexFinance -> Hyperlock
 * @notice  Factory to deploy reward stash contracts that handle extra rewards
 */
contract StashFactoryV2 {
    using Address for address;

    address public immutable operator;
    address public immutable rewardFactory;
    address public immutable proxyFactory;

    address public implementation;

    event StashCreated(address stash);

    /**
     * @param _operator       Operator is Booster
     * @param _rewardFactory  Factory that creates reward contract that are
     *                        VirtualBalanceRewardPool's used for extra pool rewards
     * @param _proxyFactory   Deploy proxies with stash implementation
     */
    constructor(
        address _operator,
        address _rewardFactory,
        address _proxyFactory
    ) public {
        operator = _operator;
        rewardFactory = _rewardFactory;
        proxyFactory = _proxyFactory;
    }

    function setImplementation(address _implementation) external {
        require(msg.sender == IDeposit(operator).owner(), "!auth");

        implementation = _implementation;
    }

    //Create a stash contract for the given pool.
    function CreateStash(
        uint256 _pid,
        address _gauge,
        address _staker
    ) external returns (address) {
        require(msg.sender == operator, "!authorized");
        require(implementation != address(0), "0 impl");

        address stash = IProxyFactory(proxyFactory).clone(implementation);
        IStash(stash).initialize(_pid, operator, _staker, _gauge, rewardFactory);

        emit StashCreated(stash);
        return stash;
    }
}
