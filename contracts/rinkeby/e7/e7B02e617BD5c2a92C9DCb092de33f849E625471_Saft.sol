// SPDX-License-Identifier: MIT
// StableUnit
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// SIMPLE AGREEMENT FOR FUTURE TOKENS (SAFT)
interface ISaft {
    // The parties agree as follows:
    // The Purchaser shall purchase Tokens from the Company in accordance with the following terms:
    struct PurchaserInfo {
        uint256 maximumTokenAllocation; // (1) Maximum number of suDAO Tokens to be purchased by the Purchaser
        uint256 pricePerToken;          // (2) Price, per one suDAO token
                                        // (3) Maximum purchase amount, for example 50,000 USDT
                                        //     calc as totalTokens*1e18 / pricePerToken
        IERC20 paymentMethod;           // (4) Payment method, for example USDT
        uint64 paymentDeadline;         // (5) Payment ultimate date.
        uint64 fullVestingTimestamp;   // (6) 12 months vesting period with 3 months cliff.
        uint64 cliffTimestamp;         // See https://www.unixtimestamp.com/

        uint256 _tokensBought;
        uint256 _tokensClaimed;
    }

    function purchase(address purchaser, uint256 payAmount) external;
    function availableToClaim(address purchaser) external view returns (uint256);
    function claimTokens() external;
}

