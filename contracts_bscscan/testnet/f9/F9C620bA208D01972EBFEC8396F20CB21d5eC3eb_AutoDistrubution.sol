/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "./libs/ReentrancyGuard.sol";
import './libs/AddrArrayLib.sol';
import "./MoneyToken.sol";

// MasterChef is the master of money. He can make money and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once money is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefMoney is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using AddrArrayLib for AddrArrayLib.Addresses;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 busdRewardDebt; // Reward debt. See explanation below.
        uint256 lastDepositTime;
        uint256 moneyRewardLockedUp;
        uint256 busdRewardLockedUp;
        //
        // We do some fancy math here. Basically, any point in time, the amount of moneys
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accMoneyPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accMoneyPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. moneys to distribute per block.
        uint256 lastRewardBlock; // Last block number that moneys distribution occurs.
        uint256 accMoneyPerShare; // Accumulated moneys per share, times 1e12. See below.
        uint256 accBusdPerShare; // Accumulated moneys per share, times 1e12. See below.
        uint256 burnRate; // Burn rate when unstake. ex: WHEN UNSTAKE  95% of THE $TIME TOKEN STAKED ARE BURNED AUTOMATICALY
        uint256 emergencyBurnRate; // Burn rate when emergencyWithdraw. ex: IF UNSTAKE BEFORE 2 WEEK THE USER GET NO REWARD AND 25% OF THE $TIME TOKEN STAKED ARE BURN WHEN UNSTAKE
        uint256 lockPeriod; // Staking lock period. ex: POOL 5 REWARD LOCKED: 2 WEEK
        uint256 depositFee; // deposit fee.
        bool depositBurn;
        bool secondaryReward;
    }

    // The money TOKEN!
    // AUDIT: MCM-06 | Set immutable to Variables
    MoneyToken public immutable money;
    // Busd token
    // AUDIT: MCM-06 | Set immutable to Variables
    IBEP20 public immutable busdToken;
    // Dev address.
    address public devaddr;

    // Busd Feeder
    address public busdFeeder1;
    address public busdFeeder2;
    // Max percent with 2 decimal -> 10000 = 100%
    // AUDIT: MCM-02 | Set constant to Variables
    uint256 public constant maxShare = 10000;
    // money tokens created per block.
    uint256 public moneyPerBlock;
    // busd tokens created per block.
    uint256 public busdPerBlock;
    // Bonus muliplier for early money makers.
    // AUDIT: MCM-12 | Incorrect Naming Convention Utilization
    uint256 public bonusMultiplier = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(uint256 => AddrArrayLib.Addresses) private addressByPid;
    mapping(uint256 => uint[]) public userIndexByPid;

    mapping (address => bool) private _authorizedCaller;

    // Total deposit amount of each pool
    mapping(uint256 => uint256) public poolDeposit;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalBusdAllocPoint = 0;

    // The block number when money mining starts.
    // AUDIT: MCM-06 | Set immutable to Variables
    uint256 public immutable startBlock;

    uint256 public busdEndBlock;

    uint256 public constant busdPoolId = 0;

    // AUDIT: MCM-02 | Set constant to Variables
    address public constant BURN_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Burn(address indexed user, uint256 indexed pid, uint256 sent, uint256 burned);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    // AUDIT: MCM-03 | Missing indexed in Events
    event Transfer(address indexed to, uint256 requsted, uint256 sent);
    event MoneyPerBlockUpdated(uint256 moneyPerBlock);
    event BusdPerBlockUpdated(uint256 busdPerBlock);
    // AUDIT: MCM-03 | Missing indexed in Events
    event UpdateEmissionSettings(address indexed from, uint256 depositAmount, uint256 endBlock);
    // AUDIT: MCM-08 | Missing Emit Events
    event UpdateMultiplier(uint256 multiplierNumber);
    event SetDev(address indexed prevDev, address indexed newDev);
    event SetAuthorizedCaller(address indexed caller, bool _status);
    event SetBusdFeeder1(address indexed busdFeeder);
    event SetBusdFeeder2(address indexed busdFeeder);
    event RewardLockedUp(address indexed recipient, uint256 indexed pid, uint256 moneyLockedUp, uint256 busdLockedUp);

    modifier onlyAuthorizedCaller() {
        require(_msgSender() == owner() || _authorizedCaller[_msgSender()],"MINT_CALLER_NOT_AUTHORIZED");
        _;
    }

    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "pool id not exisit");
        _;
    }

    constructor(
        MoneyToken _money,
        IBEP20 _busdToken,
        address _devaddr,
        address _busdFeeder1,
        address _busdFeeder2,
        uint256 _moneyPerBlock,
        uint256 _busdPerBlock, //should be 0
        uint256 _startBlock,
        uint256 _busdEndBlock //should be 0
    ) public {
        require(address(_money) != address(0), "MasterChefMoney.Constructor: Money token shouldn't be zero address");
        require(address(_busdToken) != address(0), "MasterChefMoney.Constructor: Busd token shouldn't be zero address");
        require(_devaddr != address(0), "MasterChefMoney.Constructor: Dev address shouldn't be zero address");
        require(_busdFeeder1 != address(0), "MasterChefMoney.Constructor: Busd feeder 1 address shouldn't be zero address");
        require(_busdFeeder2 != address(0), "MasterChefMoney.Constructor: Busd feeder 2 address shouldn't be zero address");
        require(_moneyPerBlock != 0, "MasterChefMoney.Constructor: Money reward token count per block can't be zero");

        money = _money;
        busdToken = _busdToken;
        devaddr = _devaddr;
        busdFeeder1 = _busdFeeder1;
        busdFeeder2 = _busdFeeder2;
        moneyPerBlock = _moneyPerBlock;
        busdPerBlock = _busdPerBlock;
        startBlock = _startBlock;
        busdEndBlock = _busdEndBlock;
        _authorizedCaller[busdFeeder1] = true; // tester: to allow call to updateEmissionSettings
        _authorizedCaller[busdFeeder2] = true; // tester: to allow call to updateEmissionSettings
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    //update money reward count per block
    function updateMoneyPerBlock(uint256 _moneyPerBlock) external onlyOwner {
        require(_moneyPerBlock != 0, "MasterChefMoney.updateMoneyPerBlock: Reward token count per block can't be zero");
        moneyPerBlock = _moneyPerBlock;
        // emitts event when moneyPerBlock updated
        emit MoneyPerBlockUpdated(_moneyPerBlock);
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    //update busd reward count per block
    function updateBusdPerBlock(uint256 _busdPerBlock) external onlyOwner {
        require(_busdPerBlock != 0, "MasterChefMoney.updateBusdPerBlock: Reward token count per block can't be zero");
        busdPerBlock = _busdPerBlock;
        // emitts event when busdPerBlock updated
        emit BusdPerBlockUpdated(_busdPerBlock);
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        bonusMultiplier = multiplierNumber;
        // AUDIT: MCM-08 | Missing Emit Events
        emit UpdateMultiplier(multiplierNumber);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // Add a new lp to the pool. Can only be called by the owner.
    function add (
        uint256 _allocPoint,
        IBEP20 _lpToken,
        uint256 _burnRate,
        uint256 _emergencyBurnRate,
        uint256 _lockPeriod,
        uint256 _depositFee,
        bool _depositBurn,
        bool _secondaryReward,
        bool _withUpdate
    ) external onlyOwner {
        // AUDIT: MCM-21 | The Logic Issue of add()
        if( poolInfo.length == 0 ) {
            require ( busdToken == _lpToken, "add: first pool should be busd pool") ;
        } else {
            require(busdToken != _lpToken,"busd pool already added" );
        }

        require(_depositFee <= 1000, "add: invalid deposit fee basis points");
        require(_burnRate <= 10000, "add: invalid deposit fee basis points");
        require(_emergencyBurnRate <= 2500, "add: invalid emergency brun rate basis points");
        require(_lockPeriod <= 30 days, "add: invalid lock period");

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
        block.number > startBlock ? block.number : startBlock;

        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        if(_secondaryReward) {
            totalBusdAllocPoint = totalBusdAllocPoint.add(_allocPoint);
        }
        poolInfo.push(
            PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accMoneyPerShare: 0,
        accBusdPerShare: 0,
        burnRate: _burnRate,
        emergencyBurnRate: _emergencyBurnRate,
        lockPeriod: _lockPeriod,
        depositFee: _depositFee,
        depositBurn: _depositBurn,
        secondaryReward: _secondaryReward
        })
        );
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Update the given pool's money allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _burnRate,
        uint256 _emergencyBurnRate,
        uint256 _lockPeriod,
        uint256 _depositFee,
        bool _depositBurn,
        bool _secondaryReward,
        bool _withUpdate
    ) external onlyOwner validatePoolByPid(_pid){
        require(_depositFee <= 1000, "set: invalid deposit fee basis points");
        require(_burnRate <= 10000, "set: invalid deposit fee basis points");
        require(_emergencyBurnRate <= 2500, "set: invalid emergency brun rate basis points");
        require(_lockPeriod <= 30 days, "set: invalid lock period");

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].burnRate = _burnRate;
        poolInfo[_pid].emergencyBurnRate = _emergencyBurnRate;
        poolInfo[_pid].lockPeriod = _lockPeriod;
        poolInfo[_pid].depositFee = _depositFee;
        poolInfo[_pid].depositBurn = _depositBurn;


        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(
                _allocPoint
            );
        }
        if(_secondaryReward) {
            totalBusdAllocPoint = totalBusdAllocPoint.add(_allocPoint);
        }
        if(poolInfo[_pid].secondaryReward) {
            totalBusdAllocPoint = totalBusdAllocPoint.sub(prevAllocPoint);
        }
        poolInfo[_pid].secondaryReward = _secondaryReward;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
    public
    view
    returns (uint256)
    {
        return _to.sub(_from).mul(bonusMultiplier);
    }

    // Return reward multiplier over the given _from to _to block.
    function getBusdMultiplier(uint256 _from, uint256 _to)
    public
    view
    returns (uint256)
    {
        if (_to <= busdEndBlock) {
            return _to.sub(_from).mul(bonusMultiplier);
        } else if (_from >= busdEndBlock) {
            return 0;
        } else {
            return busdEndBlock.sub(_from).mul(bonusMultiplier);
        }
    }

    function getBusdBalance() public view returns (uint256) {
        uint256 balance = busdToken.balanceOf(address(this)).sub(poolDeposit[busdPoolId]);
        return balance;
    }

    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // View function to see pending moneys and busd on frontend.
    function pendingReward(uint256 _pid, address _user)
    external
    view
    validatePoolByPid(_pid)
    returns (uint256, uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMoneyPerShare = pool.accMoneyPerShare;
        uint256 accBusdPerShare = pool.accBusdPerShare;
        uint256 lpSupply = poolDeposit[_pid];

        uint256 moneyPendingReward;
        uint256 busdPendingReward;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
            getMultiplier(pool.lastRewardBlock, block.number);
            uint256 moneyReward =
            multiplier.mul(moneyPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
            accMoneyPerShare = accMoneyPerShare.add(
                moneyReward.mul(1e12).div(lpSupply)
            );
            if(pool.secondaryReward) {
                uint256 busdMultiplier = getBusdMultiplier(pool.lastRewardBlock, block.number);
                uint256 busdReward =
                busdMultiplier.mul(busdPerBlock).mul(pool.allocPoint).div(
                    totalBusdAllocPoint
                );
                accBusdPerShare = accBusdPerShare.add(
                    busdReward.mul(1e12).div(lpSupply)
                );
            }
        }
        moneyPendingReward = user.amount.mul(accMoneyPerShare).div(1e12).sub(user.rewardDebt).add(user.moneyRewardLockedUp);
        // AUDIT: MCM-16 | Calculation of busdPendingReward
        // AUDIT: MCM-23 | Set The secondaryReward
        // DEV: busd reward will be 0 if pool.secondaryReward is false.
        // DEV: becuase accBusdPerShare and busdRewardDebt are 0 in non 2nd reward pools.
        // DEV: We already did test for this.
        busdPendingReward = user.amount.mul(accBusdPerShare).div(1e12).sub(user.busdRewardDebt).add(user.busdRewardLockedUp);

        return (moneyPendingReward, busdPendingReward);
    }


    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = poolDeposit[_pid];
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 moneyReward =
        multiplier.mul(moneyPerBlock).mul(pool.allocPoint).div(
            totalAllocPoint
        );
        // AUDIT: MCM-10 | Over Minted Token
        // DEV: we prefer to keep 108% emission model.
        money.mint(devaddr, moneyReward.mul(800).div(10000));
        money.mint(address(this), moneyReward);
        pool.accMoneyPerShare = pool.accMoneyPerShare.add(
            moneyReward.mul(1e12).div(lpSupply)
        );
        if(pool.secondaryReward) {
            uint256 busdMultiplier = getBusdMultiplier(pool.lastRewardBlock, block.number);
            uint256 busdReward =
            busdMultiplier.mul(busdPerBlock).mul(pool.allocPoint).div(
                totalBusdAllocPoint
            );
            pool.accBusdPerShare = pool.accBusdPerShare.add(
                busdReward.mul(1e12).div(lpSupply)
            );
        }
        pool.lastRewardBlock = block.number;
    }

    function payOrLockupPendingMoney(address _recipient, uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_recipient];

        uint256 pending = user.amount.mul(pool.accMoneyPerShare).div(1e12).sub(user.rewardDebt).add(user.moneyRewardLockedUp);
        uint256 pendingBusd = user.amount.mul(pool.accBusdPerShare).div(1e12).sub(user.busdRewardDebt).add(user.busdRewardLockedUp);
        if (pool.lockPeriod > 0 ) {
            user.moneyRewardLockedUp = user.moneyRewardLockedUp.add(pending);
            user.busdRewardLockedUp = user.busdRewardLockedUp.add(pendingBusd);
            emit RewardLockedUp(_recipient, _pid, pending, pendingBusd);
        } else {
            if (pending > 0) {
                safeMoneyTransfer(_recipient, pending);
            }
        }
    }
    // AUDIT: MCM-01 | Proper Usage of public and external
    function deposit(uint256 _pid, uint256 _amount) external {
        depositFor(msg.sender, _pid, _amount);
    }

    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Deposit LP tokens to MasterChef for money allocation.
    function depositFor(address _recipient, uint256 _pid, uint256 _amount) public validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_recipient];
        updatePool(_pid);

        // AUDIT: MCM-22 | The Logic Issue Of UnDistributed Rewards
        // DEV: There is no harvest Action in lock pool, once user deposit again in lock pool
        // DEV: We save user's reward amount, that's why rewardDebt is not updated in lock pool.

        if (user.amount > 0) {
            // TESTER: I thing that you need to run this block on every deposit.
            payOrLockupPendingMoney(_recipient, _pid);
        }
        if (_amount > 0) {
            if(pool.depositFee > 0)
            {
                uint256 tax = _amount.mul(pool.depositFee).div(maxShare);
                uint256 received = _amount.sub(tax);
                if(pool.depositBurn){
                    pool.lpToken.safeTransferFrom(address(msg.sender), BURN_ADDRESS, tax);
                }
                else {
                    pool.lpToken.safeTransferFrom(address(msg.sender), devaddr, tax);
                }
                // MCM-05 | Incompatibility With Deflationary Tokens
                uint256 oldBalance = pool.lpToken.balanceOf(address(this));
                pool.lpToken.safeTransferFrom(address(msg.sender), address(this), received);
                uint256 newBalance = pool.lpToken.balanceOf(address(this));
                received = newBalance.sub(oldBalance);
                //add user deposit amount to the total pool deposit amount
                poolDeposit[_pid] = poolDeposit[_pid].add(received);
                user.amount = user.amount.add(received);
                userIndex(_pid, _recipient);
            }
            else{
                uint256 oldBalance = pool.lpToken.balanceOf(address(this));
                pool.lpToken.safeTransferFrom(
                    address(msg.sender),
                    address(this),
                    _amount
                );
                uint256 newBalance = pool.lpToken.balanceOf(address(this));
                _amount = newBalance.sub(oldBalance);
                //add user deposit amount to the total pool deposit amount
                poolDeposit[_pid] = poolDeposit[_pid].add(_amount);
                user.amount = user.amount.add(_amount);
                userIndex(_pid, _recipient);
            }

            user.lastDepositTime = _getNow();
        }

        user.rewardDebt = user.amount.mul(pool.accMoneyPerShare).div(1e12);
        user.busdRewardDebt = user.amount.mul(pool.accBusdPerShare).div(1e12);
        emit Deposit(_recipient, _pid, _amount);
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if(pool.lockPeriod > 0){
            require(user.amount == _amount, "withdraw: Should unstake 100% of time token");
        }
        else {
            require(user.amount >= _amount, "withdraw: not good");
        }

        updatePool(_pid);

        poolDeposit[_pid] = poolDeposit[_pid].sub(_amount);

        if (pool.lockPeriod > 0 ) {
            if(_getNow() < user.lastDepositTime + pool.lockPeriod) {
                if (_amount > 0) {
                    user.amount = user.amount.sub(_amount);
                    userIndex(_pid, msg.sender);
                    uint256 tax = _amount.mul(pool.emergencyBurnRate).div(maxShare);
                    uint256 sent = _amount.sub(tax);
                    pool.lpToken.safeTransfer(BURN_ADDRESS, tax );
                    pool.lpToken.safeTransfer(address(msg.sender), sent );
                    emit Burn(msg.sender, _pid, sent, tax);
                }
                user.moneyRewardLockedUp = 0;
                user.busdRewardLockedUp = 0;
                user.rewardDebt = user.amount.mul(pool.accMoneyPerShare).div(1e12);
                user.busdRewardDebt = user.amount.mul(pool.accBusdPerShare).div(1e12);
                emit Withdraw(msg.sender, _pid, _amount);
            }else{
                uint256 pending = user.amount.mul(pool.accMoneyPerShare).div(1e12).sub(user.rewardDebt).add(user.moneyRewardLockedUp);
                if (pending > 0) {
                    safeMoneyTransfer(msg.sender, pending);
                }
                if(pool.secondaryReward) { // TESTER: moved outside as pendingBusd is checked
                    uint256 pendingBusd = user.amount.mul(pool.accBusdPerShare).div(1e12).sub(user.busdRewardDebt).add(user.busdRewardLockedUp);
                    if( pendingBusd > 0 ){
                        safeBusdTransfer(msg.sender, pendingBusd); // TESTER: change pool.lpToken to busdToken
                    }
                }
                if (_amount > 0) {
                    user.amount = user.amount.sub(_amount);
                    userIndex(_pid, msg.sender);
                    if(pool.burnRate == maxShare)
                        pool.lpToken.safeTransfer(BURN_ADDRESS, _amount );
                    else
                    {
                        uint256 tax = _amount.mul(pool.burnRate).div(maxShare);
                        uint256 sent = _amount.sub(tax);
                        pool.lpToken.safeTransfer(BURN_ADDRESS, tax );
                        pool.lpToken.safeTransfer(address(msg.sender), sent );
                    }
                }
                user.moneyRewardLockedUp = 0;
                user.busdRewardLockedUp = 0;
                user.rewardDebt = user.amount.mul(pool.accMoneyPerShare).div(1e12);
                user.busdRewardDebt = user.amount.mul(pool.accBusdPerShare).div(1e12);

                emit Withdraw(msg.sender, _pid, _amount);
            }
        } else {
            uint256 pending = user.amount.mul(pool.accMoneyPerShare).div(1e12).sub(user.rewardDebt).add(user.moneyRewardLockedUp);
            if (pending > 0) {
                safeMoneyTransfer(msg.sender, pending);
            }
            if(pool.secondaryReward) {
                // TESTER: adding secondary reward here too (if no lock).
                // why? bcs reward is computed with and without lock on updatePool
                uint256 pendingBusd = user.amount.mul(pool.accBusdPerShare).div(1e12).sub(user.busdRewardDebt).add(user.busdRewardLockedUp);
                if( pendingBusd > 0 ){
                    safeBusdTransfer(msg.sender, pendingBusd); // TESTER: change pool.lpToken to busdToken
                }
            }
            if (_amount > 0) {
                user.amount = user.amount.sub(_amount);
                userIndex(_pid, msg.sender);
                pool.lpToken.safeTransfer(address(msg.sender), _amount);
            }
            user.moneyRewardLockedUp = 0;
            user.busdRewardLockedUp = 0;
            user.rewardDebt = user.amount.mul(pool.accMoneyPerShare).div(1e12);
            // AUDIT: MCM-17 | user.busdRewardDebt Not Updated
            user.busdRewardDebt = user.amount.mul(pool.accBusdPerShare).div(1e12);
            emit Withdraw(msg.sender, _pid, _amount);
        }
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        // AUDIT: MCM-19 | The logical Issue of emergencyWithdraw ()
        // DEV: There is no emergencyWithdraw feature in Lock pools.
        require(pool.lockPeriod == 0, "use withdraw");
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        poolDeposit[_pid] = poolDeposit[_pid].sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.busdRewardDebt = 0; // TESTER: critical bug correction!
        user.moneyRewardLockedUp = 0;
        user.busdRewardLockedUp = 0;
        // AUDIT: MCM-16 | Calling Function userIndex Before Balance Updating
        userIndex(_pid, msg.sender);
    }

    // Safe money transfer function, just in case if rounding error causes pool to not have enough moneys.
    function safeMoneyTransfer(address _to, uint256 _amount) internal {
        uint256 balance = money.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > balance) {
            transferSuccess = money.transfer(_to, balance);
        } else {
            transferSuccess = money.transfer(_to, _amount);
        }
        emit Transfer(_to, _amount, balance); // TESTER: let's emit event here
        require(transferSuccess, "transfer failed");
    }

    // Safe busd transfer function, just in case if rounding error causes pool to not have enough busd.
    function safeBusdTransfer(address _to, uint256 _amount) internal {
        uint256 balance = getBusdBalance();
        bool transferSuccess = false;
        if (_amount > balance) {
            transferSuccess = busdToken.transfer(_to, balance);
        } else {
            transferSuccess = busdToken.transfer(_to, _amount);
        }
        emit Transfer(_to, _amount, balance); // TESTER: let's emit event here
        require(transferSuccess, "transfer failed");
    }

    function updateEmissionSettings(uint256 _pid, uint256 _depositAmount, uint256 _endBlock) external onlyAuthorizedCaller {
        require(msg.sender == busdFeeder1 || msg.sender == busdFeeder2, "MasterChefMoney.updateEmissionSettings: msg sender should be busd feeder");
        require(_endBlock > block.number, "End block should be bigger than current block");
        updatePool(_pid);

        busdEndBlock = _endBlock;

        //TESTER: note that _from wallet must approve this contract before.
        // AUDIT: MCM-20 | Token Transfer In updateEmissionSettings
        // DEV: Msg.sender is not user's wallet. This is admin wallet which provide busd for 2nd reward in this contract.
        busdToken.safeTransferFrom(msg.sender, address(this), _depositAmount);
        uint256 busdBalance = getBusdBalance();
        uint256 blockCount = busdEndBlock.sub(block.number);
        busdPerBlock = busdBalance.div(blockCount);

        emit UpdateEmissionSettings(msg.sender, _depositAmount, _endBlock);
    }

    function setAuthorizedCaller(address caller, bool _status) onlyOwner external {
        require(caller != address(0), "MasterChefMoney.setAuthorizedCaller: Zero address");
        _authorizedCaller[caller] = _status;

        emit SetAuthorizedCaller(caller, _status);
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // Update dev address by the previous dev.
    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");

        // AUDIT: MCM-18 | Lack of Input Validation
        require(_devaddr != address(0), "dev: zero address");
        // AUDIT: MCM-08 | Missing Emit Events
        emit SetDev(devaddr, _devaddr);
        devaddr = _devaddr;
    }

    function setBusdFeeder1(address _busdFeeder1) onlyOwner external {
        require(_busdFeeder1 != address(0), "setBusdFeeder: zero address");
        busdFeeder1 = _busdFeeder1;
        emit SetBusdFeeder1(_busdFeeder1);
    }

    function setBusdFeeder2(address _busdFeeder2) onlyOwner external {
        require(_busdFeeder2 != address(0), "setBusdFeeder: zero address");
        busdFeeder2 = _busdFeeder2;
        emit SetBusdFeeder2(_busdFeeder2);
    }

    function _getNow() public virtual view returns (uint256) {
        return block.timestamp;
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    function totalUsersByPid( uint256 _pid ) external virtual view returns (uint256) {
        return addressByPid[_pid].getAllAddresses().length;
    }
    function usersByPid( uint256 _pid ) public virtual view returns (address[] memory) {
        return addressByPid[_pid].getAllAddresses();
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    function usersBalancesByPid( uint256 _pid ) external virtual view returns (UserInfo[] memory) {
        address[] memory list = usersByPid(_pid);
        UserInfo[] memory balances = new UserInfo[]( list.length );
        for (uint i = 0; i < list.length; i++) {
            address addr = list[i];
            balances[i] = userInfo[_pid][addr];
        }
        return balances;
    }
    function userIndex( uint256 _pid, address _user ) internal {
        AddrArrayLib.Addresses storage addr = addressByPid[_pid];

        uint256 amount = userInfo[_pid][_user].amount;
        // AUDIT: MCM-07 | Comparison to A Boolean Constant
        if( amount > 0 ){ // add user
            addr.pushAddress(_user);
        }else if( amount == 0 ){ // remove user
            addr.removeAddress(_user);
        }
    }

    // allow to change tax treasure via timelock
    function adminSetTaxAddr(address payable _taxTo) external onlyOwner {
        money.setTaxAddr(_taxTo);
    }

    // allow to change tax via timelock
    function adminSetTax(uint16 _tax) external onlyOwner {
        money.setTax(_tax);
    }

    // whitelist address (like vaults)
    function adminSetWhiteList(address _addr, bool _status) external onlyOwner {
        money.setWhiteList(_addr, _status);
    }

    // liquidity lock setting
    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        money.setSwapAndLiquifyEnabled(_enabled);
    }
}

