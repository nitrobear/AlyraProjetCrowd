// SPDX-License-Identifier: MIT

pragma solidity >=0.8.14;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Chainlink.sol";

contract Staking is Ownable, ReentrancyGuard, Chainlink {
    struct Staker {
        uint256 totalStaked; // Total amount staked
        uint256 lastDepositOrClaim; // Date of last deposit or last claim
        uint256 totalRewards; // Total of rewards
        uint256 allTimeHarvested; // Amount harvested from the start
        uint256 firstTimeDeposit; // Date of the first deposit
        bool exists;
    }

    mapping(address => Staker) public stakers;
    address[] public stakerList;

    uint256 public annualRewardRate; //annual rewards percentage
    uint256 public cooldown; //minimum time between two claims (in seconds)
    uint256 public minimumReward; //minimum reward to claim
    uint256 public poolBalance; //Amount staked on the pool

    ERC20 public stakingToken;

    enum PoolInfo {
        ActivePool,
        PausedPool,
        ClosedPool
    }

    PoolInfo public poolStatus;

    constructor(
        uint256 annualRewardRate_,
        uint256 cooldown_, // (in second)
        uint256 minimumReward_,
        address stakingTokenAddress
    ) {
        annualRewardRate = annualRewardRate_;
        cooldown = cooldown_;
        minimumReward = minimumReward_;
        stakingToken = ERC20(stakingTokenAddress);
    }

    event PoolStatusChange(PoolInfo newStatus);

    event Transaction(
        string action,
        address stakerAddress,
        uint256 amountStacked,
        uint256 rewards,
        uint256 timastamp
    );

    // ----------- CALCULATION FUNCTIONS ------------ //

    function rewardPerSecond(address a) public view returns (uint256) {
        return (((stakers[a].totalStaked * annualRewardRate) / 100) / 31536000);
    }

    function rewardDuration(address a) public view returns (uint256) {
        return block.timestamp - stakers[a].lastDepositOrClaim;
    }

    // ----------- GETTER -------------- //

    function getRewards(address a) public view returns (uint256 reward) {
        reward =
            stakers[a].totalRewards +
            (rewardPerSecond(a) * rewardDuration(a));
    }

    function getStaker(address a) public view returns (bool exists) {
        exists = stakers[a].exists;
    }

    function getStakedAmount(address a) public view returns (uint256 amount) {
        amount = stakers[a].totalStaked;
    }

    function getRemainingCooldown(address a)
        public
        view
        returns (uint256 remainingCooldown)
    {
        remainingCooldown = ((stakers[a].lastDepositOrClaim + cooldown) -
            block.timestamp);
    }

    function getStakersInPool() public view returns (uint256 stakersInPool) {
        uint256 stakersActive;
        for (uint256 i = 0; i < stakerList.length; i++) {
            address user = stakerList[i];
            if (stakers[user].totalStaked > 0) {
                stakersActive++;
            }
        }
        stakersInPool = stakersActive;
    }

    function getlastDepositOrClaim(address a)
        public
        view
        returns (uint256 lastDepositOrClaim)
    {
        lastDepositOrClaim = stakers[a].lastDepositOrClaim;
    }

    function getAllTimeHarvest(address a)
        public
        view
        returns (uint256 allTimeHarvest)
    {
        allTimeHarvest = stakers[a].allTimeHarvested;
    }

    function getFirstTimeDeposit(address a)
        public
        view
        returns (uint256 firstTimeDeposit)
    {
        firstTimeDeposit = stakers[a].firstTimeDeposit;
    }

    // ----- STAKING / UNSTAKING FUNCTIONS  ---- //

    function stake() external payable {
        require(
            poolStatus == PoolInfo.ActivePool,
            "Pool isn't active, you can't do this now"
        );
        require(msg.value > 0, "You have not sent any ETH");
        uint256 eth = msg.value;
        address user = msg.sender;

        if (stakers[user].exists) {
            if (stakers[user].totalStaked > 0) {
                uint256 reward = (rewardPerSecond(user) * rewardDuration(user));
                stakers[user].totalRewards += reward;
                stakers[user].totalStaked += eth;
                poolBalance += eth;
                stakers[user].lastDepositOrClaim = block.timestamp;

                emit Transaction("deposit", user, eth, reward, block.timestamp);
            } else {
                stakers[user].totalStaked += eth;
                poolBalance += eth;
                stakers[user].lastDepositOrClaim = block.timestamp;

                emit Transaction("deposit", user, eth, 0, block.timestamp);
            }
        } else {
            // Create new user
            Staker memory newUser;
            newUser.totalStaked = eth;
            poolBalance += eth;
            newUser.lastDepositOrClaim = block.timestamp;
            newUser.firstTimeDeposit = block.timestamp;
            newUser.exists = true;
            // Add user to stakers
            stakers[user] = newUser;
            stakerList.push(user);

            emit Transaction("deposit", user, eth, 0, block.timestamp);
        }
    }

    function partialUnstake(uint256 amount) external {
        address user = msg.sender;
        uint256 eth = amount;
        require(
            poolStatus == PoolInfo.ActivePool,
            "Pool isn't active, you can't do this now"
        );
        require(eth > 0, "No amount entered");
        require(
            stakers[user].exists = true,
            "You didn't participate in staking"
        );
        require(eth < stakers[user].totalStaked, "You don't have enough funds");
        require(stakers[user].totalStaked > 0, "You have nothing to unstake");

        uint256 reward = (rewardPerSecond(user) * rewardDuration(user));
        stakers[user].totalRewards += reward;
        stakers[user].totalStaked -= eth;
        poolBalance -= eth;
        stakers[user].lastDepositOrClaim = block.timestamp;
        (bool res, ) = user.call{value: amount}("");
        require(res, "Failed to send Ether");
    }

    function unstake() external {
        require(
            poolStatus == PoolInfo.ActivePool,
            "Pool isn't active, you can't do this now"
        );
        address user = msg.sender;
        require(
            stakers[user].exists = true,
            "You didn't participate in staking"
        );
        require(stakers[user].totalStaked > 0, "You have nothing to unstake");
        uint256 reward = (rewardPerSecond(user) * rewardDuration(user));
        stakers[user].totalRewards += reward;
        uint256 harvest = stakers[user].totalRewards;
        uint256 withdrawal = stakers[user].totalStaked;
        stakers[user].allTimeHarvested += harvest;
        poolBalance -= withdrawal;
        stakers[user].totalRewards = 0;
        stakers[user].totalStaked = 0;
        stakers[user].lastDepositOrClaim = 0;
        (bool res, ) = user.call{value: withdrawal}("");
        require(res, "Failed to send Ether");
        bool res2 = ERC20(stakingToken).transfer(user, harvest);
        require(res2, "Failed to send tokens");

        emit Transaction("unstake", user, withdrawal, harvest, block.timestamp);
    }

    // --------------- HARVEST FUNCTION -------------------//

    function harvestReward() external {
        address user = msg.sender;
        uint256 reward = (rewardPerSecond(user) * rewardDuration(user));
        require(
            poolStatus == PoolInfo.ActivePool ||
                poolStatus == PoolInfo.PausedPool,
            "Pool is closed, you can't do this now"
        );
        require(
            stakers[user].exists = true,
            "You didn't participate in staking"
        );
        require(
            stakers[user].totalRewards > minimumReward,
            "You haven't reached the minimum reward"
        );
        require(
            (stakers[user].lastDepositOrClaim + cooldown < block.timestamp),
            "You haven't reached the minimum time between two harvests"
        );
        stakers[user].totalRewards += reward;
        uint256 harvest = stakers[user].totalRewards;
        stakers[user].allTimeHarvested += harvest;
        stakers[user].lastDepositOrClaim = block.timestamp;
        stakers[user].totalRewards = 0;
        bool res2 = ERC20(stakingToken).transfer(user, harvest);
        require(res2, "Failed to send tokens");

        emit Transaction("harvest", user, 0, harvest, block.timestamp);
    }

    // ----------------- OWNER FUNCTION ------------------- //

    function pausedPool() external onlyOwner {
        poolStatus = PoolInfo.PausedPool;
        emit PoolStatusChange(PoolInfo.PausedPool);
    }

    function closedPool() external onlyOwner {
        poolStatus = PoolInfo.ClosedPool;
        emit PoolStatusChange(PoolInfo.ClosedPool);
    }

    function activePool() external onlyOwner {
        poolStatus = PoolInfo.ActivePool;
        emit PoolStatusChange(PoolInfo.ActivePool);
    }

    function unstakeAll() external onlyOwner {
        require(poolStatus == PoolInfo.ClosedPool, "Pool is not closed");
        for (uint256 i = 0; i < stakerList.length; i++) {
            address user = stakerList[i];
            if (stakers[user].totalStaked > 0) {
                ForceRemoveStake(user);
            }
        }
    }

    function ForceRemoveStake(address user) private {
        require(
            stakers[user].exists = true,
            "You didn't participate in staking"
        );
        require(stakers[user].totalStaked > 0, "You have nothing to unstake");
        uint256 reward = (rewardPerSecond(user) * rewardDuration(user));
        stakers[user].totalRewards += reward;
        uint256 harvest = stakers[user].totalRewards;
        uint256 withdrawal = stakers[user].totalStaked;
        stakers[user].allTimeHarvested += harvest;
        poolBalance -= withdrawal;
        stakers[user].totalRewards = 0;
        stakers[user].totalStaked = 0;
        stakers[user].lastDepositOrClaim = 0;
        (bool res, ) = user.call{value: withdrawal}("");
        require(res, "Failed to send Ether");
        bool res2 = ERC20(stakingToken).transfer(user, harvest);
        require(res2, "Failed to send tokens");
    }
}
