// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import { IDeposit, IBoosterFeeDistro } from "./Interfaces.sol";
import { IAuraLocker } from "../interfaces/IAuraLocker.sol";
import { SafeMath } from "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts-0.6/access/Ownable.sol";

/**
 * @title   BoosterFeeDistro
 * @author  Hyperlock Finance
 */
contract BoosterFeeDistro is IBoosterFeeDistro, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable crv;
    address public immutable booster;
    address public immutable lockRewards;
    address public immutable stakerRewards;

    uint256 public pendingLockIncentive;
    uint256 public pendingStakerIncentive;
    uint256 public pendingCallIncentive;

    // @dev Authorized address that can call queueNewRewards
    mapping(address => bool) public authorized;

    /* -------------------------------------------------------------------
       Events
    ------------------------------------------------------------------- */

    event SetAuthorized(address user, bool auth);
    event Distributed(uint256 lockIncentive, uint256 stakerIncentive, uint256 callIncentive);
    event RewardAdded(uint256 lockIncentive, uint256 stakerIncentive, uint256 callIncentive);

    /* -------------------------------------------------------------------
       Constructor
    ------------------------------------------------------------------- */

    /**
     * @param _booster The booster
     */
    constructor(address _booster) public {
        address _lockRewards = IDeposit(_booster).lockRewards();
        require(_lockRewards != address(0), "!lockRewards");

        crv = IDeposit(_booster).crv();
        booster = _booster;
        lockRewards = _lockRewards;
        stakerRewards = IDeposit(_booster).stakerRewards();

        authorized[_booster] = true;
        emit SetAuthorized(_booster, true);
    }

    /**
     * Allows contract owner to authorized a given user to call queueNewRewards.
     * @param user The address to authorize.
     * @param auth Whether the user is authorized or not.
     */
    function setAuthorized(address user, bool auth) external onlyOwner {
        authorized[user] = auth;
        emit SetAuthorized(user, auth);
    }

    /**
     * @dev Called by the booster to allocate new Crv rewards.
     */
    function queueNewRewards(
        uint256 _lockIncentive,
        uint256 _stakerIncentive,
        uint256 _callIncentive
    ) external override {
        require(authorized[msg.sender], "!auth");
        pendingLockIncentive = pendingLockIncentive.add(_lockIncentive);
        pendingStakerIncentive = pendingStakerIncentive.add(_stakerIncentive);
        pendingCallIncentive = pendingCallIncentive.add(_callIncentive);

        emit RewardAdded(_lockIncentive, _stakerIncentive, _callIncentive);
    }

    /**
     * @dev Distribute pending fees to lockRewards and stakerRewards, additionally it transfers callIncentive to the caller.
     */
    function distributeFees() external {
        uint256 lockIncentive = pendingLockIncentive;
        if (lockIncentive > 0) {
            pendingLockIncentive = 0;
            //send lockers' share of crv to reward contract (vault.strategy)
            IERC20(crv).safeTransfer(lockRewards, lockIncentive);
        }

        uint256 stakerIncentive = pendingStakerIncentive;
        if (stakerIncentive > 0) {
            pendingStakerIncentive = 0;
            //send stakers's share of crv to reward contract
            IERC20(crv).safeApprove(stakerRewards, 0);
            IERC20(crv).safeApprove(stakerRewards, stakerIncentive);
            IAuraLocker(stakerRewards).queueNewRewards(crv, stakerIncentive);
        }

        uint256 callIncentive = pendingCallIncentive;
        if (callIncentive > 0 && (lockIncentive > 0 || stakerIncentive > 0)) {
            pendingCallIncentive = 0;
            //send incentives for calling
            IERC20(crv).safeTransfer(msg.sender, callIncentive);
        }

        emit Distributed(lockIncentive, stakerIncentive, callIncentive);
    }

    /**
     *  @dev It calculates the delta between the crv balance and the the total pending incentives
     */
    function skimmableIncentive() public view returns (uint256) {
        uint256 bal = IERC20(crv).balanceOf(address(this));
        uint256 totalPending = pendingLockIncentive.add(pendingStakerIncentive).add(pendingCallIncentive);
        return bal.sub(totalPending);
    }

    /**
     * @dev As this contract can receive CRV directly from other sources .i.e Merkle. It calculates the amount of skimmable incentives
     * for locking, staking, and earmarking then these incentives are then added to the pending incentive variables.
     */
    function skim() external {
        uint256 skimmable = skimmableIncentive();
        if (skimmable > 0) {
            uint256 lockIncentive = IDeposit(booster).lockIncentive();
            uint256 stakerIncentive = IDeposit(booster).stakerIncentive();
            uint256 earmarkIncentive = IDeposit(booster).earmarkIncentive();
            uint256 totalIncentive = lockIncentive.add(stakerIncentive).add(earmarkIncentive);

            pendingLockIncentive = pendingLockIncentive.add(skimmable.mul(lockIncentive).div(totalIncentive));
            pendingStakerIncentive = pendingStakerIncentive.add(skimmable.mul(stakerIncentive).div(totalIncentive));
            pendingCallIncentive = pendingCallIncentive.add(skimmable.mul(earmarkIncentive).div(totalIncentive));
        }
    }
}