/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

pragma experimental ABIEncoderV2;
import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';
import "./libs/ReentrancyGuard.sol";

import './libs/AddrArrayLib.sol';
import "./TimeToken.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterChef is the master of cake. He can make cake and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once cake is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefTime is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using AddrArrayLib for AddrArrayLib.Addresses;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of times
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTimePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTimePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. times to distribute per block.
        uint256 lastRewardBlock;  // Last block number that times distribution occurs.
        uint256 accTimePerShare; // Accumulated times per share, times 1e12. See below.
        uint256 depositFee; // Deposit Fee Percent of LP token
        uint256 withdrawFee; // Withdraw Fee Percent of LP token
        bool isBurn; // Burn Deposit Fee
    }

    // The time TOKEN!
    // AUDIT: MCT-02 | Set immutable to Variables
    TimeToken public immutable time;
    // Dev address.
    address public devaddr;
    // Withdraw Recipient address.
    address public withdrawRecipient;
    // Deposit Recipient address.
    address public depositRecipient;
    // Max percent with 2 decimal -> 10000 = 100%
    // AUDIT: MCT-03 | Set constant to Variables
    uint256 public constant maxShare = 10000;
    // time tokens created per block.
    uint256 public timePerBlock;
    // Bonus muliplier for early time makers.
    uint256 public bonusMultiplier = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping(uint256 => AddrArrayLib.Addresses) private addressByPid;
    mapping(uint256 => uint[]) public userIndexByPid;

    // AUDIT: MCT-06 | add() Function Not Restricted
    // The Staking token list
    mapping (address => bool) private stakingTokens;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when time mining starts.
    // AUDIT: MCT-02 | Set immutable to Variables
    uint256 public immutable startBlock;

    // AUDIT: MCT-03 | Set constant to Variables
    address public constant BURN_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, uint256 fee);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    event timePerBlockUpdated(uint256 timePerBlock);
    // AUDIT: MCT-05 | Missing indexed in Events
    event depositRecipientUpdated(address indexed depositRecipient);
    event withdrawRecipientUpdated(address indexed withdrawRecipient);
    event Transfer(address indexed to, uint256 requsted, uint256 sent);
    // AUDIT: MCT-04 | Missing Emit Events
    event UpdateMultiplier(uint256 multiplierNumber);

    event SetDev(address indexed prevDev, address indexed newDev);

    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "pool id not exisit");
        _;
    }

    constructor(
        TimeToken _time,
        address _devaddr,
        address _depositRecipient,
        address _withdrawRecipient,
        uint256 _timePerBlock,
        uint256 _startBlock
    ) public {
        require(address(_time) != address(0), "MasterChefTime.Constructor: Time token shouldn't be zero address");
        require(address(_devaddr) != address(0), "MasterChefTime.Constructor: Dev address shouldn't be zero address");
        require(_depositRecipient != address(0), "MasterChefTime.Constructor: Deposit recipient shouldn't be zero address");
        require(_withdrawRecipient != address(0), "MasterChefTime.Constructor: Withdraw recipient shouldn't be zero address");
        require(_timePerBlock != 0, "MasterChefTime.Constructor: Reward token count per block can't be zero");

        time = _time;
        devaddr = _devaddr;
        depositRecipient = _depositRecipient;
        withdrawRecipient = _withdrawRecipient;
        timePerBlock = _timePerBlock;
        startBlock = _startBlock;
    }

    //update reward count per block
    // AUDIT: MCT-01 | Proper Usage of public and external
    function updateTimePerBlock(uint256 _timePerBlock) external onlyOwner {
        require(_timePerBlock != 0, "MasterChefTime.updateTimePerBlock: Reward token count per block can't be zero");
        timePerBlock = _timePerBlock;
        // emitts event when timePerBlock updated
        emit timePerBlockUpdated(_timePerBlock);
    }

    // AUDIT: MCT-01 | Proper Usage of public and external
    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        bonusMultiplier = multiplierNumber;
        // AUDIT: MCT-04 | Missing Emit Events
        emit UpdateMultiplier(multiplierNumber);
    }

    //update the address of depositRecipient
    // AUDIT: MCT-01 | Proper Usage of public and external
    function updateDepositRecipient(address _depositRecipient) external onlyOwner {
        require(_depositRecipient != address(0), "MasterChefTime.updateDepositRecipient: Recipient address cannot be zero");
        depositRecipient = _depositRecipient;
        // emitts event when depositRecipient address updated
        emit depositRecipientUpdated(depositRecipient);
    }
    //update the address of withdrawRecipient
    // AUDIT: MCT-01 | Proper Usage of public and external
    function updateWithdrawRecipient(address _withdrawRecipient) external onlyOwner {
        require(_withdrawRecipient != address(0), "MasterChefTime.updateWithdrawRecipient: Recipient address cannot be zero");
        withdrawRecipient = _withdrawRecipient;
        // emitts event when withdrawRecipient address updated
        emit withdrawRecipientUpdated(withdrawRecipient);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    // AUDIT: MCT-01 | Proper Usage of public and external
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint256 _depositFee, uint256 _withdrawFee, bool _isBurn, bool _withUpdate) external onlyOwner {
        // AUDIT: MCT-06 | add() Function Not Restricted
        require(!stakingTokens[address(_lpToken)], "MasterChefMoney.add: This staking token already added.");
        require(_depositFee <= 500, "add: invalid deposit fee basis points");
        require(_withdrawFee <= 199, "add: invalid withdraw fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accTimePerShare: 0,
        depositFee: _depositFee,
        withdrawFee: _withdrawFee,
        isBurn: _isBurn
        }));

        // AUDIT: MCT-06 | add() Function Not Restricted
        stakingTokens[address(_lpToken)] = true;
    }

    // Update the given pool's time allocation point, deposit fee and withdraw fee. Can only be called by the owner.
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function set(uint256 _pid, uint256 _allocPoint, uint256 _depositFee, uint256 _withdrawFee, bool _isBurn, bool _withUpdate) public onlyOwner validatePoolByPid(_pid){
        require(_depositFee <= 500, "set: invalid deposit fee basis points");
        require(_withdrawFee <= 199, "set: invalid withdraw fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFee = _depositFee;
        poolInfo[_pid].withdrawFee = _withdrawFee;
        poolInfo[_pid].isBurn = _isBurn;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(bonusMultiplier);
    }

    // View function to see pending time tokens on frontend.
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function pendingTime(uint256 _pid, address _user) external view validatePoolByPid(_pid) returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTimePerShare = pool.accTimePerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 timeReward = multiplier.mul(timePerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTimePerShare = accTimePerShare.add(timeReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accTimePerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function updatePool(uint256 _pid) public validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 timeReward = multiplier.mul(timePerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        time.mint(devaddr, timeReward.div(10));
        time.mint(address(this), timeReward);
        pool.accTimePerShare = pool.accTimePerShare.add(timeReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // AUDIT: MCT-01 | Proper Usage of public and external
    // AUDIT: MCT-07 | Check Effect Interaction Pattern Violated
    function deposit(uint256 _pid, uint256 _amount) external {
        depositFor(msg.sender, _pid, _amount);
    }

    // Deposit LP tokens to MasterChef for time allocation.
    function depositFor(address recipient, uint256 _pid, uint256 _amount) public validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][recipient];
        uint256 depositAmount = _amount;
        uint256 depositFeeAmount = 0;
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTimePerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTimeTransfer(recipient, pending);
            }
        }
        if (depositAmount > 0) {
            if(pool.depositFee > 0) {
                // Check if there is pool's deposit fee.
                depositFeeAmount = depositAmount.mul(pool.depositFee).div(maxShare);

                // Burn or send deposit fee to recipient
                if(pool.isBurn)
                    pool.lpToken.safeTransferFrom(address(msg.sender), BURN_ADDRESS, depositFeeAmount);
                else
                    pool.lpToken.safeTransferFrom(address(msg.sender), depositRecipient, depositFeeAmount);

                depositAmount = depositAmount.sub(depositFeeAmount);
            }
            uint256 oldBalance = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), depositAmount);
            uint256 newBalance = pool.lpToken.balanceOf(address(this));
            depositAmount = newBalance.sub(oldBalance);

            user.amount = user.amount.add(depositAmount);
            userIndex(_pid, recipient);
        }
        user.rewardDebt = user.amount.mul(pool.accTimePerShare).div(1e12);
        emit Deposit(recipient, _pid, depositAmount, depositFeeAmount);
    }

    // Withdraw LP tokens from MasterChef.
    // AUDIT: MCT-01 | Proper Usage of public and external
    // AUDIT: MCT-07 | Check Effect Interaction Pattern Violated
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function withdraw(uint256 _pid, uint256 _amount) external validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 withdrawAmount = _amount;
        require(user.amount >= withdrawAmount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTimePerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTimeTransfer(msg.sender, pending);
        }
        if(withdrawAmount > 0) {
            user.amount = user.amount.sub(withdrawAmount);
            userIndex(_pid, msg.sender);
            // avoid rounding errors on withdraw if fee=0
            if( pool.withdrawFee > 0 ){
                uint256 withdrawFeeAmount = withdrawAmount.mul(pool.withdrawFee).div(maxShare);
                pool.lpToken.safeTransfer(withdrawRecipient, withdrawFeeAmount);
                withdrawAmount = withdrawAmount.sub(withdrawFeeAmount);
            }
            pool.lpToken.safeTransfer(address(msg.sender), withdrawAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accTimePerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, withdrawAmount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // AUDIT: MCT-01 | Proper Usage of public and external
    // AUDIT: MCT-07 | Check Effect Interaction Pattern Violated
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function emergencyWithdraw(uint256 _pid) external validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 withdrawFeeAmount = user.amount.mul(pool.withdrawFee).div(maxShare);
        pool.lpToken.safeTransfer(withdrawRecipient, withdrawFeeAmount);
        pool.lpToken.safeTransfer(address(msg.sender), user.amount.sub(withdrawFeeAmount));

        emit EmergencyWithdraw(msg.sender, _pid, user.amount.sub(withdrawFeeAmount)); // TESTER: need to fix this

        user.amount = 0;
        user.rewardDebt = 0;

        userIndex(_pid, msg.sender);
    }

    function safeTimeTransfer(address _to, uint256 _amount) internal {
        uint256 balance = time.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > balance) {
            transferSuccess = time.transfer(_to, balance);
            emit Transfer(_to, _amount, balance);
        } else {
            transferSuccess = time.transfer(_to, _amount);
            emit Transfer(_to, _amount, balance);
        }
        require(transferSuccess, "transfer failed");
    }

    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");

        // AUDIT: MCM-18 | Lack of Input Validation
        require(_devaddr != address(0), "dev: zero address");

        emit SetDev(devaddr, _devaddr);
        devaddr = _devaddr;
    }

    // AUDIT: MCT-01 | Proper Usage of public and external
    function totalUsersByPid( uint256 _pid ) external virtual view returns (uint256) {
        return addressByPid[_pid].getAllAddresses().length;
    }
    function usersByPid( uint256 _pid ) public virtual view returns (address[] memory) {
        return addressByPid[_pid].getAllAddresses();
    }
    // AUDIT: MCT-01 | Proper Usage of public and external
    function usersBalancesByPid( uint256 _pid ) external virtual view returns (UserInfo[] memory) {
        address[] memory list = usersByPid(_pid);
        UserInfo[] memory balances = new UserInfo[]( list.length );
        for (uint i = 0; i < list.length; i++) {
            address addr = list[i];
            balances[i] = userInfo[_pid][addr];
        }
        return balances;
    }
    function userIndex( uint256 _pid, address _user ) internal {
        AddrArrayLib.Addresses storage addr = addressByPid[_pid];

        uint256 amount = userInfo[_pid][_user].amount;
        if( amount > 0 ){ // add user
            addr.pushAddress(_user);
        }else if( amount == 0 ){ // remove user
            addr.removeAddress(_user);
        }
    }

}

