// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts-0.8/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { IBooster } from "../interfaces/IBooster.sol";
import { IStashRewardDistro } from "../interfaces/IStashRewardDistro.sol";
import { AuraMath } from "../utils/AuraMath.sol";
import { INfpBooster } from "../interfaces/INfpBooster.sol";
import { IAuraToken } from "../interfaces/IAuraToken.sol";

/**
 * @title   GaugeVoter
 * @author  Aura Finance
 * @notice  Distribute AURA rewards to each gauge that receives voting weight
 *          for a given epoch.
 *
 *          Gauges receiving votes fall into 3 categories that we need to deal with:
 *          1.  Liquidity gauges with pools on Booster
 *          2.  Merkl gauges with pools on nfpBooster, make sure Merkl has
 *              whitelisted crv token as reward token.
 *          3.  Gauge that don't take deposits and are not supported by AURA eg veBAL
 *
 *          The process for setting up this contract is:
 *          1.  setRewardPerEpoch(...)
 *          2.  setPoolIds([0...poolLength])
 *          3.  setPoolKeys(0x...)
 *          4.  setIsNoDepositGauge(veBAL, veLIT, ...)
 *
 *          The process for each voting epoch (2 weeks) is:
 *          1.  voteGaugeWeight is called with the gauges and weights
 *          2.  processGaugeRewards is called to distribute AURA to the reward distro
 *              for each gauge
 */
