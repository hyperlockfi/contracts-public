// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "../interfaces/IAuraLocker.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-0.6/access/Ownable.sol";

/**
 * @title   BoosterFeeDistro
 * @author  Hyperlock
 */
contract BoosterFeeDistro is IBoosterFeeDistro, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable cvxCrv;
    address public immutable lockRewards;
    address public immutable stakerRewards;

    uint256 public pendingLockIncentive;
    uint256 public pendingStakerIncentive;
    uint256 public pendingCallIncentive;

    mapping(address => bool) public authorized;

    event SetAuthorized(address user, bool auth);
    event Distribute(uint256 lockIncentive, uint256 stakerIncentive, uint256 callIncentive);

    constructor(address _booster) public {
        address _lockRewards = IDeposit(_booster).lockRewards();
        require(_lockRewards != address(0), "!lockRewards");

        cvxCrv = IDeposit(_booster).cvxCrv();
        lockRewards = _lockRewards;
        stakerRewards = IDeposit(_booster).stakerRewards();

        authorized[_booster] = true;
    }

    function setAuthorized(address user, bool auth) external onlyOwner {
        authorized[user] = auth;
        emit SetAuthorized(user, auth);
    }

    /// @dev Callable by Booster and BoosterV3
    function queueNewRewards(
        uint256 _lockIncentive,
        uint256 _stakerIncentive,
        uint256 _callIncentive
    ) external override {
        require(authorized[msg.sender], "!auth");
        pendingLockIncentive = pendingLockIncentive.add(_lockIncentive);
        pendingStakerIncentive = pendingStakerIncentive.add(_stakerIncentive);
        pendingCallIncentive = pendingCallIncentive.add(_callIncentive);
    }

    function distributeFees() external {
        uint256 lockIncentive = pendingLockIncentive;
        if (lockIncentive > 0) {
            pendingLockIncentive = 0;
            //send lockers' share of cvxCrv to reward contract (vault.strategy)
            IERC20(cvxCrv).safeTransfer(lockRewards, lockIncentive);
        }

        uint256 stakerIncentive = pendingStakerIncentive;
        if (stakerIncentive > 0) {
            pendingStakerIncentive = 0;
            //send stakers's share of cvxCrv to reward contract
            IERC20(cvxCrv).safeApprove(stakerRewards, 0);
            IERC20(cvxCrv).safeApprove(stakerRewards, stakerIncentive);
            IAuraLocker(stakerRewards).queueNewRewards(cvxCrv, stakerIncentive);
        }

        uint256 callIncentive = pendingCallIncentive;
        if (callIncentive > 0 && (lockIncentive > 0 || stakerIncentive > 0)) {
            pendingCallIncentive = 0;
            //send incentives for calling
            IERC20(cvxCrv).safeTransfer(msg.sender, callIncentive);
        }

        emit Distribute(lockIncentive, stakerIncentive, callIncentive);
    }
}
