// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { ERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts-0.8/access/Ownable.sol";
import { AuraMath } from "../utils/AuraMath.sol";

/**
 * @title   AuraToken
 * @notice  Basically an ERC20 with minting functionality operated by the "minter" and GaugeVoter.
 * @dev     The minting schedule is based on the amount of CRV earned through staking and is
 *          distributed along a supply curve (cliffs etc). Fork of ConvexToken.
 */
contract AuraToken is ERC20, Ownable {
    using AuraMath for uint256;

    /* -------------------------------------------------------------------
       Storage
    ------------------------------------------------------------------- */

    uint256 public constant EMISSIONS_MAX_SUPPLY = 45e24; // 45m
    uint256 public constant INIT_MINT_AMOUNT = 55e24; // 55m

    address public minter;
    uint256 public minterMinted = type(uint256).max;

    // Gauge voter periods
    address public gaugeVoter;
    uint256 public lastGaugeVoterMint;
    uint256 public immutable startEpoch;
    uint256 public constant gaugeVoterPeriod = 2 weeks;

    // Gauge voter mint rate
    uint256 public rampUpRate;
    uint256 public rampDownRate;
    uint256 public gaugeVoterMintRate;
    uint256 public constant RAMP_UP_END_EPOCH = 7;
    uint256 public constant INIT_GAUGE_VOTER_MINT_RATE = 45e22; // 450,000 (110,000/wk)
    uint256 public constant RAMP_DENOMINATOR = 10_000;

    /* -------------------------------------------------------------------
       Events
    ------------------------------------------------------------------- */

    event Initialised();
    event SetGaugeVoter(address gaugeVoter);
    event SetRampRates(uint256 rampUpRate, uint256 rampDownRate);

    /* -------------------------------------------------------------------
       Init
    ------------------------------------------------------------------- */

    /**
     * @param _nameArg      Token name
     * @param _symbolArg    Token symbol
     */
    constructor(string memory _nameArg, string memory _symbolArg) ERC20(_nameArg, _symbolArg) {
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
        address _gaugeVoter,
        uint256 _rampUpRate,
        uint256 _rampDownRate
    ) external onlyOwner {
        require(totalSupply() == 0, "Only once");
        require(_minter != address(0), "Invalid minter");
        require(_gaugeVoter != address(0), "Invalid gaugeVoter");

        _mint(_to, INIT_MINT_AMOUNT);
        minter = _minter;
        gaugeVoter = _gaugeVoter;
        minterMinted = 0;

        gaugeVoterMintRate = INIT_GAUGE_VOTER_MINT_RATE;

        rampUpRate = _rampUpRate;
        rampDownRate = _rampDownRate;

        emit Initialised();
        emit SetRampRates(_rampUpRate, _rampDownRate);
        emit SetGaugeVoter(_gaugeVoter);
    }

    /* -------------------------------------------------------------------
       Setters
    ------------------------------------------------------------------- */

    /**
     * Allows the owner to set the gauge voter mint rates
     * @param _rampUpRate The ramp up rate at which the gauge voter mints
     * @param _rampDownRate The ramp down rate at which the gauge voter mints
     */
    function setRampRates(uint256 _rampUpRate, uint256 _rampDownRate) external onlyOwner {
        rampUpRate = _rampUpRate;
        rampDownRate = _rampDownRate;
        emit SetRampRates(_rampUpRate, _rampDownRate);
    }

    /**
     * @notice Set the gauge voter address
     * @param _gaugeVoter The new gauge voter address
     */
    function setGaugeVoter(address _gaugeVoter) external onlyOwner {
        gaugeVoter = _gaugeVoter;
        emit SetGaugeVoter(_gaugeVoter);
    }

    /* -------------------------------------------------------------------
       View
    ------------------------------------------------------------------- */

    function getCurrentEpoch() external view returns (uint256) {
        return _getCurrentEpoch();
    }

    /* -------------------------------------------------------------------
       Core
    ------------------------------------------------------------------- */

    /**
     * @dev Mints AURA to the gauge voter based on the gauge voter minting schedule.
     */
    function gaugeVoterMint() external {
        require(msg.sender == gaugeVoter, "!gaugeVoter");
        uint256 currentEpoch = _getCurrentEpoch();
        require(currentEpoch > lastGaugeVoterMint, "!epoch");
        uint256 epoch = currentEpoch - startEpoch;

        uint256 emissionsMinted = totalSupply() - INIT_MINT_AMOUNT - minterMinted;
        uint256 amtTillMax = EMISSIONS_MAX_SUPPLY.sub(emissionsMinted);
        uint256 mintRate = gaugeVoterMintRate;

        if (amtTillMax < mintRate) {
            return;
        }

        // Update rate either up or down. For the first 7 epochs we ramp emissions up
        // then after that the emissions go down
        uint256 rampRate = epoch < RAMP_UP_END_EPOCH ? rampUpRate : rampDownRate;
        gaugeVoterMintRate = mintRate.mul(rampRate).div(RAMP_DENOMINATOR);

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
