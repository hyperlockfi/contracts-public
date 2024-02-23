// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "./interfaces/IGaugeController.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";

/**
 * @title   PoolManagerV3
 * @author  ConvexFinance
 * @notice  Pool Manager v3
 *          PoolManagerV3 calls addPool on PoolManagerShutdownProxy which calls
 *          addPool on PoolManagerProxy which calls addPool on Booster.
 *          PoolManager-ception
 * @dev     Add pools to the Booster contract
 */
contract PoolManagerV3 {
    using SafeMath for uint256;

    address public immutable gaugeController;
    address public immutable booster;
    address public immutable cvx;
    address public operator;
    bool public isShutdown;

    bool public protectAddPool;

    /**
     * @param _gaugeController  Curve gauge controller e.g: (0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB)
     * @param _operator         Convex multisig
     */
    constructor(
        address _gaugeController,
        address _operator,
        address _booster,
        address _cvx
    ) public {
        gaugeController = _gaugeController;
        operator = _operator;
        protectAddPool = true;
        booster = _booster;
        cvx = _cvx;
    }

    function setOperator(address _operator) external {
        require(msg.sender == operator, "!auth");
        operator = _operator;
    }

    function setExtraReward(uint256 _pid, address _token) external {
        require(msg.sender == operator, "!auth");
        _setExtraReward(_pid, _token);
    }

    function _setExtraReward(uint256 _pid, address _token) internal {
        (, , , , address stash, ) = IDeposit(booster).poolInfo(_pid);
        IStash(stash).setExtraReward(_token);
    }

    /**
     * @notice set if addPool is only callable by operator
     */
    function setProtectPool(bool _protectAddPool) external {
        require(msg.sender == operator, "!auth");
        protectAddPool = _protectAddPool;
    }

    /**
     * @notice Add a new curve pool to the system
     */
    function addPool(address _gauge) external returns (bool) {
        _addPool(_gauge);
        return true;
    }

    function _addPool(address _gauge) internal {
        require(!isShutdown, "shutdown");

        if (protectAddPool) {
            require(msg.sender == operator, "!auth");
        }

        //get lp token from gauge
        address lptoken = ICurveGauge(_gauge).lp_token();

        require(_gauge != address(0), "gauge is 0");
        require(lptoken != address(0), "lp token is 0");

        //check if a pool with this gauge already exists
        bool gaugeExists = IPools(booster).gaugeMap(_gauge);
        require(!gaugeExists, "already registered gauge");

        //must also check that the lp token is not a registered gauge
        //because curve gauges are tokenized
        gaugeExists = IPools(booster).gaugeMap(lptoken);
        require(!gaugeExists, "already registered lptoken");

        uint256 weight = IGaugeController(gaugeController).get_gauge_weight(_gauge);
        require(weight > 0, "must have weight");

        //gauge/lptoken address checks will happen in the next call
        uint256 pid = IDeposit(booster).poolLength();
        IPools(booster).addPool(lptoken, _gauge);
        _setExtraReward(pid, cvx);
    }

    //shutdown pool management and disallow new booster. change is immutable
    function shutdownSystem() external {
        require(msg.sender == operator, "!auth");
        isShutdown = true;
    }

    function shutdownPool(uint256 _pid) external returns (bool) {
        require(msg.sender == operator, "!auth");

        //get pool info
        (address lptoken, address depositToken, , , , bool isshutdown) = IPools(booster).poolInfo(_pid);
        require(!isshutdown, "already shutdown");

        //shutdown pool and get before and after amounts
        uint256 beforeBalance = IERC20(lptoken).balanceOf(booster);
        IPools(booster).shutdownPool(_pid);
        uint256 afterBalance = IERC20(lptoken).balanceOf(booster);

        //check that proper amount of tokens were withdrawn(will also fail if already shutdown)
        require(afterBalance.sub(beforeBalance) >= IERC20(depositToken).totalSupply(), "supply mismatch");

        return true;
    }
}
