// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import { IERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import { INonfungiblePositionManager } from "../interfaces/INonfungiblePositionManager.sol";
import { INonfungiblePositionManagerStruct } from "../interfaces/INonfungiblePositionManagerStruct.sol";

contract NfpFaucet is INonfungiblePositionManagerStruct {
    /* -------------------------------------------------------------------
       Storage 
    ------------------------------------------------------------------- */

    INonfungiblePositionManager public immutable nfpManager;

    /// @dev The amount of each token to send
    uint256 public constant AMOUNT = 1 ether;

    /// @dev user => pool => isClaimed;
    mapping(address => mapping(address => bool)) public isClaimed;

    /* -------------------------------------------------------------------
       Events 
    ------------------------------------------------------------------- */

    event Claimed(address sender, uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /* -------------------------------------------------------------------
       Constructor 
    ------------------------------------------------------------------- */

    constructor(address _nfpManager) public {
        nfpManager = INonfungiblePositionManager(_nfpManager);
    }

    /* -------------------------------------------------------------------
       Functions 
    ------------------------------------------------------------------- */

    /// @dev For a given token0 and token1 create a V3 position
    /// @dev Only callable for each token once per user
    function claimToken(address _pool) external {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        require(!isClaimed[msg.sender][_pool], "claimed");
        isClaimed[msg.sender][_pool] = true;

        address token0 = pool.token0();
        address token1 = pool.token1();

        require(IERC20(token0).balanceOf(address(this)) >= AMOUNT, "token0 balance too low");
        require(IERC20(token1).balanceOf(address(this)) >= AMOUNT, "token1 balance too low");

        uint24 fee = pool.fee();
        int24 tickSpacing = pool.tickSpacing();
        (, int24 tick, , , , , ) = pool.slot0();

        MintParams memory params;
        params.token0 = address(token0);
        params.token1 = address(token1);
        params.fee = fee;
        params.tickLower = tick - tickSpacing;
        params.tickUpper = tick + tickSpacing;
        params.amount0Desired = AMOUNT;
        params.amount1Desired = AMOUNT;
        params.amount0Min = 0;
        params.amount1Min = 0;
        params.recipient = msg.sender;
        params.deadline = block.timestamp + 1000;

        IERC20(token0).approve(address(nfpManager), AMOUNT);
        IERC20(token1).approve(address(nfpManager), AMOUNT);

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = nfpManager.mint(params);

        emit Claimed(msg.sender, tokenId, liquidity, amount0, amount1);
    }
}