/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/GSN/Context.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/utils/Address.sol";

import "./interfaces.sol";


// MoneyToken with Governance.
contract MoneyToken is Context, IBEP20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;


    uint256 public tax;
    address payable public taxToAddrAddress;
    uint256 public constant maxTax = 100; // 10%
    mapping(address => bool) whitelist;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = false;

    IUniswapV2Router02 public  uniswapV2Router;
    address public  uniswapV2Pair;

    event transferInsufficient(address indexed from, address indexed to, uint256 total, uint256 balance);
    event whitelistedTransfer(address indexed from, address indexed to, uint256 total);
    event Transfer(address indexed sender, address indexed recipient, uint256 amount);

    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqiudity
    );
    event SetTaxAddr(address indexed taxTo);
    event SetTax(uint256 tax);
    event SetWhiteList(address indexed addr, bool status);

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(address payable _taxToAddrAddress, uint256 _tax)
    public
    {
        require(_tax <= maxTax, "INVALID TAX");
        require(_taxToAddrAddress != address(0), "Zero Address");
        _name = 'Money Token';
        _symbol = 'Money';
        _decimals = 18;
        taxToAddrAddress = _taxToAddrAddress;
        tax = _tax;
    }

    function init_router(address router) external onlyOwner {
        require(router != address(0), "MoneyToken.init_router: Zero Address");
        // TESTER: moving to a separate function to avoid breaking tests.
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(router);
        // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
        .createPair(address(this), _uniswapV2Router.WETH());

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;
    }

    function getOwner() external override view returns (address) {
        return owner();
    }
    function name() public override view returns (string memory) {
        return _name;
    }
    function decimals() external override view returns (uint8) {
        return _decimals;
    }
    function symbol() external override view returns (string memory) {
        return _symbol;
    }
    function totalSupply() external override view returns (uint256) {
        return _totalSupply;
    }
    function balanceOf(address account) public override view returns (uint256) {
        return _balances[account];
    }
    function allowance(address owner, address spender) external override view returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(subtractedValue, 'BEP20: decreased allowance below zero')
        );
        return true;
    }
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), 'BEP20: mint to the zero address');

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), 'BEP20: approve from the zero address');
        require(spender != address(0), 'BEP20: approve to the zero address');

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }


    // ----------------------------------------------------------------
    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function setTaxAddr(address payable _taxToAddrAddress) external onlyOwner {
        require(_taxToAddrAddress != address(0), "MoneyToken.setTaxAddr: Zero Address");
        taxToAddrAddress = _taxToAddrAddress;
        emit SetTaxAddr(_taxToAddrAddress);
    }

    function setTax(uint256 _tax) external onlyOwner {
        require(_tax <= maxTax, "INVALID TAX");
        tax = _tax;
        emit SetTax(_tax);
    }

    function setWhiteList(address _addr, bool _status) external onlyOwner {
        require(_addr != address(0), "MoneyToken.setWhiteList: Zero Address");
        whitelist[_addr] = _status;
        emit SetWhiteList(_addr, _status);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (whitelist[recipient] || whitelist[msg.sender]) {
            _transfer(msg.sender, recipient, amount);
            _moveDelegates(_delegates[msg.sender], _delegates[recipient], amount);
            emit whitelistedTransfer(msg.sender, recipient, amount);
        } else {
            (uint256 _amount, uint256 _tax, uint256 _liquidity) = getTax(amount);
            if (!inSwapAndLiquify && _msgSender() != uniswapV2Pair
            && swapAndLiquifyEnabled && _liquidity > 0 // TODO -- we'd better use min swap threshold
            ) {// TODO -- else exception handler
                //add liquidity
                swapAndLiquify(_liquidity);
            }
            if (_tax > 0) {
                _transfer(msg.sender, taxToAddrAddress, _tax);
                _moveDelegates(_delegates[msg.sender], _delegates[taxToAddrAddress], _tax);
            }
            _transfer(msg.sender, recipient, _amount);
            _moveDelegates(_delegates[msg.sender], _delegates[recipient], _amount);
        }
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        if (whitelist[recipient] || whitelist[sender]) {
            _transfer(sender, recipient, amount);
            _moveDelegates(_delegates[sender], _delegates[recipient], amount);
            emit whitelistedTransfer(sender, recipient, amount);
        } else {
            (uint256 _amount, uint256 _tax, uint256 _liquidity) = getTax(amount);
            if (!inSwapAndLiquify && sender != uniswapV2Pair
            && swapAndLiquifyEnabled && _liquidity > 0 // TODO -- we'd better use min swap threshold
            ) {// TODO -- else exception handler
                //add liquidity
                swapAndLiquify(_liquidity);
            }
            if (_tax > 0) {
                _transfer(sender, taxToAddrAddress, _tax);
                _moveDelegates(_delegates[sender], _delegates[taxToAddrAddress], _tax);
            }
            _transfer(sender, recipient, _amount);
            _moveDelegates(_delegates[sender], _delegates[recipient], _amount);
        }
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), 'BEP20: transfer from the zero address');
        require(recipient != address(0), 'BEP20: transfer to the zero address');
        _balances[sender] = _balances[sender].sub(amount, 'BEP20: transfer amount exceeds balance');
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half);
        // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        (uint amountToken, uint amountETH, uint liquidity) = uniswapV2Router.addLiquidityETH{value : ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
        require(amountToken > 0 && amountETH > 0 && liquidity > 0);
        // send any dust to tax address:
        uint256 bnbAmount = address(this).balance;

        (bool transferSuccess,) = taxToAddrAddress.call{value : bnbAmount}("");
        require(transferSuccess, "MoneyToken.addLiquidity: Failed to send");
    }

    //to recieve ETH from uniswapV2Router when swapping
    receive() external payable {}

    function getTax(uint256 _total) private view returns (uint256 _amount, uint256 _amount_tax, uint256 _amount_liquidity){
        if (tax == 0) {
            return (_total, 0, 0);
        }
        if (tax > 0) {
            _amount_tax = _total.mul(tax).div(1000);
            _amount = _total.sub(_amount_tax);

            if (swapAndLiquifyEnabled) {
                _amount_liquidity = _amount_tax.div(2);
                // 50% of tax will be locked to LP
                _amount_tax = _amount_tax.sub(_amount_liquidity);
            }
        }
        return (_amount, _amount_tax, _amount_liquidity);
    }

    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);
    }
    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    /// @dev A record of each accounts delegate
    mapping(address => address) internal _delegates;

    /// @dev A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @dev A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @dev The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @dev The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @dev A record of states for signing / validating signatures
    mapping(address => uint) public nonces;

    /// @dev An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @dev An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /**
     * @dev Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator)
    external
    view
    returns (address)
    {
        return _delegates[delegator];
    }

    /**
     * @dev Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @dev Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
    external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "CAKE::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "CAKE::delegateBySig: invalid nonce");
        require(now <= expiry, "CAKE::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @dev Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
    external
    view
    returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @dev Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
    external
    view
    returns (uint256)
    {
        require(blockNumber < block.number, "CAKE::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2;
            // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
    internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator);
        // balance of underlying CAKEs (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
    internal
    {
        uint32 blockNumber = safe32(block.number, "CAKE::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2 ** 32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly {chainId := chainid()}
        return chainId;
    }
}

/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "@pancakeswap/pancake-swap-lib/contracts/GSN/Context.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/utils/Address.sol";

import "./interfaces.sol";


contract TimeToken is Context, IBEP20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;


    // this is a special token, not transferable
    mapping(address => bool) whitelist;

    event transferInsufficient(address indexed from, address indexed to, uint256 total, uint256 balance);
    event whitelistedTransfer(address indexed from, address indexed to, uint256 total);
    event Transfer(address indexed sender, address indexed recipient, uint256 amount);
    event SetWhiteList(address indexed addr, bool status);

    constructor()
    public
    {
        whitelist[_msgSender()] = true;
        _name = 'Time Token';
        _symbol = 'Time';
        _decimals = 18;
    }

    function getOwner() external override view returns (address) {
        return owner();
    }
    function name() public override view returns (string memory) {
        return _name;
    }
    function decimals() external override view returns (uint8) {
        return _decimals;
    }
    function symbol() external override view returns (string memory) {
        return _symbol;
    }
    function totalSupply() external override view returns (uint256) {
        return _totalSupply;
    }
    function balanceOf(address account) public override view returns (uint256) {
        return _balances[account];
    }
    function allowance(address owner, address spender) external override view returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(subtractedValue, 'BEP20: decreased allowance below zero')
        );
        return true;
    }
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), 'BEP20: mint to the zero address');

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), 'BEP20: approve from the zero address');
        require(spender != address(0), 'BEP20: approve to the zero address');

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }


    // ----------------------------------------------------------------

    function setWhiteList(address _addr, bool _status) external onlyOwner {
        require(_addr != address(0), "TimeToken.setWhiteList: Zero Address");
        whitelist[_addr] = _status;
        emit SetWhiteList(_addr, _status);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (whitelist[recipient] || whitelist[msg.sender]) {
            _transfer(msg.sender, recipient, amount);
            _moveDelegates(_delegates[msg.sender], _delegates[recipient], amount);
            emit whitelistedTransfer(msg.sender, recipient, amount);
        } else {
            require(false, 'TIME TOKEN CANNOT BE TRANSFERRED');
        }
        return true;
    }
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        if (whitelist[recipient] || whitelist[sender]) {
            _transfer(sender, recipient, amount);
            _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
            _moveDelegates(_delegates[sender], _delegates[recipient], amount);
            emit whitelistedTransfer(sender, recipient, amount);
        } else {
            require(false, 'TIME TOKEN CANNOT BE TRANSFERRED');
        }
        return true;
    }
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), 'BEP20: transfer from the zero address');
        require(recipient != address(0), 'BEP20: transfer to the zero address');
        _balances[sender] = _balances[sender].sub(amount, 'BEP20: transfer amount exceeds balance');
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}

    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) external onlyOwner{
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);
    }
    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    /// @dev A record of each accounts delegate
    mapping(address => address) internal _delegates;

    /// @dev A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @dev A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @dev The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @dev The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @dev A record of states for signing / validating signatures
    mapping(address => uint) public nonces;

    /// @dev An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @dev An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /**
     * @dev Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator)
    external
    view
    returns (address)
    {
        return _delegates[delegator];
    }

    /**
     * @dev Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @dev Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
    external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "CAKE::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "CAKE::delegateBySig: invalid nonce");
        require(now <= expiry, "CAKE::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @dev Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
    external
    view
    returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @dev Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
    external
    view
    returns (uint256)
    {
        require(blockNumber < block.number, "CAKE::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2;
            // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
    internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator);
        // balance of underlying CAKEs (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
    internal
    {
        uint32 blockNumber = safe32(block.number, "CAKE::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2 ** 32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly {chainId := chainid()}
        return chainId;
    }
}

/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "./MasterChefMoney.sol";
import "./MasterChefTime.sol";
import "./interfaces.sol";


contract AutoDistrubution is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    struct ProviderInfo{
        uint256 percent; // 1% = 1000
        address provider;
    }
    IUniswapV2Router02 public uniswapV2Router;

    IBEP20 public moneyToken;

    IBEP20 public busdToken;

    MasterChefMoney private masterChefMoney;
    MasterChefTime private masterChefTime;

    // uint8 private WALLET_1_POOLID = 4;
    // uint8 private WALLET_2_POOLID = 1;
    uint256 public maxPercent = 100000; // 100%

    address private BURN_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    address[10] private walletAddress = [0xc610422fBD4aB646b3A7b6144D706301a7d67e91,
                                         0xb2E9c3507c9867943152b74D0001Aa11279D70f8,
                                         0x1892569c7C00b3C7683730b71609F164024c4709,
                                         0x72400CE2A89F0C18BC003280D6263C34aFCA87AD,
                                         0xdc554288fC9100A54eD78fD1Cfa8FC6ef13FB05b,
                                         0x9270cb89a4a8aA44FC41B62dAC04ec79CC115fE7,
                                         0xba299E149981Bec61912642d83943519A429AAee,
                                         0x74345aA48E01cDe07918eAA266026a46F3018363,
                                         0x2b2D054FF40Fa09b8761a3ecBDC95Fc24563878f,
                                         0x6ef21724f67FC6AA5d6fAfF500dD14a0C8c65A8d];

    address[] public lpTokens;
    address[] public stakingTokens;

    mapping (address => uint256) feePercent;
    mapping (address => ProviderInfo[]) public providerInfo;

    constructor(
        IUniswapV2Router02 _uniswapV2Router,
        MasterChefMoney _masterChefMoney,
        MasterChefTime _masterChefTime,
        IBEP20 _moneyToken,
        IBEP20 _busdToken
    ) public {
        require(address(_uniswapV2Router) != address(0), "AutoDistrubution: router address is zero");
        require(address(_masterChefMoney) != address(0), "AutoDistrubution: masterchefMoney address is zero");
        require(address(_masterChefTime) != address(0), "AutoDistrubution: masterchefTime address is zero");
        require(address(_moneyToken) != address(0), "AutoDistrubution: money token address is zero");
        require(address(_busdToken) != address(0), "AutoDistrubution: busd token address is zero");

        uniswapV2Router = _uniswapV2Router;
        masterChefMoney = _masterChefMoney;
        masterChefTime = _masterChefTime;
        moneyToken = _moneyToken;
        busdToken = _busdToken;
    }

    // function to set timepool address
    function setMasterChefMoney(MasterChefMoney _masterChefMoney) external onlyOwner {
        require(address(_masterChefMoney) != address(0), "AutoDistrubution.setMasterChefMoney: masterchef address is zero");
        masterChefMoney = _masterChefMoney;
    }

    // function to set timepool address
    function setMasterChefTime(MasterChefTime _masterChefTime) external onlyOwner {
        require(address(_masterChefTime) != address(0), "AutoDistrubution.setMasterChefTime: masterchef address is zero");
        masterChefTime = _masterChefTime;
    }

    // function to check wallet is valid
    function checkWalletAddress(address _walletAddress) internal view returns (bool) {
        for(uint8 i=0; i < walletAddress.length; i++) {
            if (_walletAddress == walletAddress[i]) {
                return true;
            }
        }
        return false;
    }

    // function to add LP token
    function addLpToken(address _lpToken) external onlyOwner {
        require(_lpToken != address(0), "Zero Address");
        lpTokens.push(_lpToken);
    }

    // function to add LP token
    function addStakingToken(address _stakingToken) external onlyOwner {
        require(_stakingToken != address(0), "Zero Address");
        stakingTokens.push(_stakingToken);
    }
    // function to add LP token
    function addProvider(address _wallet, uint256 _percent, address _provider) external onlyOwner {
        require(_wallet != address(0), "Zero Address");
        require(checkWalletAddress(_wallet), "Invalid Wallet address");
        require(_provider != address(0), "Zero Address");
        require(_percent > 0 , "Invalid percent");
        ProviderInfo[] storage provider = providerInfo[_wallet];
        provider.push(
            ProviderInfo({
                percent: _percent,
                provider: _provider
            })
        );
    }

    function getFeeToWallet1() external onlyOwner {
        address wallet = walletAddress[0];
        for(uint256 i = 0; i < stakingTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];

            uint256 balance = IBEP20(stakingTokens[i]).balanceOf(provider[0].provider);
            if(balance > 0) {
                uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
                if(IBEP20(stakingTokens[i]) == busdToken ) {
                    IBEP20(stakingTokens[i]).safeTransferFrom(provider[0].provider, wallet, amount);
                } else {
                    IBEP20(stakingTokens[i]).safeTransferFrom(provider[0].provider, address(this), amount);
                    swapTokensForBusd(amount, stakingTokens[i], wallet);
                }
            }
        }
    }

    function getFeeToWallet2() external onlyOwner {
        address wallet = walletAddress[1];
        for(uint256 i = 0; i < stakingTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];
            for(uint256 j = 0; j < provider.length; j++ ) {
                uint256 balance = IBEP20(stakingTokens[i]).balanceOf(provider[j].provider);
                if(balance > 0) {
                    uint256 amount = balance.mul(provider[j].percent).div(maxPercent);
                    if(IBEP20(stakingTokens[i]) == busdToken ) {
                        IBEP20(stakingTokens[i]).safeTransferFrom(provider[j].provider, wallet, amount);
                    } else {
                        IBEP20(stakingTokens[i]).safeTransferFrom(provider[j].provider, address(this), amount);
                        swapTokensForBusd(amount, stakingTokens[i], wallet);
                    }
                }
            }
        }
    }

    function buybackAndBurnMoney() external onlyOwner {
        // Wallet 3 and wallet 4
        for(uint256 i = 2; i < 4; i++)
        {
            address wallet = walletAddress[i];
            for(uint256 j = 0; j < stakingTokens.length; j++ ) {
                ProviderInfo[] memory provider = providerInfo[wallet];

                uint256 balance = IBEP20(stakingTokens[j]).balanceOf(provider[0].provider);
                uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
                IBEP20(stakingTokens[j]).safeTransferFrom(provider[0].provider, address(this), amount);
                swapTokensForMoney(amount, stakingTokens[j], BURN_ADDRESS);
            }
        }
    }

    function getFeeToWallet5() external onlyOwner {
        address wallet = walletAddress[4];
        for(uint256 i = 0; i < lpTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];
            uint256 balance = IBEP20(lpTokens[i]).balanceOf(provider[0].provider);
            uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
            IBEP20(lpTokens[i]).safeTransferFrom(provider[0].provider, wallet, amount);
        }
    }

    function getFeeToWallet6() external onlyOwner {
        address wallet = walletAddress[4];
        address[] memory moneyBnbStakers = masterChefTime.usersByPid(20);
        address[] memory moneyBusdStakers = masterChefTime.usersByPid(21);
        for(uint256 i = 0; i < lpTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];
            uint256 balance = IBEP20(lpTokens[i]).balanceOf(provider[0].provider);
            if(balance > 0) {
                uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
                IBEP20(lpTokens[i]).safeTransferFrom(provider[0].provider, address(this), amount);
                uint256 oldBalance = moneyToken.balanceOf(address(this));

                // cast to pair:
                IUniswapV2Pair pair = IUniswapV2Pair(lpTokens[i]);
                // used to extrac balances
                IBEP20 token0 = IBEP20(pair.token0());
                IBEP20 token1 = IBEP20(pair.token1());

                // remove liquidity
                uniswapV2Router.removeLiquidity(
                    pair.token0(), pair.token1(), pair.balanceOf(address(this)),
                    0, 0, address(this), block.timestamp+60);

                // swap tokens to our token:
                swapTokensForMoney( token0.balanceOf(address(this)), pair.token0(), address(this));
                swapTokensForMoney( token1.balanceOf(address(this)), pair.token1(), address(this));

                uint256 newBalance = moneyToken.balanceOf(address(this));
                uint256 busdPerShare = newBalance.sub(oldBalance).div(2).div(moneyBusdStakers.length);
                uint256 bnbPerShare = newBalance.sub(oldBalance).div(2).div(moneyBnbStakers.length);
                for(uint256 j = 0; j < moneyBnbStakers.length; j++) {
                    moneyToken.safeTransfer(moneyBnbStakers[j], bnbPerShare);
                }
                for(uint256 k = 0; k < moneyBusdStakers.length; k++) {
                    moneyToken.safeTransfer(moneyBusdStakers[k], busdPerShare);
                }
            }
        }
    }

    function getFeeToWallet7() external onlyOwner {
        address wallet = walletAddress[6];
        ProviderInfo[] memory provider = providerInfo[wallet];
        for(uint256 i = 0; i < stakingTokens.length; i++ ) {
            for(uint256 j = 0; j < 2; j++ ) {
                uint256 balance = IBEP20(stakingTokens[i]).balanceOf(provider[j].provider);
                if (balance > 0) {
                    uint256 amount = balance.mul(provider[j].percent).div(maxPercent);
                    IBEP20(stakingTokens[i]).safeTransferFrom(provider[j].provider, wallet, amount);
                }
            }
        }

        for(uint256 i = 0; i < lpTokens.length; i++ ) {
            uint256 balance = IBEP20(lpTokens[i]).balanceOf(provider[2].provider);
            if (balance > 0) {
                uint256 amount = balance.mul(provider[2].percent).div(maxPercent);
                IBEP20(lpTokens[i]).safeTransferFrom(provider[2].provider, wallet, amount);
            }
        }
    }

    function getFeeToWallet8() external onlyOwner {
        address wallet = walletAddress[7];
        ProviderInfo[] memory provider = providerInfo[wallet];
        uint256 balance = moneyToken.balanceOf(provider[0].provider);
        if (balance > 0) {
            moneyToken.safeTransferFrom(provider[0].provider, wallet, balance);
        }
    }

    function getFeeToWallet9() external onlyOwner {
        address wallet = walletAddress[8];
        address[] memory moneyBnbStakers = masterChefTime.usersByPid(20);
        address[] memory moneyBusdStakers = masterChefTime.usersByPid(21);
        require (moneyBnbStakers.length > 0 && moneyBusdStakers.length > 0 , "getFeeToWallet6: there is no money-bnb or money-busd stakers");
        ProviderInfo[] memory provider = providerInfo[wallet];
        uint256 balance = moneyToken.balanceOf(provider[0].provider);
        if (balance > 0) {
            uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
            moneyToken.safeTransferFrom(provider[0].provider, address(this), amount);
            uint256 busdPerShare = amount.div(2).div(moneyBusdStakers.length);
            uint256 bnbPerShare = amount.div(2).div(moneyBnbStakers.length);
            for(uint256 j = 0; j < moneyBnbStakers.length; j++) {
                moneyToken.safeTransfer(moneyBnbStakers[j], bnbPerShare);
            }
            for(uint256 k = 0; k < moneyBusdStakers.length; k++) {
                moneyToken.safeTransfer(moneyBusdStakers[k], busdPerShare);
            }
        }
    }

    function getFeeToWallet10() external onlyOwner {
        address wallet = walletAddress[9];
        address[] memory moneyBnbStakers = masterChefTime.usersByPid(20);
        address[] memory moneyBusdStakers = masterChefTime.usersByPid(21);
        require (moneyBnbStakers.length > 0 && moneyBusdStakers.length > 0 , "getFeeToWallet6: there is no money-bnb or money-busd stakers");
        for(uint256 i = 0; i < stakingTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];
            uint256 balance = IBEP20(stakingTokens[i]).balanceOf(provider[0].provider);
            if (balance > 0) {
                uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
                IBEP20(stakingTokens[i]).safeTransferFrom(provider[0].provider, address(this), amount);
                uint256 oldBalance = busdToken.balanceOf(address(this));
                swapTokensForBusd(amount, stakingTokens[i], address(this));
                uint256 newBalance = busdToken.balanceOf(address(this));
                uint256 busdPerShare = newBalance.sub(oldBalance).div(2).div(moneyBusdStakers.length);
                uint256 bnbPerShare = newBalance.sub(oldBalance).div(2).div(moneyBnbStakers.length);
                for(uint256 j = 0; j < moneyBnbStakers.length; j++) {
                    busdToken.safeTransfer(moneyBnbStakers[j], bnbPerShare);
                }
                for(uint256 k = 0; k < moneyBusdStakers.length; k++) {
                    busdToken.safeTransfer(moneyBusdStakers[k], busdPerShare);
                }
            }
        }
    }

    // function to swap LP token to Money token
    function swapTokensForMoney(uint balance, address token, address to) internal {

        // generate the uniswap pair path of token -> money
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(moneyToken);

        IBEP20(token).approve(address(uniswapV2Router), balance);

        // make the swap
        uniswapV2Router.swapExactTokensForTokens(
            balance,
            0, // accept any amount of money
            path,
            to,
            block.timestamp+60
        );
    }

    // function to swap LP token to Money token
    function swapTokensForBusd(uint amountIn, address tokenA, address to) internal {
        // generate the uniswap pair path of token -> money
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = address(busdToken);

        IBEP20(tokenA).approve(address(uniswapV2Router), amountIn);

        // make the swap
        uniswapV2Router.swapExactTokensForTokens(
            amountIn,
            0, // accept any amount of money
            path,
            to,
            block.timestamp+60
        );
    }
}

/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}


interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}


interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}


interface IUniswapV2Router02 is IUniswapV2Router01 {

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external override returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external override returns (uint amountToken, uint amountETH);

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

/*
  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*/
