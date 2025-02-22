pragma solidity 0.8.0;

// SPDX-License-Identifier: MIT



import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/IERC20Burnable.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IBuyBack.sol";
import "./interfaces/IFairLaunch.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IRelationship.sol";


import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice GymVaultsBank contract:
 * - Users can:
 *   # Deposit token
 *   # Deposit BNB
 *   # Withdraw assets
 */

contract GymVaultsBank is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /**
        * @notice Info of each user
        * @param shares: How many LP tokens the user has provided
        * @param rewardDebt: Reward debt. See explanation below
        * @dev Any point in time, the amount of UTACOs entitled to a user but is pending to be distributed is:
        *   amount = user.shares / sharesTotal * wantLockedTotal
        *   pending reward = (amount * pool.accRewardPerShare) - user.rewardDebt
        *   Whenever a user deposits or withdraws want tokens to a pool. Here's what happens:
        *   1. The pool's `accRewardPerShare` (and `lastStakeTime`) gets updated.
        *   2. User receives the pending reward sent to his/her address.
        *   3. User's `amount` gets updated.
        *   4. User's `rewardDebt` gets updated.
    */
    struct UserInfo {
        uint256 shares;
        uint256 rewardDebt;
        uint256 lastStakeTime;
    }
    /**
     * @notice Info of each pool
     * @param want: Address of want token contract
     * @param allocPoint: How many allocation points assigned to this pool. GYM to distribute per block
     * @param lastRewardBlock: Last block number that reward distribution occurs
     * @param accUTacoPerShare: Accumulated rewardPool per share, times 1e18
     * @param strategy: Address of strategy contract
     */
    struct PoolInfo {
        IERC20 want;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        address strategy;
    }

      /**
     * @notice Info of each rewartPool
     * @param rewardToken: Address of reward token contract
     * @param rewardPerBlock: How many reward tokens will user get per block
     * @param totalPaidRewards: Total amount of reward tokens was paid
     */

    struct RewardPoolInfo {
        address rewardToken;
        uint256 rewardPerBlock;
    }
  
    /// Percent of amount that will be sent to relationship contract
    uint256 public constant RELATIONSHIP_REWARD = 45;
    /// Percent of amount that will be sent to vault contract
    uint256 public constant VAULTS_SAVING = 45;
    /// Percent of amount that will be sent to buyBack contract
    uint256 public constant BUY_AND_BURN_GYM = 10;
    /// 100 = 1%
    uint256 public constant WITHDRAW_FEE_FACTOR_MAX = 10000; // 100 = 1%
    /// PancakeSwap: Router
    address public constant ROUTER_ADDRESS = 0x367633909278A3C91f4cB130D8e56382F00D1071; 

    /// Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint ; 
    /// Startblock number
    uint256 public startBlock; 
    uint256 public withdrawFee;
    ///buy and burn contract address
    address public buyBack; 
    address public relationship;
    /// Treasury address where will be sent all unused assets
    address public treasuryAddress;
    /// Info of each pool.
    PoolInfo[] public poolInfo;
    /// Info of each user that stakes want tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; 
    /// Info of reward pool
    RewardPoolInfo public rewardPoolInfo;

    address[] private alpacaToWBNB;


    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event RewardPaid(
        address indexed token,
        address indexed user,
        uint256 amount
    );
    
    constructor(
        uint256 _startBlock,
        address _gym,
        uint256 _gymRewardRate
    ){
        require(block.number < _startBlock, "GymVaultsBank: Start block must have a bigger value");
        startBlock = _startBlock;
        rewardPoolInfo = RewardPoolInfo({
            rewardToken: _gym, 
            rewardPerBlock: _gymRewardRate
        });
        alpacaToWBNB = [0x354b3a11D5Ea2DA89405173977E271F58bE2897D, 0xDfb1211E2694193df5765d54350e1145FD2404A1];
        emit Initialized(msg.sender, block.number);
    }

    modifier onlyOnRelationship() {
        require(IRelationship(relationship).isOnRelationship(msg.sender), "GymVaultsBank: Don't have relationship");
        _;
    }

    receive() external payable {}
    fallback() external payable {}
    
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @notice Function to set buyBack address
     * @param _buyBack: Address of BuyBack contract
     */
    function setBuyBackAddress(address _buyBack) external onlyOwner{
        buyBack = _buyBack;
    }

    /**
     * @notice Function to set relationship address
     * @param _relationship: Address of BuyBack contract
     */
    function setRelationship(address _relationship) external onlyOwner{
        relationship = _relationship;
    }

    /**
     * @notice Function to Add pool
     * @param _want: Address of want token contract
     * @param _allocPoint: AllocPoint for new pool
     * @param _withUpdate: If true will call massUpdatePools function
     * @param _strategy: Address of Strategy contract
     */
    function add(
        IERC20 _want,
        uint256 _allocPoint,
        bool _withUpdate,
        address _strategy
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = 
            block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
                PoolInfo({
                    want: _want,
                    allocPoint: _allocPoint,
                    lastRewardBlock: lastRewardBlock,
                    accRewardPerShare: 0,
                    strategy: _strategy
                })
            );
    }

    /**
     * @notice Update the given pool's reward allocation point. Can only be called by the owner
     * @param _pid: Pool id that will be updated
     * @param _allocPoint: New allocPoint for pool
     */
    function set(uint256 _pid, uint256 _allocPoint) external onlyOwner {
        massUpdatePools();
        totalAllocPoint = totalAllocPoint -
            poolInfo[_pid].allocPoint +
            _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /**
     * @notice Update the given pool's strategy. Can only be called by the owner
     * @param _pid: Pool id that will be updated
     * @param _strategy: New strategy contract address for pool
     */
    function resetStrategy(uint256 _pid, address _strategy)
        external
        onlyOwner
    {
        PoolInfo storage pool = poolInfo[_pid];
        require(
        pool.want.balanceOf(poolInfo[_pid].strategy) == 0 ||
                pool.accRewardPerShare == 0,
            "GymVaultsBank: Strategy not empty"
        );
        poolInfo[_pid].strategy = _strategy;
    }

    /**
     * @notice Migrates all assets to new strategy. Can only be called by the owner
     * @param _pid: Pool id that will be updated
     * @param _newStrategy: New strategy contract address for pool
     */
    function migrateStrategy(uint256 _pid, address _newStrategy)
        external
        onlyOwner
    {
        require(
            IStrategy(_newStrategy).wantLockedTotal() == 0 &&
                IStrategy(_newStrategy).sharesTotal() == 0,
            "GymVaultsBank: New strategy not empty"
        );
        PoolInfo storage pool = poolInfo[_pid];
        address _oldStrategy = pool.strategy;
        uint256 _oldSharesTotal = IStrategy(_oldStrategy).sharesTotal();
        uint256 _oldWantAmt = IStrategy(_oldStrategy).wantLockedTotal();
        IStrategy(_oldStrategy).withdraw(address(this), _oldWantAmt);
        pool.want.transfer(_newStrategy, _oldWantAmt);
        IStrategy(_newStrategy).migrateFrom(
            _oldStrategy,
            _oldWantAmt,
            _oldSharesTotal
        );
        pool.strategy = _newStrategy;
    }

    /**
     * @notice Updates amount of reward tokens  per block that user will get. Can only be called by the owner
     * @param _rewardPerBlock: Pool id that will be updated
     */
    function updateRewardPerBlock( uint256 _rewardPerBlock)
        external
        nonReentrant
        onlyOwner
    {
        massUpdatePools();
        rewardPoolInfo.rewardPerBlock = _rewardPerBlock;
    }

    /**
     * @notice View function to see pending reward on frontend.
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function pendingReward(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 _accRewardPerShare = pool.accRewardPerShare;
        uint256 sharesTotal = IStrategy(pool.strategy).sharesTotal();
        if (block.number > pool.lastRewardBlock && sharesTotal != 0) {
            uint256 _multiplier = block.number - pool.lastRewardBlock;
            uint256 _rewardPerBlock = rewardPoolInfo.rewardPerBlock;
            uint256 _reward =
                (_multiplier * _rewardPerBlock * pool.allocPoint) /
                    totalAllocPoint;
            _accRewardPerShare =
                _accRewardPerShare +
                ((_reward * 1e18) / sharesTotal);
        }
        return
            (user.shares * _accRewardPerShare) /
            1e18 -
            user.rewardDebt;
    }

    /**
     * @notice View function to see staked Want tokens on frontend.
     * @param _pid: Pool id where user has assets
     * @param _user: Users address
     */
    function stakedWantTokens(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = IStrategy(pool.strategy).sharesTotal();
        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strategy).wantLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return (user.shares * wantLockedTotal) / sharesTotal;
    }

    /**
     * @notice Update reward variables for all pools. Be careful of gas spending!
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date.
     * @param _pid: Pool id that will be updated
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 sharesTotal = IStrategy(pool.strategy).sharesTotal();
        if (sharesTotal == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number - pool.lastRewardBlock;
        if (multiplier <= 0) {
            return;
        }
        uint256 _rewardPerBlock = rewardPoolInfo.rewardPerBlock;
        uint256 _reward =
            (multiplier * _rewardPerBlock * pool.allocPoint) /
                totalAllocPoint;
        pool.accRewardPerShare =
            pool.accRewardPerShare +
            ((_reward * 1e18) / sharesTotal);
        pool.lastRewardBlock = block.number;
    }

    /**
     * @notice Calculates amount of reward user will get.
     * @param _pid: Pool id 
     */
    function _getReward(uint256 _pid) internal {
        PoolInfo storage _pool = poolInfo[_pid];
        UserInfo storage _user = userInfo[_pid][msg.sender];
        uint256 _pending =
            (_user.shares * _pool.accRewardPerShare) /
                (1e18) -
                (_user.rewardDebt);
        if (_pending > 0) {
            address _rewardToken = rewardPoolInfo.rewardToken;
            safeRewardTransfer(_rewardToken, msg.sender, _pending);
            emit RewardPaid(
                _rewardToken,
                msg.sender,
                _pending
            );
        }
    }

    /**
     * @notice Deposit in given pool
     * @param _pid: Pool id 
     * @param _wantAmt: Amount of want token that user wants to deposit 
     * @param _referrer: Referrer address  
     */
    function deposit(uint256 _pid, uint256 _wantAmt, address _referrer) external {
        IRelationship(relationship).addRelationship(msg.sender, _referrer);
        _deposit(_pid, _wantAmt, true);
    }

    /**
     * @notice Deposit in given pool
     * @param _pid: Pool id 
     * @param _wantAmt: Amount of want token that user wants to deposit 
     */
    function deposit(uint256 _pid, uint256 _wantAmt) external nonReentrant onlyOnRelationship {
        _deposit(_pid, _wantAmt, true);
    }

    /**
     * @notice Deposit BNB in core pool
     * @param _referrer: Referrer address  
     */
    function depositBNB( address _referrer) external payable{
        IRelationship(relationship).addRelationship(msg.sender, _referrer);
        depositBNB();
    }

    /**
     * @notice Deposit BNB in core pool
     */
    function depositBNB() public payable nonReentrant onlyOnRelationship{
        payable(relationship).transfer(msg.value * RELATIONSHIP_REWARD / 100);
        IRelationship(relationship).distributeRewards( msg.value * RELATIONSHIP_REWARD / 100, address(0), msg.sender, false);
        IWETH(0xDfb1211E2694193df5765d54350e1145FD2404A1).deposit{value: (msg.value - msg.value * RELATIONSHIP_REWARD / 100)}();
        _deposit(0, msg.value, false);
    }

     /**
     * @notice Private deposit function 
     * @param _pid: Pool id 
     * @param _wantAmt: Amount of want token that user wants to deposit 
     * @param _isToken: If false` given asset is BNB
     */
    function _deposit(uint256 _pid, uint256 _wantAmt, bool _isToken) private {
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.shares > 0) {
            _getReward(_pid);
        }
        if (_wantAmt > 0) {
            if(_isToken){
                pool.want.safeTransferFrom(
                    address(msg.sender),
                    address(this),
                    _wantAmt
                );
            pool.want.safeTransferFrom(
                address(msg.sender),
                relationship,
                msg.value * RELATIONSHIP_REWARD / 100
            );

            IRelationship(relationship).distributeRewards(_wantAmt * RELATIONSHIP_REWARD / 100, address(pool.want), msg.sender, true);
            }

            pool.want.safeTransfer(buyBack, _wantAmt * BUY_AND_BURN_GYM / 100);
            IBuyBack(buyBack).buyAndBurnToken(address(pool.want), _wantAmt * BUY_AND_BURN_GYM / 100, rewardPoolInfo.rewardToken);

            _wantAmt = _wantAmt * VAULTS_SAVING / 100;
            pool.want.safeIncreaseAllowance(pool.strategy, _wantAmt);
            uint256 sharesAdded =
                IStrategy(poolInfo[_pid].strategy).deposit(
                    msg.sender,
                    _wantAmt
                );

            user.shares = user.shares + sharesAdded;
            user.lastStakeTime = block.timestamp;
        }
        user.rewardDebt =
            (user.shares * (pool.accRewardPerShare)) /
            (1e18);
        emit Deposit(msg.sender, _pid, _wantAmt);
        if(_isToken)
        {
            pool.want.safeTransfer(treasuryAddress, pool.want.balanceOf(address(this)));
        }else{
            IWETH(0xDfb1211E2694193df5765d54350e1145FD2404A1).withdraw(IERC20(0xDfb1211E2694193df5765d54350e1145FD2404A1).balanceOf(address(this)));
            payable(treasuryAddress).transfer(address(this).balance);
        }
    }
    /**
     * @notice Withdraw user`s assets from pool 
     * @param _pid: Pool id 
     * @param _wantAmt: Amount of want token that user wants to withdraw 
     */
    function withdraw(uint256 _pid, uint256 _wantAmt) external nonReentrant {
        _withdraw(_pid, _wantAmt, true);
    }

    /**
     * @notice Withdraw user`s assets from core pool
     * @param _wantAmt: Amount of BNB that user wants to withdraw 
     */

    function withdrawBNB(uint256 _wantAmt) external nonReentrant {
        _withdraw(0, _wantAmt, false);
    }

     /**
     * @notice Private withdraw function 
     * @param _pid: Pool id 
     * @param _wantAmt: Amount of want token that user wants to withdraw 
     * @param _isToken: If false` given asset is BNB
     */
    function _withdraw(uint256 _pid, uint256 _wantAmt, bool _isToken) private { 
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strategy).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strategy).sharesTotal();

        require(user.shares > 0, "GymVaultsBank: user.shares is 0");
        require(sharesTotal > 0, "GymVaultsBank: sharesTotal is 0");

        _getReward(_pid);

        // Withdraw want tokens
        uint256 amount = (user.shares * (wantLockedTotal)) / (sharesTotal);
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved =
                IStrategy(poolInfo[_pid].strategy).withdraw(
                    msg.sender,
                    _wantAmt
                );
            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares - (sharesRemoved);
            }
            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }

            if (_wantAmt > 0) {
                if(_isToken){
                    pool.want.safeTransfer(address(msg.sender), _wantAmt * withdrawFee / WITHDRAW_FEE_FACTOR_MAX);
                    pool.want.safeTransfer(treasuryAddress, pool.want.balanceOf(address(this)));

                }else{
                    IWETH(0xDfb1211E2694193df5765d54350e1145FD2404A1).withdraw(_wantAmt);
                    payable(msg.sender).transfer(_wantAmt * withdrawFee / WITHDRAW_FEE_FACTOR_MAX);
                    payable(treasuryAddress).transfer(address(this).balance);
                }
            }
        }
        user.rewardDebt =
            (user.shares * (pool.accRewardPerShare)) /
            (1e18);
        
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    function withdrawAll(uint256 _pid) external {
        _withdraw(_pid, type(uint256).max, true);
    }

    function withdrawAllBNB() external {
        _withdraw(0, type(uint256).max, false);
    }

     /**
     * @notice View function, returns amount of BNB that user will get 
     * @param _user Address of user
     */
    function getBNBAmount(address _user) public view returns (uint256){
        PoolInfo memory pool = poolInfo[0];
        UserInfo memory user = userInfo[0][_user];
        uint256 wantLockedTotal = IStrategy(pool.strategy).wantLockedTotal();
        uint256 pendingAlpacaContract = IFairLaunchV1(0xac2fefDaF83285EA016BE3f5f1fb039eb800F43D).pendingAlpaca(1, pool.strategy);
        uint256 totalToken = IVault(0xf9d32C5E10Dd51511894b360e6bD39D7573450F9).totalToken();
        uint256 totalSupply = IERC20(0xf9d32C5E10Dd51511894b360e6bD39D7573450F9).totalSupply();
        uint256[] memory alpacaToBNBAmount = IPancakeRouter02(ROUTER_ADDRESS).getAmountsOut(pendingAlpacaContract, alpacaToWBNB);
        uint256 pendingBNBUser = user.shares * alpacaToBNBAmount[1] / wantLockedTotal;
        uint256 pendingIbBNB = pendingBNBUser * totalSupply / totalToken;

        uint256 userAmount = user.shares * IFairLaunchV1(0xac2fefDaF83285EA016BE3f5f1fb039eb800F43D).userInfo(1, pool.strategy).amount / wantLockedTotal;
        
        return totalToken * (userAmount + pendingIbBNB) / totalSupply;
    }

    /**
     * @notice  Safe transfer function for reward tokens 
     * @param _rewardToken Address of reward token contract
     * @param _to Address of reciever
     * @param _amount Amount of reward tokens to transfer
     */
    function safeRewardTransfer(
        address _rewardToken,
        address _to,
        uint256 _amount
    ) internal {
        uint256 _bal = IERC20(_rewardToken).balanceOf(address(this));
        if (_amount > _bal) {
            IERC20(_rewardToken).transfer(_to, _bal);
        } else {
            IERC20(_rewardToken).transfer(_to, _amount);
        }
    }

    /** 
     * @notice  Function to set Treasury address
     * @param _treasuryAddress Address of treasury address
    */
    function setTreasuryAddress(address _treasuryAddress)
        external
        nonReentrant
        onlyOwner
    {
        treasuryAddress = _treasuryAddress;
    } 

    /**
     * @notice  Function to set withdraw fee
     * @param _fee 100 = 1%
    */
    function setWithdrawFee(uint256 _fee) 
        external 
        nonReentrant
        onlyOwner
        {
            withdrawFee = _fee;
        }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

