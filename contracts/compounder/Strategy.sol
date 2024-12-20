// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { Ownable } from "@openzeppelin/contracts-0.8/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";
import { IGenericVault } from "../interfaces/IGenericVault.sol";
import { IRewardHandler } from "../interfaces/balancer/IRewardHandler.sol";
import { IVirtualRewards } from "../interfaces/IVirtualRewards.sol";

/**
 * @title   AuraBalStrategy
 * @author  llama.airforce -> AuraFinance
 * @notice  Changes:
 *          - remove paltform fee
 */
contract AuraBalStrategy is Ownable {
    using SafeERC20 for IERC20;

    address public immutable BAL_TOKEN;
    address public immutable AURABAL_TOKEN;

    address public immutable vault;
    address[] public rewardTokens;
    mapping(address => address) public rewardHandlers;

    /// @notice restrict function to the vault
    modifier onlyVault() {
        require(vault == msg.sender, "!vault");
        _;
    }

    /**
     * @param _vault  The vault address
     * @param _balToken  The BAL token address
     * @param _auraBalToken The AuraBAL token address
     */
    constructor(
        address _vault,
        address _balToken,
        address _auraBalToken
    ) {
        vault = _vault;
        BAL_TOKEN = _balToken;
        AURABAL_TOKEN = _auraBalToken;
    }

    /// @notice update the token to handler mapping
    function _updateRewardToken(address _token, address _handler) internal {
        rewardHandlers[_token] = _handler;
    }

    /// @notice Add a reward token and its handler
    /// @dev For tokens that should not be swapped (i.e. BAL rewards)
    ///      use address as zero handler
    /// @param _token the reward token to add
    /// @param _handler address of the contract that will sell for BAL or ETH
    function addRewardToken(address _token, address _handler) external onlyOwner {
        rewardTokens.push(_token);
        _updateRewardToken(_token, _handler);
    }

    /// @notice Delete the reward token array
    /// @dev Protects from the rewardToken array being greifed
    function clearRewardTokens() external onlyOwner {
        delete rewardTokens;
    }

    /// @notice Update the handler of a reward token
    /// @dev Used to update a handler or retire a token (set handler to address 0)
    /// @param _token the reward token to add
    /// @param _handler address of the contract that will sell for BAL or ETH
    function updateRewardToken(address _token, address _handler) external onlyOwner {
        _updateRewardToken(_token, _handler);
    }

    /// @notice returns the number of reward tokens
    /// @return the number of reward tokens
    function totalRewardTokens() external view returns (uint256) {
        return rewardTokens.length;
    }

    /// @notice Query the amount currently staked
    /// @return total - the total amount of tokens staked
    function totalUnderlying() public view returns (uint256 total) {
        return IERC20(AURABAL_TOKEN).balanceOf(address(this));
    }

    /// @notice Deposits underlying tokens in the staking contract
    function stake(uint256 _amount) public onlyVault {
        // Silence is golden
    }

    /// @notice Withdraw a certain amount from the staking contract
    /// @param _amount - the amount to withdraw
    /// @dev Can only be called by the vault
    function withdraw(uint256 _amount) external onlyVault {
        IERC20(AURABAL_TOKEN).safeTransfer(vault, _amount);
    }

    /// @notice Claim rewards and swaps them to underlying for restaking
    /// @dev Can be called by the vault only
    /// @param _minAmountOut -  min amount of underlying tokens to receive w/o revert
    function harvest(uint256 _minAmountOut) public onlyVault returns (uint256 harvested) {
        uint256 auraBalBefore = IERC20(AURABAL_TOKEN).balanceOf(address(this));
        // process extra rewards
        uint256 extraRewardCount = IGenericVault(vault).extraRewardsLength();
        for (uint256 i; i < extraRewardCount; ++i) {
            address rewards = IGenericVault(vault).extraRewards(i);
            address token = IVirtualRewards(rewards).rewardToken();
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(rewards, balance);
                IVirtualRewards(rewards).queueNewRewards(balance);
            }
        }

        // process rewards
        address[] memory _rewardTokens = rewardTokens;
        for (uint256 i; i < _rewardTokens.length; ++i) {
            address _tokenHandler = rewardHandlers[_rewardTokens[i]];
            if (_tokenHandler == address(0)) {
                continue;
            }
            uint256 _tokenBalance = IERC20(_rewardTokens[i]).balanceOf(address(this));
            if (_tokenBalance > 0) {
                IERC20(_rewardTokens[i]).safeTransfer(_tokenHandler, _tokenBalance);
                IRewardHandler(_tokenHandler).sell();
            }
        }

        harvested = IERC20(AURABAL_TOKEN).balanceOf(address(this)) - auraBalBefore;
        require(harvested >= _minAmountOut, "!minAmountOut");
    }
}