/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

library AddrArrayLib {
    using AddrArrayLib for Addresses;

    struct Addresses {
        address[]  _items;
    }

    /**
     * @notice push an address to the array
     * @dev if the address already exists, it will not be added again
     * @param self Storage array containing address type variables
     * @param element the element to add in the array
     */
    function pushAddress(Addresses storage self, address element) internal {
        if (!exists(self, element)) {
            self._items.push(element);
        }
    }

    /**
     * @notice remove an address from the array
     * @dev finds the element, swaps it with the last element, and then deletes it;
     *      returns a boolean whether the element was found and deleted
     * @param self Storage array containing address type variables
     * @param element the element to remove from the array
     */
    function removeAddress(Addresses storage self, address element) internal returns (bool) {
        for (uint i = 0; i < self.size(); i++) {
            if (self._items[i] == element) {
                self._items[i] = self._items[self.size() - 1];
                self._items.pop();
                return true;
            }
        }
        return false;
    }

    /**
     * @notice get the address at a specific index from array
     * @dev revert if the index is out of bounds
     * @param self Storage array containing address type variables
     * @param index the index in the array
     */
    function getAddressAtIndex(Addresses storage self, uint256 index) internal view returns (address) {
        require(index < size(self), "the index is out of bounds");
        return self._items[index];
    }

    /**
     * @notice get the size of the array
     * @param self Storage array containing address type variables
     */
    function size(Addresses storage self) internal view returns (uint256) {
        return self._items.length;
    }

    /**
     * @notice check if an element exist in the array
     * @param self Storage array containing address type variables
     * @param element the element to check if it exists in the array
     */
    function exists(Addresses storage self, address element) internal view returns (bool) {
        for (uint i = 0; i < self.size(); i++) {
            if (self._items[i] == element) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice get the array
     * @param self Storage array containing address type variables
     */
    function getAllAddresses(Addresses storage self) internal view returns(address[] memory) {
        return self._items;
    }

}

/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () internal {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.4.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor() internal {}

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.4.0;

import '../GSN/Context.sol';

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), 'Ownable: caller is not the owner');
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), 'Ownable: new owner is the zero address');
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.4.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, 'SafeMath: addition overflow');

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, 'SafeMath: subtraction overflow');
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, 'SafeMath: multiplication overflow');

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, 'SafeMath: division by zero');
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, 'SafeMath: modulo by zero');
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x < y ? x : y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
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
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.4.0;

