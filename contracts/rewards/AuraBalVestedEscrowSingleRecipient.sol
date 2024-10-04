// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts-0.8/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts-0.8/security/ReentrancyGuard.sol";
import { AuraMath } from "../utils/AuraMath.sol";
import { IGenericVault } from "../interfaces/IGenericVault.sol";

/**
 * @title   AuraBalVestedEscrowSingleRecipient
 * @author  adapted from AuraVestedEscrow
 * @notice  Vests tokens over a given timeframe.
 * @dev     Adaptations:
 *          - made for single recipient
 *          - can interact with the vault contract
 *          - can transfer out any extra rewards
 */
contract AuraBalVestedEscrowSingleRecipient is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardToken;
    IGenericVault public immutable vault;

    address public recipient;

    uint256 public immutable startTime;
    uint256 public immutable endTime;
    uint256 public immutable totalTime;

    bool public initialised = false;

    uint256 public totalLocked;
    uint256 public totalClaimed;

    event Funded(address indexed recipient, uint256 reward);
    event Claim(address indexed user, uint256 amount);
    event Skim(address indexed recipient, uint256 skimmable);

    /**
     * @param rewardToken_    Reward token (AuraBal)
     * @param vault_          AuraBal Vault
     * @param starttime_      Timestamp when claim starts
     * @param endtime_        When vesting ends
     */
    constructor(
        address rewardToken_,
        address vault_,
        uint256 starttime_,
        uint256 endtime_
    ) {
        require(starttime_ >= block.timestamp, "start must be future");
        require(endtime_ > starttime_, "end must be greater");

        rewardToken = IERC20(rewardToken_);
        vault = IGenericVault(vault_);

        startTime = starttime_;
        endTime = endtime_;
        totalTime = endTime - startTime;
        require(totalTime >= 16 weeks, "!short");
    }

    /* -------------------------------------------------------
        Modifier
    ------------------------------------------------------- */

    modifier onlyRecipient() {
        require(msg.sender == recipient, "!recipient");
        _;
    }

    /* -------------------------------------------------------
        Setup
    ------------------------------------------------------- */

    /**
     * @notice Fund recipients with rewardTokens
     * @param _recipient  The recipient to vest rewardTokens for
     * @param _amount     The amount of rewardTokens to vest
     */
    function fund(address _recipient, uint256 _amount) external onlyOwner nonReentrant {
        require(!initialised, "initialised already");
        require(block.timestamp < startTime, "already started");

        initialised = true;
        recipient = _recipient;
        totalLocked = _amount;

        rewardToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Funded(_recipient, _amount);
    }

    /* -------------------------------------------------------
        Views
    ------------------------------------------------------- */

    /**
     * @notice Available amount to claim
     */
    function available() public view returns (uint256) {
        uint256 vested = _totalVestedAt(block.timestamp);
        return vested - totalClaimed;
    }

    /**
     * @notice Total remaining vested amount
     */
    function remaining() public view returns (uint256) {
        uint256 vested = _totalVestedAt(block.timestamp);
        return totalLocked - vested;
    }

    /**
     * @notice Get total amount vested for this timestamp
     * @param _time       Timestamp to check vesting amount for
     */
    function _totalVestedAt(uint256 _time) internal view returns (uint256 total) {
        if (_time < startTime) {
            return 0;
        }
        uint256 locked = totalLocked;
        uint256 elapsed = _time - startTime;
        total = AuraMath.min((locked * elapsed) / totalTime, locked);
    }

    /* -------------------------------------------------------
        Claim
    ------------------------------------------------------- */

    /**
     * @dev Claim reward token
     */
    function claim() external nonReentrant {
        uint256 claimable = available();

        totalClaimed += claimable;
        rewardToken.safeTransfer(recipient, claimable);

        emit Claim(recipient, claimable);
    }

    /* -------------------------------------------------------
       Vault (only recipient)
    ------------------------------------------------------- */

    function deposit(uint256 _amount) external onlyRecipient {
        rewardToken.safeApprove(address(vault), 0);
        rewardToken.safeApprove(address(vault), _amount);
        vault.deposit(_amount, address(this));
    }

    function redeem(uint256 _shares) external onlyRecipient {
        vault.redeem(_shares, address(this), address(this));
    }

    /**
     * @dev As the amount of underlying tokens owed to the recipient grows
     *      in the vault an excess amount of tokens is available to skim. The
     *      skimmable amount if the amount above the vesting amount. And the
     *      vesting amount at any point is the total locked minus the amount
     *      already claimed. Any surplus can be sent to the recipient
     */
    function skim() external onlyRecipient {
        uint256 totalIn = totalLocked - totalClaimed;
        uint256 bal = rewardToken.balanceOf(address(this));
        uint256 underlying = vault.balanceOfUnderlying(address(this));

        uint256 skimmable = (bal + underlying) - totalIn;
        rewardToken.safeTransfer(recipient, skimmable);

        emit Skim(recipient, skimmable);
    }

    function transferERC20(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyRecipient {
        require(_token != address(rewardToken), "rewardToken");
        IERC20(_token).safeTransfer(_to, _amount);
    }
}
