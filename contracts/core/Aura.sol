// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { ERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts-0.8/access/Ownable.sol";
import { AuraMath } from "../utils/AuraMath.sol";
import { IVoterProxy } from "../interfaces/IVoterProxy.sol";

/**
 * @title   AuraToken
 * @notice  Basically an ERC20 with minting functionality operated by the "operator" of the VoterProxy (Booster).
 * @dev     The minting schedule is based on the amount of CRV earned through staking and is
 *          distributed along a supply curve (cliffs etc). Fork of ConvexToken.
 */
contract AuraToken is ERC20, Ownable {
    using AuraMath for uint256;

    /* -------------------------------------------------------------------
       Storage 
    ------------------------------------------------------------------- */

    address public operator;
    address public immutable vecrvProxy;

    uint256 public constant D = 10000;
    uint256 public constant EMISSIONS_MAX_SUPPLY = 50e24; // 50m
    uint256 public constant INIT_MINT_AMOUNT = 50e24; // 50m
    uint256 public constant totalCliffs = 500;
    uint256 public immutable reductionPerCliff;

    address public minter;
    uint256 public nativeRate;
    uint256 public minterMinted = type(uint256).max;

    address public gaugeVoter;
    uint256 public lastGaugeVoterMint;
    uint256 public gaugeVoterRate;
    uint256 public gaugeVoterMintRate;
    uint256 public immutable startEpoch;
    uint256 public constant gaugeVoterPeriod = 2 weeks;
    uint256 public constant INIT_GAUGE_VOTER_MINT_RATE = 22e22; // 220,000 (110,000/wk)

    /* -------------------------------------------------------------------
       Events 
    ------------------------------------------------------------------- */

    event Initialised();
    event OperatorChanged(address indexed previousOperator, address indexed newOperator);
    event SetNativeRate(uint256 rate);
    event SetGaugeVoterRate(uint256 rate);

    /* -------------------------------------------------------------------
       Init 
    ------------------------------------------------------------------- */

    /**
     * @param _proxy        CVX VoterProxy
     * @param _nameArg      Token name
     * @param _symbolArg    Token symbol
     */
    constructor(
        address _proxy,
        string memory _nameArg,
        string memory _symbolArg
    ) ERC20(_nameArg, _symbolArg) {
        operator = msg.sender;
        vecrvProxy = _proxy;
        reductionPerCliff = EMISSIONS_MAX_SUPPLY.div(totalCliffs);
        startEpoch = _getCurrentEpoch();
    }

    /**
     * @dev Initialise and mints initial supply of tokens.
     * @param _to        Target address to mint.
     * @param _minter    The minter address.
     */
    function init(
        address _to,
        address _minter,
        address _gaugeVoter
    ) external {
        require(msg.sender == operator, "Only operator");
        require(totalSupply() == 0, "Only once");
        require(_minter != address(0), "Invalid minter");
        require(_gaugeVoter != address(0), "Invalid gaugeVoter");

        _mint(_to, INIT_MINT_AMOUNT);
        updateOperator();
        minter = _minter;
        gaugeVoter = _gaugeVoter;
        minterMinted = 0;

        nativeRate = D / 2; // 0.5
        gaugeVoterRate = D; // 1.0

        gaugeVoterMintRate = INIT_GAUGE_VOTER_MINT_RATE;

        emit Initialised();
    }

    /* -------------------------------------------------------------------
       Setters 
    ------------------------------------------------------------------- */

    /**
     * @dev This can be called if the operator of the voterProxy somehow changes.
     */
    function updateOperator() public {
        require(totalSupply() != 0, "!init");

        address newOperator = IVoterProxy(vecrvProxy).operator();
        require(newOperator != operator && newOperator != address(0), "!operator");

        emit OperatorChanged(operator, newOperator);
        operator = newOperator;
    }

    /**
     * @dev Set the rate multiplier for native minting
     * @param _rate The multiplier
     */
    function setNativeRate(uint256 _rate) external onlyOwner {
        require(_rate <= D, "!rate");
        nativeRate = _rate;
        emit SetNativeRate(_rate);
    }

    /**
     * @dev Set the rate multiplier for gauge voter minting
     * @param _rate The multiplier
     */
    function setGaugeVoterRate(uint256 _rate) external onlyOwner {
        require(_rate <= D * 2, "!rate");
        gaugeVoterRate = _rate;
        emit SetGaugeVoterRate(_rate);
    }

    /* -------------------------------------------------------------------
       Core
    ------------------------------------------------------------------- */

    /**
     * @dev Mints AURA to a given user based on the BAL supply schedule.
     */
    function mint(address _to, uint256 _amount) external returns (uint256) {
        require(totalSupply() != 0, "Not initialised");

        if (msg.sender != operator) {
            // dont error just return. if a shutdown happens, rewards on old system
            // can still be claimed, just wont mint cvx
            return 0;
        }

        // e.g. emissionsMinted = 6e25 - 5e25 - 0 = 1e25;
        uint256 emissionsMinted = totalSupply() - INIT_MINT_AMOUNT - minterMinted;
        // e.g. reductionPerCliff = 5e25 / 500 = 1e23
        // e.g. cliff = 1e25 / 1e23 = 100
        uint256 cliff = emissionsMinted.div(reductionPerCliff);

        // e.g. 100 < 500
        if (cliff < totalCliffs) {
            // e.g. (new) reduction = (500 - 100) * 2.5 + 700 = 1700;
            // e.g. (new) reduction = (500 - 250) * 2.5 + 700 = 1325;
            // e.g. (new) reduction = (500 - 400) * 2.5 + 700 = 950;
            uint256 reduction = totalCliffs.sub(cliff).mul(5).div(2).add(700);
            // e.g. (new) amount = 1e19 * 1700 / 500 =  34e18;
            // e.g. (new) amount = 1e19 * 1325 / 500 =  26.5e18;
            // e.g. (new) amount = 1e19 * 950 / 500  =  19e17;
            uint256 amount = _amount.mul(reduction).div(totalCliffs);
            // e.g. amtTillMax = 5e25 - 1e25 = 4e25
            uint256 amtTillMax = EMISSIONS_MAX_SUPPLY.sub(emissionsMinted);

            if (amount > amtTillMax) {
                amount = amtTillMax;
            }
            _mint(_to, amount);
            return amount;
        }
        return 0;
    }

    function gaugeVoterMint() external {
        uint256 currentEpoch = _getCurrentEpoch();
        require(currentEpoch > lastGaugeVoterMint, "!epoch");
        uint256 epoch = currentEpoch - startEpoch;

        uint256 emissionsMinted = totalSupply() - INIT_MINT_AMOUNT - minterMinted;
        uint256 amtTillMax = EMISSIONS_MAX_SUPPLY.sub(emissionsMinted);
        uint256 mintRate = gaugeVoterMintRate.mul(gaugeVoterRate).div(D);
        if (amtTillMax < mintRate) {
            return;
        }

        // Every 26th epoch reduce the rate by 90%
        if (epoch % 26 == 0) {
            // reduce gaugeVoterMintRate by 90%
            gaugeVoterMintRate = (gaugeVoterMintRate * 9000) / D;
        }

        // Set the last time the gauge voter minted to the current epoch
        lastGaugeVoterMint = currentEpoch;

        _mint(gaugeVoter, mintRate);
    }

    /**
     * @dev Allows minter to mint to a specific address
     */
    function minterMint(address _to, uint256 _amount) external {
        require(msg.sender == minter, "Only minter");
        minterMinted += _amount;
        _mint(_to, _amount);
    }

    /* -------------------------------------------------------------------
       Internal 
    ------------------------------------------------------------------- */

    function _getCurrentEpoch() internal view returns (uint256) {
        return block.timestamp / gaugeVoterPeriod;
    }
}
