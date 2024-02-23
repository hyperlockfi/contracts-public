// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts-0.6/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import { ERC721 } from "@openzeppelin/contracts-0.6/token/ERC721/ERC721.sol";
import { INonfungiblePositionManager } from "../interfaces/INonfungiblePositionManager.sol";
import { INonfungiblePositionManagerStruct } from "../interfaces/INonfungiblePositionManagerStruct.sol";
import { PoolAddress } from "../thruster/PoolAddress.sol";

interface IPoints {
    function pools(address _pool) external view returns (bool);
}

/**
 * @author  Hyperlock Finance
 */
contract PointsDeposits is Ownable, INonfungiblePositionManagerStruct {
    /* -------------------------------------------------------------------
       Storage
    ------------------------------------------------------------------- */

    /// @dev The max amount of time a user can lock their token
    uint256 public constant MAX_LOCK_TIME = 8 weeks;
    /// @dev To force all locks to expire and enable withdrawals
    bool public forceExpireLocks = false;
    /// @dev The nonfungible position manager contract
    INonfungiblePositionManager public immutable nfpManager;
    /// @dev The points contract
    IPoints public immutable points;
    /// @dev user => lptoken => amount
    mapping(address => mapping(address => uint256)) public staked;
    /// @dev user => tokenId => staked
    mapping(address => mapping(uint256 => bool)) public nfps;
    /// @dev user => key => lock time
    mapping(address => mapping(bytes32 => uint256)) public locks;
    /// @dev lpToken => isProtected
    mapping(address => bool) public isProtectedToken;

    /* -------------------------------------------------------------------
       Events 
    ------------------------------------------------------------------- */

    event SetForceExpireLocks(bool force);
    event LockedERC20(address sender, bytes32 lockKey, address lptoken, uint256 amount);
    event LockedERC721(address sender, bytes32 lockKey, uint256 tokenId);
    event Stake(address lpToken, address sender, uint256 amount);
    event Unstake(address lpToken, address sender, uint256 amount);
    event Deposit(address pool, address sender, uint256 tokenId);
    event Withdraw(address pool, address sender, uint256 tokenId);

    /* -------------------------------------------------------------------
       Constructor 
    ------------------------------------------------------------------- */

    constructor(address _nfpManager, address _points) public {
        nfpManager = INonfungiblePositionManager(_nfpManager);
        points = IPoints(_points);
    }

    /* -------------------------------------------------------------------
       Modifiers 
    ------------------------------------------------------------------- */

    modifier onlyPositionOwner(uint256 _tokenId) {
        require(nfps[msg.sender][_tokenId], "not position owner");
        _;
    }

    /* -------------------------------------------------------------------
       Admin 
    ------------------------------------------------------------------- */

    function setForceExpireLocks(bool _force) external onlyOwner {
        forceExpireLocks = _force;
        emit SetForceExpireLocks(_force);
    }

    function transferERC20(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(!isProtectedToken[_token], "protected");
        IERC20(_token).transfer(_to, _amount);
    }

    /* -------------------------------------------------------------------
       ERC20 LP Tokens 
    ------------------------------------------------------------------- */

    function stake(
        address _lpToken,
        uint256 _amount,
        uint256 _lock
    ) external {
        require(points.pools(_lpToken), "invalid lp token");
        require(_lock <= MAX_LOCK_TIME, "max lock time");

        bytes32 lockKey = keccak256(abi.encode("erc20", _lpToken));
        _updateLockTime(msg.sender, lockKey, _lock);

        if (_amount > 0) {
            staked[msg.sender][_lpToken] += _amount;
            if (!isProtectedToken[_lpToken]) {
                isProtectedToken[_lpToken] = true;
            }
            IERC20(_lpToken).transferFrom(msg.sender, address(this), _amount);
        }

        if (_lock > 0) {
            emit LockedERC20(msg.sender, lockKey, _lpToken, _amount);
        }

        emit Stake(_lpToken, msg.sender, _amount);
    }

    function unstake(address _lpToken, uint256 _amount) external {
        require(_isLockExpired(msg.sender, keccak256(abi.encode("erc20", _lpToken))), "!expired");
        staked[msg.sender][_lpToken] -= _amount;
        IERC20(_lpToken).transfer(msg.sender, _amount);
        emit Unstake(_lpToken, msg.sender, _amount);
    }

    /* -------------------------------------------------------------------
       NFT LP Tokens 
    ------------------------------------------------------------------- */

    function onERC721Received(
        address,
        address _from,
        uint256 _tokenId,
        bytes calldata
    ) external returns (bytes4) {
        require(msg.sender == address(nfpManager), "!manager");
        address pool = _poolFromTokenId(_tokenId);
        require(points.pools(pool), "invalid pool");

        nfps[_from][_tokenId] = true;
        emit Deposit(pool, _from, _tokenId);
        return this.onERC721Received.selector;
    }

    function lock(uint256 _tokenId, uint256 _lock) external onlyPositionOwner(_tokenId) {
        require(_lock <= MAX_LOCK_TIME, "max lock time");

        bytes32 lockKey = keccak256(abi.encode("erc721", _tokenId));
        _updateLockTime(msg.sender, lockKey, _lock);

        emit LockedERC721(msg.sender, lockKey, _tokenId);
    }

    function withdraw(uint256 _tokenId) external onlyPositionOwner(_tokenId) {
        require(_isLockExpired(msg.sender, keccak256(abi.encode("erc721", _tokenId))), "!expired");
        address pool = _poolFromTokenId(_tokenId);
        nfps[msg.sender][_tokenId] = false;
        nfpManager.safeTransferFrom(address(this), msg.sender, _tokenId);
        emit Withdraw(pool, msg.sender, _tokenId);
    }

    /* --------------------------------------------------------------
       NFT LP Tokens: Manage Liquidity 
    -------------------------------------------------------------- */

    function decreaseLiquidity(DecreaseLiquidityParams memory params) external onlyPositionOwner(params.tokenId) {
        nfpManager.decreaseLiquidity(params);
    }

    function collect(CollectParams memory params)
        external
        onlyPositionOwner(params.tokenId)
        returns (uint256, uint256)
    {
        require(params.recipient != address(0), "!recipient");
        nfpManager.collect(params);
    }

    function rebalance(
        DecreaseLiquidityParams memory decreaseParams,
        CollectParams memory collectParams,
        MintParams memory mintParams
    ) external onlyPositionOwner(collectParams.tokenId) {
        require(decreaseParams.tokenId == collectParams.tokenId, "!tokenId");
        require(collectParams.recipient != address(0), "!collectRecipient");
        require(mintParams.recipient == address(this), "!mintRecipient");

        uint256 tokenIdBefore = collectParams.tokenId;
        (, , , , , , , uint128 liquidityBefore, , , , ) = nfpManager.positions(tokenIdBefore);

        nfpManager.decreaseLiquidity(decreaseParams);
        nfpManager.collect(collectParams);
        nfpManager.burn(tokenIdBefore);

        IERC20(mintParams.token0).approve(address(nfpManager), mintParams.amount0Desired);
        IERC20(mintParams.token1).approve(address(nfpManager), mintParams.amount1Desired);

        (uint256 tokenIdAfter, uint128 liquidityAfter, , ) = nfpManager.mint(mintParams);

        nfps[msg.sender][tokenIdBefore] = false;
        nfps[msg.sender][tokenIdAfter] = true;

        require(liquidityAfter >= liquidityBefore, "!liquidity");

        // refund tokens
        _sweepToken(mintParams.token0, msg.sender);
        _sweepToken(mintParams.token1, msg.sender);
        _sweepETH(msg.sender);
    }

    /* --------------------------------------------------------------
       Utils 
    -------------------------------------------------------------- */

    function _isLockExpired(address _sender, bytes32 _lockKey) internal view returns (bool) {
        if (forceExpireLocks) return true;
        uint256 expiresAt = locks[_sender][_lockKey];
        return block.timestamp >= expiresAt;
    }

    function _updateLockTime(
        address _sender,
        bytes32 _lockKey,
        uint256 _lock
    ) internal {
        uint256 currLock = locks[_sender][_lockKey];
        uint256 newLock = block.timestamp + _lock;
        if (newLock > currLock) {
            locks[_sender][_lockKey] = newLock;
        }
    }

    function _poolFromTokenId(uint256 _tokenId) internal view returns (address) {
        (, , address token0, address token1, uint24 fee, , , , , , , ) = nfpManager.positions(_tokenId);
        return PoolAddress.computeAddress(nfpManager.factory(), PoolAddress.PoolKey(token0, token1, fee));
    }

    function _sweepToken(address _token, address _to) internal {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        if (bal > 0) {
            IERC20(_token).transfer(_to, bal);
        }
    }

    function _sweepETH(address _to) internal {
        uint256 bal = address(this).balance;
        if (bal > 0) {
            (bool sent, ) = payable(_to).call{ value: bal }("");
            require(sent, "!sweep");
        }
    }
}
