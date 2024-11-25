// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { IERC721 } from "@openzeppelin/contracts-0.6/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts-0.6/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts-0.6/utils/ReentrancyGuard.sol";
import { INfpOps } from "../interfaces/INfpOps.sol";
import { INonfungiblePositionManager } from "../interfaces/INonfungiblePositionManager.sol";
import { INonfungiblePositionManagerStruct } from "../interfaces/INonfungiblePositionManagerStruct.sol";
import { IBooster } from "../interfaces/IBooster.sol";
import { IGauge } from "../interfaces/IGauge.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import "../convex/Interfaces.sol";

contract NfpBooster is Ownable, ReentrancyGuard, INonfungiblePositionManagerStruct {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* --------------------------------------------------------------
     * Type
    -------------------------------------------------------------- */

    struct PositionInfo {
        bytes32 poolKey;
        address owner;
    }

    struct PoolInfo {
        address pool;
        address gauge;
        bool shutdown;
    }

    /* --------------------------------------------------------------
     * Storage
    -------------------------------------------------------------- */

    /// @dev The staker (eg VoterProxy)
    INfpOps public immutable staker;

    IBooster public immutable booster;

    IERC20 public immutable crv;

    IERC20 public immutable cvxCrv;

    INonfungiblePositionManager public immutable nfpManager;

    /// @dev token ID mapped to positionInfo
    mapping(uint256 => PositionInfo) public getPositionInfo;

    /// @dev internal pool key mapped to pool address
    mapping(bytes32 => PoolInfo) public getPoolInfo;

    /* --------------------------------------------------------------
     * Event
    -------------------------------------------------------------- */

    event Deposit(uint256 indexed tokenId, address indexed from, address pool, bytes32 poolKey);
    event Withdraw(uint256 indexed tokenId, address indexed to, address pool, bytes32 poolKey);
    event AddPool(address indexed pool, bytes32 poolKey);
    event ShutdownPool(address indexed pool, bytes32 poolKey);

    /* --------------------------------------------------------------
     * Constructor
    -------------------------------------------------------------- */

    receive() external payable {}

    constructor(
        address _staker,
        address _nfpManager,
        address booster_
    ) public {
        staker = INfpOps(_staker);
        nfpManager = INonfungiblePositionManager(_nfpManager);
        IBooster _booster = IBooster(booster_);
        booster = _booster;

        crv = IERC20(_booster.crv());
        cvxCrv = IERC20(_booster.cvxCrv());
    }

    /* --------------------------------------------------------------
     * Modifiers
    -------------------------------------------------------------- */

    modifier onlyPositionOwner(uint256 _tokenId) {
        require(msg.sender == getPositionInfo[_tokenId].owner, "!positionOwner");
        _;
    }

    /* --------------------------------------------------------------
     * View
    -------------------------------------------------------------- */

    function getPoolKey(address _pool) external view returns (bytes32) {
        address token0 = IUniswapV3Pool(_pool).token0();
        address token1 = IUniswapV3Pool(_pool).token1();
        uint256 fee = IUniswapV3Pool(_pool).fee();

        return _poolKey(token0, token1, fee);
    }

    /* --------------------------------------------------------------
     * Pools
    -------------------------------------------------------------- */

    function addPool(address _pool, address _gauge) external nonReentrant onlyOwner {
        require(IGauge(_gauge).pool() == _pool, "!pool");

        address token0 = IUniswapV3Pool(_pool).token0();
        address token1 = IUniswapV3Pool(_pool).token1();
        uint256 fee = IUniswapV3Pool(_pool).fee();

        bytes32 key = _poolKey(token0, token1, fee);
        PoolInfo storage poolInfo = getPoolInfo[key];

        poolInfo.pool = _pool;
        poolInfo.gauge = _gauge;
        poolInfo.shutdown = false;

        emit AddPool(_pool, key);
    }

    function shutdownPool(bytes32 _key) external onlyOwner {
        getPoolInfo[_key].shutdown = true;

        emit ShutdownPool(getPoolInfo[_key].pool, _key);
    }

    /* --------------------------------------------------------------
     * Deposit/Withdraw
    -------------------------------------------------------------- */

    function deposit(uint256 _tokenId) external nonReentrant {
        (, , address token0, address token1, uint24 fee, , , , , , , ) = nfpManager.positions(_tokenId);
        bytes32 poolKey = _poolKey(token0, token1, fee);

        PoolInfo memory poolInfo = getPoolInfo[poolKey];
        require(!poolInfo.shutdown, "pool shutdown");
        require(poolInfo.pool != address(0), "!pool");

        PositionInfo storage positionInfo = getPositionInfo[_tokenId];
        positionInfo.poolKey = poolKey;
        positionInfo.owner = msg.sender;

        IERC721(nfpManager).safeTransferFrom(msg.sender, address(staker), _tokenId);

        emit Deposit(_tokenId, msg.sender, poolInfo.pool, poolKey);
    }

    function withdraw(uint256 _tokenId, address _to) external nonReentrant onlyPositionOwner(_tokenId) {
        PositionInfo memory positionInfo = getPositionInfo[_tokenId];
        bytes32 poolKey = positionInfo.poolKey;
        PoolInfo memory poolInfo = getPoolInfo[poolKey];

        delete getPositionInfo[_tokenId];

        staker.withdrawPosition(_tokenId, _to);

        emit Withdraw(_tokenId, _to, poolInfo.pool, poolKey);
    }

    /* --------------------------------------------------------------
     * Manage Liquidity
    -------------------------------------------------------------- */

    function collect(CollectParams memory params)
        external
        nonReentrant
        onlyPositionOwner(params.tokenId)
        returns (uint256, uint256)
    {
        require(params.recipient != address(0), "!recipient");
        require(params.recipient != address(this), "!recipient");
        return staker.collect(params);
    }

    /* --------------------------------------------------------------
     * Internal
    -------------------------------------------------------------- */

    function _poolKey(
        address _token0,
        address _token1,
        uint256 _fee
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(_token0, _token1, _fee));
    }
}
