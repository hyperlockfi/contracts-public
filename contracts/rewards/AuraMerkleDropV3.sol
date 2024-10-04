// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { MerkleProof } from "@openzeppelin/contracts-0.8/utils/cryptography/MerkleProof.sol";
import { IAuraLocker } from "../interfaces/IAuraLocker.sol";
import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts-0.8/security/ReentrancyGuard.sol";
import { AuraMath } from "../utils/AuraMath.sol";
import { IAuraVestedEscrow } from "../interfaces/IAuraVestedEscrow.sol";
import { KeeperRole } from "../peripheral/KeeperRole.sol";

/**
 * @title   AuraMerkleDropV3
 * @dev     Forked from convex-platform/contracts/contracts/MerkleAirdrop.sol. Changes:
 *            - solc 0.8.11 & OpenZeppelin MerkleDrop
 *            - Delayed start w/ trigger
 *            - EndTime for withdrawal to treasuryDAO
 *            - Penalty on claim & AuraLocker lock (only if address(auraLocker) != 0)
 *            - Handles multiple merkle roots lifting some code from HiddenHands
 *              `RewardDistributor` 0xa9b08B4CeEC1EF29EdEC7F9C94583270337D6416.
 */
contract AuraMerkleDropV3 is ReentrancyGuard, KeeperRole {
    using SafeERC20 for IERC20;

    struct MerkleDrop {
        bytes32 merkleRoot;
        uint256 totalAmount;
        uint256 startTime;
        uint256 expiryTime;
        bytes32 ipfsHash;
    }

    struct Claim {
        uint256 epoch;
        uint256 amount;
        bytes32[] merkleProof;
        bool lock;
    }
    /// @dev The length of a claim/allocate epoch
    uint256 public constant EPOCH_LENGTH = 1 weeks;

    IERC20 public immutable aura;
    IAuraLocker public auraLocker;

    address public immutable penaltyForwarder;
    uint256 public immutable penaltyNumerator;

    uint256 public immutable deployTime;
    uint256 public pendingPenalty = 0;
    uint256 public totalClaimed;

    // Maps each of epoch to its merkle drop information
    mapping(uint256 => MerkleDrop) public merkleDrops;
    // Maps user claims per epoch  address => ( epoch => claimed)
    mapping(address => mapping(uint256 => bool)) public hasClaimed;
    // Tracks total amount of user claimed amounts
    mapping(address => uint256) public claimedPerUser;
    // Maps total claimed amount per epoch
    mapping(uint256 => uint256) public claimedPerEpoch;

    event MerkleDropUpdated(
        uint256 epoch,
        bytes32 merkleRoot,
        uint256 totalAmount,
        uint256 startTime,
        uint256 expiryTime,
        bytes32 ipfsHash
    );
    event ExpiredWithdrawn(uint256 epoch, uint256 amount);
    event LockerSet(address newLocker);
    event Claimed(uint256 epoch, address addr, uint256 amt, bool locked);
    event PenaltyForwarded(uint256 amount);
    event Rescued();

    /**
     * @param _owner            The Aura Dao
     * @param _aura             Aura token
     * @param _auraLocker       Aura locker contract
     * @param _penaltyForwarder PenaltyForwarded contract
     * @param _penaltyNumerator Penalty numerator 5 = 50% penalty
     */
    constructor(
        address _owner,
        address _aura,
        address _auraLocker,
        address _penaltyForwarder,
        uint256 _penaltyNumerator
    ) KeeperRole(_owner) {
        require(_owner != address(0), "!owner");
        require(_aura != address(0), "!aura");
        aura = IERC20(_aura);
        auraLocker = IAuraLocker(_auraLocker);

        penaltyForwarder = _penaltyForwarder;
        deployTime = block.timestamp;

        require(_penaltyNumerator < 10, "!penalty");
        penaltyNumerator = _penaltyNumerator;
    }

    /***************************************
                    CONFIG
    ****************************************/

    function setMerkleDrop(uint256 _epoch, MerkleDrop memory _merkleDrop) external onlyKeeper {
        require(_merkleDrop.expiryTime - _merkleDrop.startTime > 2 weeks, "!expiry");
        merkleDrops[_epoch] = _merkleDrop;
        emit MerkleDropUpdated(
            _epoch,
            _merkleDrop.merkleRoot,
            _merkleDrop.totalAmount,
            _merkleDrop.startTime,
            _merkleDrop.expiryTime,
            _merkleDrop.ipfsHash
        );
    }

    function withdrawExpired(uint256 _epoch) external onlyOwner {
        require(block.timestamp > merkleDrops[_epoch].expiryTime, "!expired");
        uint256 expiredAmount = merkleDrops[_epoch].totalAmount - claimedPerEpoch[_epoch];
        uint256 amt = AuraMath.min(aura.balanceOf(address(this)) - pendingPenalty, expiredAmount);
        aura.safeTransfer(this.owner(), amt);
        emit ExpiredWithdrawn(_epoch, amt);
    }

    function setLocker(address _newLocker) external onlyOwner {
        auraLocker = IAuraLocker(_newLocker);
        emit LockerSet(_newLocker);
    }

    function rescueReward() public onlyOwner {
        uint256 amt = aura.balanceOf(address(this));
        aura.safeTransfer(this.owner(), amt);

        emit Rescued();
    }

    /***************************************
                    CLAIM
    ****************************************/

    function _claim(
        uint256 _epoch,
        bytes32[] calldata _proof,
        uint256 _amount,
        bool _lock
    ) private returns (bool) {
        MerkleDrop memory _merkleDrop = merkleDrops[_epoch];

        require(_merkleDrop.merkleRoot != bytes32(0), "!root");
        require(block.timestamp > _merkleDrop.startTime, "!started");
        require(block.timestamp < _merkleDrop.expiryTime, "!active");
        require(_amount > 0, "!amount");
        require(hasClaimed[msg.sender][_epoch] == false, "already claimed");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(MerkleProof.verify(_proof, _merkleDrop.merkleRoot, leaf), "invalid proof");

        totalClaimed += _amount;
        claimedPerEpoch[_epoch] += _amount;
        require(claimedPerEpoch[_epoch] <= _merkleDrop.totalAmount, "!claimedPerEpoch");

        hasClaimed[msg.sender][_epoch] = true;
        claimedPerUser[msg.sender] += _amount;

        if (_lock) {
            aura.safeApprove(address(auraLocker), 0);
            aura.safeApprove(address(auraLocker), _amount);
            auraLocker.lock(msg.sender, _amount);
        } else {
            // If there is an address for auraLocker, and not locking, apply penalty
            uint256 penalty = address(penaltyForwarder) == address(0) || address(auraLocker) == address(0)
                ? 0
                : (_amount * penaltyNumerator) / 10;

            pendingPenalty += penalty;
            aura.safeTransfer(msg.sender, _amount - penalty);
        }

        emit Claimed(_epoch, msg.sender, _amount, _lock);
        return true;
    }

    /**
        @notice Claim rewards based on the specified metadata
        @param  _claims  Claim[] List of claim metadata
     */
    function claim(Claim[] calldata _claims) external nonReentrant {
        uint256 cLen = _claims.length;
        require(cLen > 0, "!length");

        for (uint256 i; i < cLen; ++i) {
            _claim(_claims[i].epoch, _claims[i].merkleProof, _claims[i].amount, _claims[i].lock);
        }
    }

    /***************************************
                    FORWARD
    ****************************************/

    function forwardPenalty() public {
        uint256 toForward = pendingPenalty;
        pendingPenalty = 0;
        aura.safeTransfer(penaltyForwarder, toForward);
        emit PenaltyForwarded(toForward);
    }

    /**
     *   @notice Gets current epoch, useful for automations
     */
    function getCurrentEpoch() external view returns (uint256) {
        return block.timestamp / EPOCH_LENGTH;
    }

    /***************************************
                CLAIM VESTING
    ****************************************/

    function claimVesting(address _vesting) public {
        IAuraVestedEscrow(_vesting).claim(false);
    }
}
