// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../interfaces/ISwapRouter.sol";
import "./SingleSidedLiquidityLib.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import { IUniswapV2Factory } from "../interfaces/IUniswapV2Factory.sol";
import { INonfungiblePositionManagerStruct } from "../interfaces/INonfungiblePositionManagerStruct.sol";
import { INonfungiblePositionManager } from "../interfaces/INonfungiblePositionManager.sol";
import { IERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts-0.6/utils/ReentrancyGuard.sol";
import { IUniswapV2Pair } from "../interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Router02 } from "../interfaces/IUniswapV2Router02.sol";

/**
 * @title   SingleSidedDepositor
 * @notice  Peripheral contract that allows users to single side deposit into a Thurster V2, V3 pools.
 *          The contract calculates the optimal amount of TokenIn to be swapped for it's pair token.
 *          the swap is done withing the same pool of the deposit.
 *          **************************** ¡¡¡ WARNING !!! ****************************
 *          Do not use this contract to deposit when :
 *      1.- Pools with low liquidity.
 *      2.- The amount to deposit is a big % of the new deposit.
 *      3.- Without providing min amounts calculated off-chain.
 *          **************************** ¡¡¡ WARNING !!! ****************************
 */
contract SingleSidedDepositor is ReentrancyGuard {
    using SafeMath for uint256;
    using TickMath for uint160;
    using TickMath for int24;
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public immutable nfpManager; // ie. 0x434575EaEa081b735C985FA9bf63CD7b87e227F9
    ISwapRouter public immutable swapRouter; // ie. 0x337827814155ECBf24D20231fCA4444F530C0555
    address public immutable quoter; // ie. 0x3b299f65b47c0bfAEFf715Bc73077ba7A0a685bE

    // V2
    uint256 public constant V2_FEE_DENOMINATOR = 1000000;

    // (1.00%)
    uint256 public constant V2_FEE_10000 = 10000;
    address public immutable routerV2_10000; // ie. 0x44889b52b71E60De6ed7dE82E2939fcc52fB2B4E;
    address public immutable factoryV2_10000; // ie. 0x37836821a2c03c171fB1a595767f4a16e2b93Fc4;
    // (0.30%)
    uint256 public constant V2_FEE_3000 = 3000;
    address public immutable routerV2_3000; // ie. 0x98994a9A7a2570367554589189dC9772241650f6;
    address public immutable factoryV2_3000; // ie. 0xb4A7D971D0ADea1c73198C97d7ab3f9CE4aaFA13;

    constructor(
        // v3
        address _nfpManager,
        address _swapRouter,
        address _quoter,
        // v2
        address _routerV2_10000,
        address _factoryV2_10000,
        address _routerV2_3000,
        address _factoryV2_3000
    ) public {
        nfpManager = INonfungiblePositionManager(_nfpManager);
        swapRouter = ISwapRouter(_swapRouter);
        quoter = _quoter;
        routerV2_10000 = _routerV2_10000;
        factoryV2_10000 = _factoryV2_10000;
        routerV2_3000 = _routerV2_3000;
        factoryV2_3000 = _factoryV2_3000;
    }

    /* --------------------------------------------------------------
     * ZAPV3 
    -------------------------------------------------------------- */

    /// @notice Single side deposit into a V3 pool.
    /// @dev It calculates the optimal amount of `tokenIn` to swap for its pair pool and it is deposited into a v3 Pool.
    /// Call off-chain quoteSwapAmountV3 to calculate `amountTokenInToSwap` and `minLiquidity`.
    /// @param _pool V3 Pool to deposit to.
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param tokenIn Token address that is being deposited.
    /// @param amountIn How much tokenIn is required for the minted liquidity
    /// @param amountTokenInToSwap How much tokenIn is swapped for its pair.
    /// @param minLiquidity Expected liquidity after the position is minted.
    function zapV3(
        address _pool,
        int24 tickLower,
        int24 tickUpper,
        address tokenIn,
        uint256 amountIn,
        uint256 amountTokenInToSwap,
        uint256 minLiquidity
    ) external {
        // Get pool info
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        bool isAmountInToken0 = pool.token0() == tokenIn;

        require(isAmountInToken0 || tokenIn == pool.token1(), "!wrong token");
        address tokenToSwap = isAmountInToken0 ? pool.token1() : pool.token0();

        // Pull tokens from sender
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Swap tokenIn for PairToken
        IERC20(tokenIn).safeIncreaseAllowance(address(swapRouter), amountTokenInToSwap);
        uint256 amountSwapped = swapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(tokenIn, pool.fee(), tokenToSwap),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountTokenInToSwap,
                amountOutMinimum: 0
            })
        );

        // Mint position
        (, uint128 actualLiquidity) = _addLiquidityV3(
            _pool,
            tickLower,
            tickUpper,
            tokenIn,
            amountIn.sub(amountTokenInToSwap),
            amountSwapped
        );

        // Validate that calculated liquidity is close to the actual liquidity
        require(minLiquidity >= actualLiquidity, "!liquidity");
        // Return any dust to sender
        sweepToken(pool.token0(), msg.sender);
        sweepToken(pool.token1(), msg.sender);
    }

    function _addLiquidityV3(
        address _pool,
        int24 tickLower,
        int24 tickUpper,
        address tokenIn,
        uint256 amountIn,
        uint256 amountSwapped
    ) internal returns (uint256 tokenId, uint128 liquidity) {
        // Get pool info
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        bool isAmountInToken0 = pool.token0() == tokenIn;
        address tokenToSwap = isAmountInToken0 ? pool.token1() : pool.token0();

        // Mint position
        IERC20(tokenIn).safeIncreaseAllowance(address(nfpManager), amountIn);
        IERC20(tokenToSwap).safeIncreaseAllowance(address(nfpManager), amountSwapped);

        uint256 amount0Desired = isAmountInToken0 ? amountIn : amountSwapped;
        uint256 amount1Desired = isAmountInToken0 ? amountSwapped : amountIn;

        (tokenId, liquidity, , ) = nfpManager.mint(
            INonfungiblePositionManagerStruct.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                fee: pool.fee(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0e18,
                amount1Min: 0e18,
                recipient: msg.sender,
                deadline: block.timestamp
            })
        );
    }

    function quoteSwapAmountV3(
        address pool,
        int24 tickLower,
        int24 tickUpper,
        address baseToken,
        address quoteToken,
        uint256 baseAmountIn
    ) public returns (uint256 liquidity, uint256 tokensToSwap) {
        return
            SingleSidedLiquidityLib.getParamsForSingleSidedAmount(
                quoter,
                pool,
                tickLower,
                tickUpper,
                baseAmountIn,
                baseToken < quoteToken
            );
    }

    /* --------------------------------------------------------------
     * ZAPV2 
    -------------------------------------------------------------- */

    function zapV2(
        address _pool,
        address tokenIn,
        uint256 amountIn,
        uint256 fee,
        uint256 amountOutMin
    ) external {
        require(fee == V2_FEE_3000 || fee == V2_FEE_10000, "!fee");
        // Get pool info
        IUniswapV2Pair pool = IUniswapV2Pair(_pool);
        bool isAmountInToken0 = pool.token0() == tokenIn;

        require(isAmountInToken0 || tokenIn == pool.token1(), "!wrong token");
        address tokenToSwap = isAmountInToken0 ? pool.token1() : pool.token0();

        // Pull tokens from sender
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        (address v2Factory, address v2Router) = _getV2FactoryAndRouter(fee);

        address pair = IUniswapV2Factory(v2Factory).getPair(tokenIn, tokenToSwap);
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair).getReserves();

        uint256 reserveIn = isAmountInToken0 ? reserve0 : reserve1;
        uint256 amountToSwap = quoteSwapAmountV2(reserveIn, amountIn, fee);

        _swapV2(v2Router, tokenIn, tokenToSwap, amountToSwap, amountOutMin);
        _addLiquidityV2(v2Router, tokenIn, tokenToSwap);

        // Return any dust to sender
        sweepToken(pool.token0(), msg.sender);
        sweepToken(pool.token1(), msg.sender);
    }

    function _swapV2(
        address v2Router,
        address tokenIn,
        address tokenToSwap,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal {
        IERC20(tokenIn).safeIncreaseAllowance(v2Router, amountIn);

        address[] memory path = new address[](2);
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenToSwap;

        IUniswapV2Router02(v2Router).swapExactTokensForTokens(
            amountIn,
            amountOutMin, // amountOutMin
            path,
            address(this), // to
            block.timestamp // deadline
        );
    }

    function _addLiquidityV2(
        address v2Router,
        address token0,
        address token1
    ) internal {
        uint256 balToken0 = IERC20(token0).balanceOf(address(this));
        uint256 balToken1 = IERC20(token1).balanceOf(address(this));

        IERC20(token0).safeIncreaseAllowance(v2Router, balToken0);
        IERC20(token1).safeIncreaseAllowance(v2Router, balToken1);

        IUniswapV2Router02(v2Router).addLiquidity(
            token0,
            token1,
            balToken0, //amount0Desired
            balToken1, //amount1Desired
            1, // amount0Min
            1, //amount1Min
            msg.sender, // to
            block.timestamp // deadline
        );
    }

    function _getV2FactoryAndRouter(uint256 fee) internal view returns (address v2Factory, address v2Router) {
        if (fee == V2_FEE_10000) {
            v2Factory = factoryV2_10000;
            v2Router = routerV2_10000;
        } else {
            v2Factory = factoryV2_3000;
            v2Router = routerV2_3000;
        }
    }

    function sqrt(uint256 y) private pure returns (uint256 z) {
        // import "@uniswap/lib/contracts/libraries/Babylonian.sol";
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /*
    s = optimal swap amount
    r = amount of reserve for token a
    a = amount of token a the user currently has (not added to reserve yet)
    f = swap fee percent
    s = (sqrt(((2 - f)r)^2 + 4(1 - f)ar) - (2 - f)r) / (2(1 - f))
    */

    function quoteSwapAmountV2(
        uint256 reserveIn,
        uint256 amountIn,
        uint256 fee
    ) public pure returns (uint256) {
        uint256 q0 = (((2 * V2_FEE_DENOMINATOR) - fee)**2) / V2_FEE_DENOMINATOR;
        uint256 q1 = 4 * (V2_FEE_DENOMINATOR - fee);
        uint256 q2 = ((2 * V2_FEE_DENOMINATOR) - fee) / 1000;
        uint256 q3 = (2 * (V2_FEE_DENOMINATOR - fee)) / 1000;

        return (sqrt(reserveIn * (reserveIn * q0 + amountIn * q1)) - reserveIn * q2) / q3;
    }

    /* --------------------------------------------------------------
     * Utility 
    -------------------------------------------------------------- */
    function sweepToken(address _token, address _to) public nonReentrant {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        if (bal > 0) {
            IERC20(_token).transfer(_to, bal);
        }
    }
}