pragma solidity 0.8.0;

// SPDX-License-Identifier: MIT



interface IStrategy {
    // Total want tokens managed by strategy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    function wantAddress() external view returns (address);

    function token0Address() external view returns (address);

    function token1Address() external view returns (address);

    function earnedAddress() external view returns (address);

    function ratio0() external view returns (uint256);

    function ratio1() external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);

    // Main want token compounding function
    function earn() external;

    // Transfer want tokens autoFarm -> strategy
    function deposit(address _userAddress, uint256 _wantAmt) external returns (uint256);

    // Transfer want tokens strategy -> autoFarm
    function withdraw(address _userAddress, uint256 _wantAmt) external returns (uint256);

    function migrateFrom(address _oldStrategy, uint256 _oldWantLockedTotal, uint256 _oldSharesTotal) external;

    function inCaseTokensGetStuck(address _token, uint256 _amount, address _to) external;
}

pragma solidity 0.8.0;

// SPDX-License-Identifier: MIT


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Burnable is IERC20 {
    function burn(uint96 _amount) external;

    function burnFrom(address _account, uint96 _amount) external;
}

pragma solidity 0.8.0;

// SPDX-License-Identifier: MIT



interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);
}

pragma solidity 0.8.0;

// SPDX-License-Identifier: MIT



