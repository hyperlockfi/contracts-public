// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface ICurveGauge {
    function deposit(uint256) external;
    function balanceOf(address) external view returns (uint256);
    function withdraw(uint256) external;
    function claim_rewards() external;
    function reward_tokens(uint256) external view returns(address);//v2
    function rewarded_token() external view returns(address);//v1
    function lp_token() external view returns(address);
}

interface ICurveVoteEscrow {
    function create_lock(uint256, uint256) external;
    function increase_amount(uint256) external;
    function increase_unlock_time(uint256) external;
    function withdraw() external;
    function smart_wallet_checker() external view returns (address);
    function commit_smart_wallet_checker(address) external;
    function apply_smart_wallet_checker() external;
}

interface IWalletChecker {
    function check(address) external view returns (bool);
    function approveWallet(address) external;
    function dao() external view returns (address);
}

interface IVoting{
    function vote(uint256, bool, bool) external; //voteId, support, executeIfDecided
    function getVote(uint256) external view returns(bool,bool,uint64,uint64,uint64,uint64,uint256,uint256,uint256,bytes memory);
    function vote_for_gauge_weights(address,uint256) external;
}

interface IMinter{
    function mint(address) external;
}

interface IStaker{
    function deposit(address, address) external returns (bool);
    function withdraw(address) external returns (uint256);
    function withdraw(address, address, uint256) external returns (bool);
    function withdrawAll(address, address) external returns (bool);
    function createLock(uint256, uint256) external returns(bool);
    function increaseAmount(uint256) external returns(bool);
    function increaseTime(uint256) external returns(bool);
    function release() external returns(bool);
    function claimCrv(address) external returns (uint256);
    function claimRewards(address) external returns(bool);
    function claimFees(address) external returns (uint256);
    function setStashAccess(address, bool) external returns (bool);
    function vote(uint256,address,bool) external returns(bool);
    function voteGaugeWeight(address,uint256) external returns(bool);
    function balanceOfPool(address) external view returns (uint256);
    function operator() external view returns (address);
    function execute(address _to, uint256 _value, bytes calldata _data) external returns (bool, bytes memory);
    function migrate(address to) external;
}

interface IRewards{
    function stake(address, uint256) external;
    function stakeFor(address, uint256) external;
    function withdraw(address, uint256) external;
    function exit(address) external;
    function getReward(address) external;
    function queueNewRewards(uint256) external;
    function notifyRewardAmount(uint256) external;
    function addExtraReward(address) external;
    function extraRewardsLength() external view returns (uint256);
    function stakingToken() external view returns (address);
    function rewardToken() external view returns(address);
    function earned(address account) external view returns (uint256);
}

interface IStash{
    function stashRewards() external returns (bool);
    function processStash() external returns (bool);
    function claimRewards() external returns (bool);
    function initialize(uint256 _pid, address _operator, address _staker, address _gauge, address _rewardFactory) external;
    function setExtraReward(address) external;
}

interface IFeeDistributor {
    function claim(address user) external returns (uint256);
    function token() external view returns (address);
    function toggle_allow_checkpoint_token() external;
    function admin() external view returns (address);
}

interface ITokenMinter{
    function mint(address,uint256) external;
    function burn(address,uint256) external;
}

interface IDeposit{
    function isShutdown() external view returns(bool);
    function balanceOf(address _account) external view returns(uint256);
    function totalSupply() external view returns(uint256);
    function poolInfo(uint256) external view returns(address,address,address,address,address,bool);
    function poolLength() external view returns(uint256);
    function withdrawTo(uint256,uint256,address) external;
    function claimRewards(uint256,address) external returns(bool);
    function setGaugeRedirect(uint256 _pid) external returns(bool);
    function owner() external returns(address);
    function poolManager() external returns(address);
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
    function crv() external returns (address);
    function cvxCrv() external returns (address);
    function lockRewards() external returns (address);
    function stakerRewards() external returns (address);
    function lockIncentive() external returns (uint256);
    function stakerIncentive() external returns (uint256);
    function earmarkIncentive() external returns (uint256);
}

interface ICrvDeposit{
    function deposit(uint256, bool) external;
    function lockIncentive() external view returns(uint256);
}

interface IRewardFactory{
    function setAccess(address,bool) external;
    function CreateCrvRewards(uint256,address,address) external returns(address);
    function CreateTokenRewards(address,address,address) external returns(address);
    function activeRewardCount(address) external view returns(uint256);
    function addActiveReward(address,uint256) external returns(bool);
    function removeActiveReward(address,uint256) external returns(bool);
}

interface IStashFactory{
    function CreateStash(uint256,address,address) external returns(address);
    function setImplementation(address) external;
}

interface ITokenFactory{
    function CreateDepositToken(address) external returns(address);
}

interface IPools{
    function addPool(address _lptoken, address _gauge) external returns(bool);
    function shutdownPool(uint256 _pid) external returns(bool);
    function poolInfo(uint256) external view returns(address,address,address,address,address,bool);
    function poolLength() external view returns (uint256);
    function gaugeMap(address) external view returns(bool);
    function setPoolManager(address _poolM) external;
    function shutdownSystem() external;
    function setUsedAddress(address[] memory) external;
}

interface IVestedEscrow{
    function fund(address[] calldata _recipient, uint256[] calldata _amount) external returns(bool);
}

interface IRewardDeposit {
    function addReward(address, uint256) external;
}

interface IBoosterFeeDistro {
    function queueNewRewards(uint256 _lockIncentive, uint256 _stakerIncentive, uint256 _callIncentive) external;
}
