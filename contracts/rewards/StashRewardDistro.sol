// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { IStashRewardDistro } from "../interfaces/IStashRewardDistro.sol";
import { AuraMath } from "../utils/AuraMath.sol";
import { IBooster } from "../interfaces/IBooster.sol";
import { DistributionParameters } from "../interfaces/merkl/DistributionParameters.sol";
import { IDistributionCreator } from "../interfaces/merkl/IDistributionCreator.sol";

/**
 * @title   StashRewardDistro
 * @author  Aura Finance
 */
contract StashRewardDistro is IStashRewardDistro {
    using AuraMath for uint256;
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------
       Storage
    ------------------------------------------------------------------- */

    // @dev Epoch duration
    uint256 public constant EPOCH_DURATION = 1 weeks;

    // @dev The booster address
    IBooster public immutable booster;

    // @dev The merkl distribution contract
    address public immutable merklDistributionCreator;

    // @dev Epoch => Pool ID => Token => Amount
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) public getFunds;

    /* -------------------------------------------------------------------
       Events
    ------------------------------------------------------------------- */

    event Funded(uint256 epoch, uint256 pid, address token, uint256 amount);
    event Queued(uint256 epoch, uint256 pid, address token, uint256 amount);
    event MerklCampaign(uint256 epoch, address pool, address token, uint256 amount);

    /* -------------------------------------------------------------------
       Constructor
    ------------------------------------------------------------------- */

    /**
     * @param _booster The booster
     * @param _merklDistributionCreator The Merkl Distributor Creator
     */
    constructor(address _booster, address _merklDistributionCreator) {
        booster = IBooster(_booster);
        merklDistributionCreator = _merklDistributionCreator;
        IDistributionCreator(_merklDistributionCreator).acceptConditions();
    }

    /* -------------------------------------------------------------------
       View
    ------------------------------------------------------------------- */

    /**
     * @dev Get the current epoch
     */
    function getCurrentEpoch() external view returns (uint256) {
        return _getCurrentEpoch();
    }

    /* -------------------------------------------------------------------
       Core
    ------------------------------------------------------------------- */

    /**
     * @dev  Fund a pool for the next epoch. Epochs are 1 week in length and run
     *       Thursday to Thursday
     * @param _pid Pool ID
     * @param _token Token address
     * @param _amount Amount of the token to fund in total
     * @param _periods Number of periods to fund
     *                 _amount is split evenly between the number of periods
     */
    function fundPool(
        uint256 _pid,
        address _token,
        uint256 _amount,
        uint256 _periods
    ) external {
        // Loop through n periods and assign rewards to each epoch
        // Add 1 to the epoch so it can only be queued for the next epoch which
        // will be the next thursday. The process will be
        // fundPool is called on tuesday and adds rewards to the next epoch which
        // will start on thursday
        uint256 epoch = _getCurrentEpoch().add(1);
        uint256 epochAmount = _amount.div(_periods);
        for (uint256 i = 0; i < _periods; i++) {
            getFunds[epoch][_pid][_token] = getFunds[epoch][_pid][_token].add(epochAmount);
            emit Funded(epoch, _pid, _token, epochAmount);
            epoch++;
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice Queue the current epoch's rewards to the pid's stash.
     * @param _pid  The pool id to queue rewards.
     * @param _token The reward token.
     */
    function queueRewards(uint256 _pid, address _token) external {
        _queueRewards(_getCurrentEpoch(), _pid, _token);
    }

    /**
     * @notice Queue rewards to the pid's stash
     *  It can only queue past or current epoch's rewards
     * @param _pid  The pool id to queue rewards.
     * @param _token The reward token.
     * @param _epoch The epoch to process.
     */
    function queueRewards(
        uint256 _pid,
        address _token,
        uint256 _epoch
    ) external {
        require(_epoch <= _getCurrentEpoch(), "!epoch");
        _queueRewards(_epoch, _pid, _token);
    }

    function createMerklCampaign(
        address _pool,
        address _token,
        uint256 _amount,
        uint256 _periods
    ) external {
        address[] memory positionWrappers = new address[](1);
        uint32[] memory wrapperTypes = new uint32[](1);

        positionWrappers[0] = booster.staker();
        wrapperTypes[0] = 0;

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        DistributionParameters memory params = DistributionParameters({
            rewardId: bytes32(""),
            uniV3Pool: _pool,
            rewardToken: _token,
            amount: _amount,
            positionWrappers: positionWrappers,
            wrapperTypes: wrapperTypes,
            propToken0: 4500,
            propToken1: 4500,
            propFees: 1000,
            epochStart: uint32(block.timestamp),
            numEpoch: uint32(_periods) * uint32(168), // 1 week (7*24)
            isOutOfRangeIncentivized: 0,
            boostedReward: 0, // 0x boost
            boostingAddress: address(0),
            additionalData: bytes("")
        });

        IERC20(_token).safeIncreaseAllowance(merklDistributionCreator, _amount);
        IDistributionCreator(merklDistributionCreator).createDistribution(params);

        emit MerklCampaign(_getCurrentEpoch(), _pool, _token, _amount);
    }

    /* -------------------------------------------------------------------
       Internal
    ------------------------------------------------------------------- */

    function _queueRewards(
        uint256 _epoch,
        uint256 _pid,
        address _token
    ) internal {
        uint256 amount = getFunds[_epoch][_pid][_token];
        require(amount != 0, "!amount");
        getFunds[_epoch][_pid][_token] = 0;

        IBooster.PoolInfo memory poolInfo = booster.poolInfo(_pid);
        IERC20(_token).safeTransfer(poolInfo.stash, amount);
        emit Queued(_epoch, _pid, _token, amount);
    }

    function _getCurrentEpoch() internal view returns (uint256) {
        return block.timestamp.div(EPOCH_DURATION);
    }
}