import "./IPancakeRouter01.sol";

interface IPancakeRouter02 is IPancakeRouter01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

pragma solidity 0.8.0;

// SPDX-License-Identifier: MIT


interface IBuyBack {
    function buyAndBurnToken(
        address,
        uint256,
        address
    ) external returns (uint256);
}

pragma solidity 0.8.0;
pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT



interface IFairLaunchV1 {
  // Data structure
  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
    uint256 bonusDebt;
    address fundedBy;
  }
  struct PoolInfo {
    address stakeToken;
    uint256 allocPoint;
    uint256 lastRewardBlock;
    uint256 accAlpacaPerShare;
    uint256 accAlpacaPerShareTilBonusEnd;
  }

  // Information query functions
  function alpacaPerBlock() external view returns (uint256);
  function totalAllocPoint() external view returns (uint256);
  function poolInfo(uint256 pid) external view returns (IFairLaunchV1.PoolInfo memory);
  function userInfo(uint256 pid, address user) external view returns (IFairLaunchV1.UserInfo memory);
  function poolLength() external view returns (uint256);

  // OnlyOwner functions
  function setAlpacaPerBlock(uint256 _alpacaPerBlock) external;
  function setBonus(uint256 _bonusMultiplier, uint256 _bonusEndBlock, uint256 _bonusLockUpBps) external;
  function manualMint(address _to, uint256 _amount) external;
  function addPool(uint256 _allocPoint, address _stakeToken, bool _withUpdate) external;
  function setPool(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external;

  // User's interaction functions
  function pendingAlpaca(uint256 _pid, address _user) external view returns (uint256);
  function updatePool(uint256 _pid) external;
  function deposit(address _for, uint256 _pid, uint256 _amount) external;
  function withdraw(address _for, uint256 _pid, uint256 _amount) external;
  function withdrawAll(address _for, uint256 _pid) external;
  function harvest(uint256 _pid) external;
}