contract Saft is ISaft, Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable suDAO;

    event AddedAccount(
        address account,
        uint256 maxRewardTokens,
        uint256 exchangeRate,
        IERC20 stakedToken,
        uint64 stakeEndTimestamp,
        uint64 rewardCliff,
        uint64 rewardTimestamp
    );
    event Staked(address account, uint256 stakedAmount);
    event ClaimedReward(address account, uint256 rewardAmount);


    mapping (address => PurchaserInfo) public presale;
    uint256 public totalTokensSold;

    function purchase(address purchaser, uint256 payAmount) external override {
        PurchaserInfo storage p = presale[purchaser];

        require(p.maximumTokenAllocation != 0,
            "purchase isn't initialized");
        require(block.timestamp <= p.paymentDeadline,
            "payment deadline is over");
        // for example, buy 100 = 10 dai / 0.1$/token
        uint256 purchaseAmount = payAmount * 1e18 / p.pricePerToken;
        require(p._tokensBought + purchaseAmount <= p.maximumTokenAllocation,
            "exceeded the purchase limit");
        // pay
        p.paymentMethod.safeTransferFrom(msg.sender, address(this), payAmount);
        // receive the purchaseToken
        p._tokensBought = p._tokensBought + purchaseAmount;
        totalTokensSold = totalTokensSold + purchaseAmount;
        //
        emit Staked(purchaser, purchaseAmount);
    }

    function tokenVested(address purchaser) public view returns (uint256) {
        PurchaserInfo memory p = presale[purchaser];
        require(p._tokensBought > 0, "no tokens purchased");
        // can't claim anything before cliff period is over
        if (block.timestamp <= p.cliffTimestamp) return 0;
        // after vesting is over - 100% of bought tokens are available to claim
        if (p.fullVestingTimestamp < block.timestamp) return p._tokensBought;
        // otherwise, in the period [cliff ... fullyVested] vesting is proportional to the time passed
        uint256 vestingPeriodSeconds = p.fullVestingTimestamp - p.cliffTimestamp;
        uint256 timeSinceCliffSeconds = p.fullVestingTimestamp - block.timestamp;
        return p._tokensBought * timeSinceCliffSeconds / vestingPeriodSeconds;
    }

    function availableToClaim(address purchaser) public view override returns (uint256) {
        return tokenVested(purchaser) - presale[purchaser]._tokensClaimed;
    }

    function claimTokens() external override {
        PurchaserInfo storage p = presale[msg.sender];
        require(p._tokensBought > 0,
            "nothing to claim");
        require(p.cliffTimestamp < block.timestamp,
            "cannot claim tokens before cliff is over");
        uint256 claimAmount = availableToClaim(msg.sender);
        // send claimAmount to the user and add that amount to tokenClaimed
        p._tokensClaimed = p._tokensClaimed + claimAmount;
        suDAO.safeTransfer(msg.sender, claimAmount);
        emit ClaimedReward(msg.sender, claimAmount);
    }

    constructor (IERC20 _suDAO) {
        suDAO = _suDAO;
    }

    function addPurchaser (
        address purchaser,
        uint256 tokenAllocation,
        uint256 pricePerToken,
        IERC20 paymentMethod,
        uint64 paymentPeriodSeconds,
        uint64 cliffSeconds,
        uint64 vestingPeriodSeconds
    ) external onlyOwner {
        // check that contract has enough tokens for 100% of purchasers
        uint256 totalUnsoldTokens = suDAO.balanceOf(address(this)) - totalTokensSold;
        require(totalUnsoldTokens >= tokenAllocation, "Don't have enough tokens to sell");
        // create account
        PurchaserInfo memory p = PurchaserInfo({
            maximumTokenAllocation: tokenAllocation,
            pricePerToken: pricePerToken,
            paymentMethod: paymentMethod,
            paymentDeadline: uint64(block.timestamp) + paymentPeriodSeconds,
            fullVestingTimestamp: uint64(block.timestamp) + vestingPeriodSeconds,
            cliffTimestamp: uint64(block.timestamp) + cliffSeconds,
            _tokensBought: 0,
            _tokensClaimed: 0
        });
        // save the account on blockchain
        presale[purchaser] = p;
        // log this information
        emit AddedAccount(
            purchaser,
            tokenAllocation,
            pricePerToken,
            paymentMethod,
            p.paymentDeadline,
            p.fullVestingTimestamp,
            p.cliffTimestamp
        );
    }

    function updatePaymentDeadline(address purchaser, uint64 newPaymentPeriodSeconds) external onlyOwner {
        PurchaserInfo storage p = presale[purchaser];
        p.paymentDeadline = uint64(block.timestamp) + newPaymentPeriodSeconds;
    }

    function updatePrice(address purchaser, uint256 newPricePerToken) external onlyOwner {
        PurchaserInfo storage p = presale[purchaser];
        p.pricePerToken = newPricePerToken;
    }

    function updatePaymentMethod(address purchaser, IERC20 newPaymentMethod) external onlyOwner {
        PurchaserInfo storage p = presale[purchaser];
        p.paymentMethod = newPaymentMethod;
    }

    function updateAllocation(address purchaser, uint256 newAllocation) external onlyOwner {
        PurchaserInfo storage p = presale[purchaser];
        p.maximumTokenAllocation = newAllocation;
    }

    /**
     * @notice Purchaser can donate all unclaimed tokens to the system
     */
    function donateAllTokens() external {
        PurchaserInfo storage p = presale[msg.sender];
        require(p.maximumTokenAllocation > 0, "Account is not initialized");
        // how many tokens are still on the account?
        uint256 tokenBalance = p._tokensBought - p._tokensClaimed;
        // remove them from bought tokens
        p._tokensBought = p._tokensBought - tokenBalance;
    }

    function adminWithdraw(IERC20 token) external onlyOwner {
        if (token == suDAO) {
            // allow to withdraw unsold suDAO only
            uint256 withdrawAmount = suDAO.balanceOf(address(this)) - totalTokensSold;
            if (withdrawAmount > 0) {
                suDAO.safeTransferFrom(address(this), address(msg.sender), withdrawAmount);
            }
        } else {
            uint256 withdrawAmount = token.balanceOf(address(this));
            if (withdrawAmount > 0) {
                token.safeTransferFrom(address(this), address(msg.sender), withdrawAmount);
            }
        }
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
  "remappings": [],
  "optimizer": {
    "enabled": false,
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