interface IBEP20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view returns (address);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address _owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import './IBEP20.sol';
import '../../math/SafeMath.sol';
import '../../utils/Address.sol';

/**
 * @title SafeBEP20
 * @dev Wrappers around BEP20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeBEP20 for IBEP20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeBEP20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(
        IBEP20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IBEP20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IBEP20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            'SafeBEP20: approve from non-zero to non-zero allowance'
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(
            value,
            'SafeBEP20: decreased allowance below zero'
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IBEP20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, 'SafeBEP20: low-level call failed');
        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), 'SafeBEP20: BEP20 operation did not succeed');
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
        // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
        // for accounts without code, i.e. `keccak256('')`
        bytes32 codehash;
        bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            codehash := extcodehash(account)
        }
        return (codehash != accountHash && codehash != 0x0);
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, 'Address: insufficient balance');

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{value: amount}('');
        require(success, 'Address: unable to send value, recipient may have reverted');
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, 'Address: low-level call failed');
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, 'Address: low-level call with value failed');
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, 'Address: insufficient balance for call');
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(
        address target,
        bytes memory data,
        uint256 weiValue,
        string memory errorMessage
    ) private returns (bytes memory) {
        require(isContract(target), 'Address: call to non-contract');

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{value: weiValue}(data);
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "evmVersion": "istanbul",
  "libraries": {},
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  }
}