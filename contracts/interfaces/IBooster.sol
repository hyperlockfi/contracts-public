// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

interface IBooster {
    struct FeeDistro {
        address distro;
        address rewards;
        bool active;
    }

    function feeTokens(address _token) external returns (FeeDistro memory);

    function earmarkFees(address _feeToken) external returns (bool);

    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        address stash;
        bool shutdown;
    }

    function earmarkRewards(uint256 _pid) external returns (bool);

    function poolLength() external view returns (uint256);

    function lockRewards() external view returns (address);

    function poolInfo(uint256 _pid) external view returns (PoolInfo memory);

    function lockIncentive() external view returns (uint256);

    function stakerIncentive() external view returns (uint256);

    function staker() external view returns (address);

    function earmarkIncentive() external view returns (uint256);

    function platformFee() external view returns (uint256);

    function FEE_DENOMINATOR() external view returns (uint256);

    function voteGaugeWeight(address[] calldata _gauge, uint256[] calldata _weight) external returns (bool);

    function crv() external view returns (address);

    function cvxCrv() external view returns (address);

    function boosterFeeDistro() external view returns (address);

    function boosterFeeHandler() external view returns (address);

    function nfpBooster() external view returns (address);

    function calculateIncentives(uint256 rewardAmount)
        external
        view
        returns (
            uint256 _lockIncentive,
            uint256 _stakerIncentive,
            uint256 _callIncentive,
            uint256 _rewardIncentive,
            uint256 _totalIncentive
        );
}
