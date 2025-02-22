// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/// @title IssueNOBL
/// @notice Issuing contract for ScienceCoins (NOBL)
contract IssueNOBL is Ownable {
    using SafeMath for uint256;
    IERC20 public openTherapoidContract;

    uint256 public transferThreshold;
    uint256 public totalTokensIssued;
    mapping(address => bool) public isIssuer;

    event LogBulkIssueNOBL(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes32 activity
    );
    event LogUpdateThreshold(uint256 oldThreshold, uint256 newThreshold);
    event LogAddIssuer(address issuer, uint256 addedAt);
    event LogRemoveIssuer(address issuer, uint256 removedAt);

    /**
     * @dev Modifier to make a function invocable by only the issuer account
     */
    modifier onlyIssuer() {
        require(isIssuer[msg.sender], "Caller is not issuer");
        _;
    }

    /**
     * @dev Sets the values for {OpenTherapoid Contract}.
     *
     * All of these values except _transferThreshold, _tokenIssuers are immutable: they can only be set once during
     * construction.
     */
    constructor(
        IERC20 _openTherapoidContractAddress,
        uint256 _transferThreshold,
        address[] memory _tokenIssuers
    ) {
        //solhint-disable-next-line reason-string
        require(
            address(_openTherapoidContractAddress) != address(0),
            "OpenTherapoid contract can't be address zero"
        );
        address issuer;
        for (uint256 i = 0; i < _tokenIssuers.length; i++) {
            issuer = _tokenIssuers[i];
            require(issuer != address(0), "Issuer can't be address zero");
            isIssuer[issuer] = true;
            //solhint-disable-next-line not-rely-on-time
            emit LogAddIssuer(issuer, block.timestamp);
        }
        openTherapoidContract = _openTherapoidContractAddress;
        transferThreshold = _transferThreshold;
    }

    /**
     * @dev To issue tokens for their activities on the platform
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function issueNOBLToken(
        address sender,
        address recipient,
        uint256 amount
    ) external onlyIssuer {
        //solhint-disable-next-line reason-string
        require(
            transferThreshold >= (totalTokensIssued.add(amount)),
            "Threshold exceeds, wait till threshold is updated"
        );
        totalTokensIssued = totalTokensIssued.add(amount);
        openTherapoidContract.transferFrom(sender, recipient, amount);
    }

    /**
     * @dev Moves tokens `amount` from `tokenOwner` to `recipients`.
     */
    function issueBulkNOBLToken(
        address sender,
        address[] memory recipients,
        uint256[] memory amounts,
        bytes32[] memory activities
    ) external onlyIssuer {
        require(
            (recipients.length == amounts.length) &&
                (recipients.length == activities.length),
            "Unequal params"
        );
        for (uint256 i = 0; i < recipients.length; i++) {
            openTherapoidContract.transferFrom(
                sender,
                recipients[i],
                amounts[i]
            );
            emit LogBulkIssueNOBL(
                sender,
                recipients[i],
                amounts[i],
                activities[i]
            );
        }
    }

    /**
     * @dev To increase transfer threshold value for this contract
     *
     * Requirements:
     * - invocation can be done, only by the contract owner.
     */
    function updateThreshold(uint256 newThreshold, bool shouldIncrease)
        external
        onlyOwner
    {
        uint256 oldThreshold = transferThreshold;
        if (shouldIncrease) {
            transferThreshold = transferThreshold.add(newThreshold);
        } else {
            transferThreshold = transferThreshold.sub(newThreshold);
        }
        emit LogUpdateThreshold(oldThreshold, transferThreshold);
    }

    /**
     * @dev To add issuers address in the contract
     *
     * Requirements:
     * - invocation can be done, only by the contract owner.
     */
    function addIssuers(address[] memory _issuers) external onlyOwner {
        address issuer;
        for (uint256 i = 0; i < _issuers.length; i++) {
            issuer = _issuers[i];
            require(issuer != address(0), "Issuer can't be address zero");
            require(!isIssuer[issuer], "Already an issuer");
            isIssuer[issuer] = true;
            //solhint-disable-next-line not-rely-on-time
            emit LogAddIssuer(issuer, block.timestamp);
        }
    }

    /**
     * @dev To remove issuers address from the contract
     *
     * Requirements:
     * - invocation can be done, only by the contract owner.
     */
    function removeIssuers(address[] memory _issuers) external onlyOwner {
        address issuer;
        for (uint256 i = 0; i < _issuers.length; i++) {
            issuer = _issuers[i];
            require(issuer != address(0), "Issuer can't be address zero");
            require(isIssuer[issuer], "Not an issuer");
            isIssuer[issuer] = false;
            //solhint-disable-next-line not-rely-on-time
            emit LogRemoveIssuer(issuer, block.timestamp);
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../GSN/Context.sol";
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
    constructor () internal {
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
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
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

pragma solidity >=0.6.0 <0.8.0;

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
        require(c >= a, "SafeMath: addition overflow");

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
        return sub(a, b, "SafeMath: subtraction overflow");
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
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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
        require(c / a == b, "SafeMath: multiplication overflow");

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
        return div(a, b, "SafeMath: division by zero");
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
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
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
        return mod(a, b, "SafeMath: modulo by zero");
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
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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