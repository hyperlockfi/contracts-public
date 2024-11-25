// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import { TickMath } from "../thruster/TickMath.sol";
import { PoolAddress } from "../thruster/PoolAddress.sol";
import { PositionValue } from "../thruster/PositionValue.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import { LiquidityAmounts } from "../thruster/LiquidityAmounts.sol";
import { INonfungiblePositionManager } from "../interfaces/INonfungiblePositionManager.sol";
import { IUniswapV2Pair } from "../interfaces/IUniswapV2Pair.sol";

contract NfpViewHelper {
    using SafeMath for uint256;
    using PositionValue for INonfungiblePositionManager;

    struct Position {
        uint256 id;
        bytes32 key;
        address pool;
        address token0;
        address token1;
        uint24 fee;
        uint256 feesToken0;
        uint256 feesToken1;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /* -------------------------------------------------------------------
       Storage 
    ------------------------------------------------------------------- */

    INonfungiblePositionManager public immutable nfpManager;
    //  factory => fee
    mapping(address => uint256) public v2factoryFees;

    /* -------------------------------------------------------------------
       Constructor 
    ------------------------------------------------------------------- */

    constructor(
        address _nfpManager,
        address[] memory _v2Factories,
        uint256[] memory _v2Fees
    ) public {
        nfpManager = INonfungiblePositionManager(_nfpManager);

        uint256 length = _v2Fees.length;
        require(length == _v2Factories.length, "wrong input");

        for (uint256 i = 0; i < length; i++) {
            v2factoryFees[_v2Factories[i]] = _v2Fees[i];
        }
    }

    /* -------------------------------------------------------------------
       Core 
    ------------------------------------------------------------------- */

    function getTokensForOwner(
        address owner,
        uint256 start,
        uint256 end
    ) external view returns (Position[] memory) {
        uint256 i0 = start;
        uint256 i1 = end > 0 ? end : nfpManager.balanceOf(owner);

        Position[] memory positions = new Position[](i1 - i0);

        for (uint256 i = i0; i < i1; i++) {
            uint256 tokenId = nfpManager.tokenOfOwnerByIndex(owner, i);
            positions[i] = getPositionInfo(tokenId);
        }

        return positions;
    }

    function getPositionInfos(uint256[] memory _tokenIds) external view returns (Position[] memory) {
        uint256 len = _tokenIds.length;
        Position[] memory positions = new Position[](len);

        for (uint256 i = 0; i < len; i++) {
            positions[i] = getPositionInfo(_tokenIds[i]);
        }

        return positions;
    }

    function getPositionInfo(uint256 _tokenId) public view returns (Position memory position) {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = nfpManager.positions(_tokenId);

        bytes32 poolKey = keccak256(abi.encode(token0, token1, fee));
        address poolAddr = PoolAddress.computeAddress(
            nfpManager.factory(),
            PoolAddress.PoolKey({ token0: token0, token1: token1, fee: fee })
        );

        (position.feesToken0, position.feesToken1) = nfpManager.fees(_tokenId);
        position.id = _tokenId;
        position.key = poolKey;
        position.pool = poolAddr;
        position.token0 = token0;
        position.token1 = token1;
        position.fee = fee;
        position.tickLower = tickLower;
        position.tickUpper = tickUpper;
        position.liquidity = liquidity;
        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.tokensOwed0 = tokensOwed0;
        position.tokensOwed1 = tokensOwed1;
    }

    function getTokenAmounts(address _pool, uint256[] calldata _tokenIds)
        external
        view
        returns (uint256 token0Amount, uint256 token1Amount)
    {
        (uint160 sqrtRatioX96, , , , , , ) = IUniswapV3Pool(_pool).slot0();
        uint256 len = _tokenIds.length;

        for (uint256 i = 0; i < len; i++) {
            (uint256 t0, uint256 t1) = nfpManager.total(_tokenIds[i], sqrtRatioX96);
            token0Amount = token0Amount.add(t0);
            token1Amount = token1Amount.add(t1);
        }
    }

    /* -------------------------------------------------------------------
       V2 
    ------------------------------------------------------------------- */

    function getV2PoolFee(address _pool) external view returns (uint256 fee) {
        return v2factoryFees[IUniswapV2Pair(_pool).factory()];
    }

    /* -------------------------------------------------------------------
       Utils 
    ------------------------------------------------------------------- */

    function keyFromPositionId(uint256 _tokenId) external view returns (bytes32) {
        (, , address token0, address token1, uint24 fee, , , , , , , ) = nfpManager.positions(_tokenId);
        return keccak256(abi.encode(token0, token1, fee));
    }

    function poolFromPositionId(uint256 _tokenId) external view returns (address) {
        (, , address token0, address token1, uint24 fee, , , , , , , ) = nfpManager.positions(_tokenId);
        return
            PoolAddress.computeAddress(
                nfpManager.factory(),
                PoolAddress.PoolKey({ token0: token0, token1: token1, fee: fee })
            );
    }

    /* -------------------------------------------------------------------
       Liquidity 
    ------------------------------------------------------------------- */
    function _getAmountsForLiquidity(
        address _pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 _liquidity
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtRatioX96, , , , , , ) = IUniswapV3Pool(_pool).slot0();
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                _liquidity
            );
    }

    function getAmountsForLiquidityByPool(
        address _pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 _liquidity
    ) external view returns (uint256 amount0, uint256 amount1) {
        return _getAmountsForLiquidity(_pool, tickLower, tickUpper, _liquidity);
    }

    function getAmountsForLiquidity(uint256 _tokenId, uint128 _liquidity)
        external
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (, , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, , , , , ) = nfpManager
            .positions(_tokenId);
        address pool = PoolAddress.computeAddress(nfpManager.factory(), PoolAddress.PoolKey(token0, token1, fee));

        return _getAmountsForLiquidity(pool, tickLower, tickUpper, _liquidity);
    }

    function getAmountForAmount(
        uint256 _tokenId,
        uint256 _amount0,
        uint256 _amount1
    ) external view returns (uint256) {
        require(_amount0 == 0 || _amount1 == 0, "one of amount0 OR amount1 must be zero");

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = nfpManager.positions(_tokenId);

        if (_amount0 > 0) {
            uint128 liq = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                _amount0
            );
            return
                LiquidityAmounts.getAmount1ForLiquidity(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liq
                );
        } else {
            uint128 liq = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                _amount1
            );
            return
                LiquidityAmounts.getAmount0ForLiquidity(
                    TickMath.getSqrtRatioAtTick(tickLower),
                    TickMath.getSqrtRatioAtTick(tickUpper),
                    liq
                );
        }
    }
}