contract GaugeVoter is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IAuraToken;
    using AuraMath for uint256;

    /* -------------------------------------------------------------------
       Types
    ------------------------------------------------------------------- */

    struct Pid {
        uint128 value;
        bool isSet;
    }

    struct Key {
        address pool;
        bool isSet;
    }

    /* -------------------------------------------------------------------
       Storage
    ------------------------------------------------------------------- */

    /// @dev Total vote weight per epoch
    uint256 public constant TOTAL_WEIGHT_PER_EPOCH = 10_000;

    /// @dev Epoch duration
    uint256 public constant EPOCH_DURATION = 2 weeks;

    /// @dev Aura token address
    IAuraToken public immutable aura;

    /// @dev The Booster contract address
    IBooster public immutable booster;

    /// @dev The NFP Booster contract address
    INfpBooster public immutable nfpBooster;

    /// @dev Extra reward distro contract
    IStashRewardDistro public stashRewardDistro;

    /// @dev How much total reward per epoch
    uint256 public rewardPerEpoch;

    /// @dev Distributor address
    address public distributor;

    /// @dev Gauge => Pool ID
    mapping(address => Pid) public getPoolId;

    /// @dev Gauge => Key
    mapping(address => Key) public getPoolKey;

    /// @dev Epoch => Gauge => Weight
    mapping(uint256 => mapping(address => uint256)) public getWeightByEpoch;

    /// @dev Epoch => Gauge => Has been processed
    mapping(uint256 => mapping(address => bool)) public isProcessed;

    /// @dev Gauge => Is a no deposit gauge like veBAL
    mapping(address => bool) public isNoDepositGauge;

    /// @dev Epoch => total weight
    mapping(uint256 => uint256) public getTotalWeight;

    /* -------------------------------------------------------------------
       Events
    ------------------------------------------------------------------- */

    event SetStashRewardDistro(address stashRewardDistro);
    event SetDistributor(address distributor);
    event SetRewardPerEpoch(uint256 rewardPerEpoch);
    event SetIsNoDepositGauge(address gauge, bool isNoDeposit);
    event ProcessGaugeRewards(address[] gauge, uint256 epoch);
    event GaugeVoterMint(uint256 minted);

    /* -------------------------------------------------------------------
       Constructor
    ------------------------------------------------------------------- */

    /**
     * @param _aura Aura token
     * @param _booster Booster contract
     * @param _nfpBooster The NFP Booster contract
     * @param _stashRewardDistro Stash reward distro
     */
    constructor(
        address _aura,
        address _booster,
        address _nfpBooster,
        address _stashRewardDistro
    ) {
        aura = IAuraToken(_aura);
        booster = IBooster(_booster);
        nfpBooster = INfpBooster(_nfpBooster);
        _setStashRewardDistro(_stashRewardDistro);
    }

    /* -------------------------------------------------------------------
       Modifiers
    ------------------------------------------------------------------- */

    modifier onlyDistributor() {
        require(msg.sender == distributor, "!distributor");
        _;
    }

    /* -------------------------------------------------------------------
       Setters
    ------------------------------------------------------------------- */
    function _setStashRewardDistro(address _stashRewardDistro) private {
        stashRewardDistro = IStashRewardDistro(_stashRewardDistro);
        aura.safeApprove(_stashRewardDistro, 0);
        aura.safeApprove(_stashRewardDistro, type(uint256).max);

        emit SetStashRewardDistro(_stashRewardDistro);
    }

    /**
     * @dev Set the stash reward distro and approve it to spend aura.
     * @param _stashRewardDistro The distributor account
     */
    function setStashRewardDistro(address _stashRewardDistro) external onlyOwner {
        _setStashRewardDistro(_stashRewardDistro);
    }

    /**
     * @dev Set distributor who can process rewards
     * @param _distributor The distributor account
     */
    function setDistributor(address _distributor) external onlyOwner {
        distributor = _distributor;
        emit SetDistributor(_distributor);
    }

    /**
     * @dev Set if a gauge does not take deposits eg veBAL, veLIT etc
     * @param _gauge Gauge address
     * @param _isNoDeposit If it is a no deposit gauge
     */
    function setIsNoDepositGauge(address _gauge, bool _isNoDeposit) external onlyOwner {
        isNoDepositGauge[_gauge] = _isNoDeposit;
        emit SetIsNoDepositGauge(_gauge, _isNoDeposit);
    }

    /**
     * @dev Loop through the booster pools and configure each one
     * @param start The start index
     * @param end The end index
     */
    function setPoolIds(uint256 start, uint256 end) external {
        for (uint256 i = start; i < end; i++) {
            IBooster.PoolInfo memory poolInfo = booster.poolInfo(i);
            getPoolId[poolInfo.gauge] = Pid(uint128(i), true);
        }
    }

    /**
     * @dev Lookup a pool key on the nfpBooster and add it to the mapping
     * @param _key THe pool key
     */
    function setPoolKeys(bytes32 _key) external {
        (address pool, address gauge, ) = nfpBooster.getPoolInfo(_key);
        require(gauge != address(0), "!key");
        getPoolKey[gauge] = Key(pool, true);
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

    /**
     * @dev Get amount to send for each gauge by epoch
     * @param _epoch Epoch
     * @param _gauge The gauge address
     * @return Amount to send
     */
    function getAmountToSendByEpoch(uint256 _epoch, address _gauge) external view returns (uint256) {
        return _getAmountToSend(_epoch, _gauge);
    }

    /* -------------------------------------------------------------------
       Core
    ------------------------------------------------------------------- */

    function gaugeVoterMint() external {
        uint256 balBefore = aura.balanceOf(address(this));
        aura.gaugeVoterMint();
        uint256 balAfter = aura.balanceOf(address(this));
        uint256 minted = balAfter - balBefore;

        if (minted > 0) {
            rewardPerEpoch = minted;
            emit SetRewardPerEpoch(rewardPerEpoch);
        }

        emit GaugeVoterMint(minted);
    }

    /**
     * @notice  Wraps the booster.voteGaugeWeight call to track weights for each epoch
     *          So AURA rewards can be distributed pro rata to those pool stashes
     * @param _gauge    Array of the gauges
     * @param _weight   Array of the weights
     * @return bool for success
     */
    function voteGaugeWeight(address[] calldata _gauge, uint256[] calldata _weight) external onlyOwner returns (bool) {
        uint256 totalWeight = 0;
        uint256 totalDepositWeight = 0;
        uint256 epoch = _getCurrentEpoch();
        uint256 gaugeLen = _gauge.length;

        require(rewardPerEpoch > 0, "!rewardPerEpoch");
        require(gaugeLen == _weight.length, "!length");
        require(getTotalWeight[epoch] == 0, "already voted");

        // Loop through each gauge and store it's weight for this epoch, while
        // tracking totalWeights that is used for validation and totalDepositsWeight
        // which is used later to calculate pro rata rewards
        for (uint256 i = 0; i < gaugeLen; i++) {
            address gauge = _gauge[i];
            uint256 weight = _weight[i];

            totalWeight = totalWeight.add(weight);

            // Some gauges like veBAL have no deposits so we just skip
            // those special cases
            if (isNoDepositGauge[gauge]) continue;

            getWeightByEpoch[epoch][gauge] = weight;
            totalDepositWeight = totalDepositWeight.add(weight);
        }

        // Update the total weight for this epoch
        getTotalWeight[epoch] = totalDepositWeight;

        // Check that the total weight (inclusive of no deposit gauges)
        // reaches 10,000 which is the total vote weight as defined in
        // the GaugeController
        require(totalWeight == TOTAL_WEIGHT_PER_EPOCH, "!totalWeight");

        // Forward the gauge vote to the booster
        return booster.voteGaugeWeight(_gauge, _weight);
    }

    /**
     * @notice Process gauge rewards for the given epoch for mainnet
     * @param _gauge Array of gauges
     * @param _epoch The epoch
     */
    function processGaugeRewards(uint256 _epoch, address[] calldata _gauge) external onlyDistributor {
        require(_epoch <= _getCurrentEpoch(), "!epoch");

        for (uint256 i = 0; i < _gauge.length; i++) {
            address gauge = _gauge[i];

            // Some gauges could be marked as not deposit gauges
            require(!isNoDepositGauge[gauge], "noDepositGauge");

            uint256 amountToSend = _calculateAmountToSend(_epoch, gauge);

            // Fund the extra reward distro for the next 2 epochs
            Pid memory pid = getPoolId[gauge];
            if (pid.isSet) {
                // This is a Booster pool
                stashRewardDistro.fundPool(uint256(pid.value), address(aura), amountToSend, 2);
            } else {
                // Check if it is a NfpBooster pool
                Key memory key = getPoolKey[gauge];
                require(key.isSet, "!key");
                // Fund the pool via merkl
                stashRewardDistro.createMerklCampaign(key.pool, address(aura), amountToSend, 2);
            }
        }

        emit ProcessGaugeRewards(_gauge, _epoch);
    }

    /* -------------------------------------------------------------------
       Utils
    ------------------------------------------------------------------- */

    /**
     * @dev Transfer ERC20
     * @param _token The token address
     * @param _to Address to transfer tokens to
     * @param _amount Amount of tokens to send
     */
    function transferERC20(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /* -------------------------------------------------------------------
       Internal
    ------------------------------------------------------------------- */

    function _getAmountToSend(uint256 _epoch, address _gauge) internal view returns (uint256) {
        // Send pro rata AURA to the sidechain
        uint256 weight = getWeightByEpoch[_epoch][_gauge];
        uint256 amountToSend = rewardPerEpoch.mul(weight).div(getTotalWeight[_epoch]);
        return amountToSend;
    }

    function _calculateAmountToSend(uint256 _epoch, address _gauge) internal returns (uint256) {
        // Send pro rata AURA to the sidechain
        uint256 amountToSend = _getAmountToSend(_epoch, _gauge);
        require(amountToSend != 0, "amountToSend=0");

        // Prevent amounts from being sent multiple times
        require(!isProcessed[_epoch][_gauge], "isProcessed");
        isProcessed[_epoch][_gauge] = true;

        return amountToSend;
    }

    function _getCurrentEpoch() internal view returns (uint256) {
        return block.timestamp.div(EPOCH_DURATION);
    }
}