pragma solidity 0.8.0;

// SPDX-License-Identifier: MIT


interface IVault {

  /// @dev Return the total ERC20 entitled to the token holders. Be careful of unaccrued interests.
  function totalToken() external view returns (uint256);

  /// @dev Add more ERC20 to the bank. Hope to get some good returns.
  function deposit(uint256 amountToken) external payable;

  /// @dev Withdraw ERC20 from the bank by burning the share tokens.
  function withdraw(uint256 share) external;

  /// @dev Request funds from user through Vault
  function requestFunds(address targetedToken, uint amount) external;

  function token() external view returns (address);
}

pragma solidity 0.8.0;

// SPDX-License-Identifier: MIT



interface IRelationship {
    function isOnRelationship(address _user) external view returns (bool);

    function addRelationship(address _user, address _referrer) external;

    function distributeRewards(
        uint256 _wantAmt,
        address _wantAddr,
        address _user,
        bool _isToken
    ) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

    constructor () {
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";
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
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

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
    function allowance(address owner, address spender) external view returns (uint256);

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
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

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

pragma solidity ^0.8.0;

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
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
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
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
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
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
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
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
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

pragma solidity 0.8.0;

// SPDX-License-Identifier: MIT



interface IPancakeRouter01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
    external
    returns (
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
    external
    payable
    returns (
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

{
  "optimizer": {
    "enabled": false,
    "runs": 200
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  },
  "metadata": {
    "useLiteralContent": true
  },
  "libraries": {}
}