// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IsYSL.sol";
import "../interfaces/IMasterChief.sol";

contract AirLock is Ownable {
    address sYSL;
    address YSL;
    address airdrop;
    address master;

    mapping(address => LockedFunds) userLocked;

    constructor(address _sYSL, address _YSL) {
        sYSL = _sYSL;
        YSL = _YSL;
    }

    struct LockedFunds {
        uint256 lockPeriod;
        uint256 lockTime;
        uint256 lastAlloc;
        uint256 amount;
        uint256 staked;
        bool isYSL;
        bool isCommunity;
    }
    modifier strict() {
        require(block.timestamp < userLocked[_msgSender()].lockPeriod + 86400, "Not accessable");
        _;
    }

    modifier masterOnlyOr(address _addr) {
        require(_msgSender() == master || _msgSender() == _addr, "Only master is allowed");
        _;
    }

    modifier airdropOnly() {
        require(_msgSender() == airdrop);
        _;
    }

    function setAirdrop(address _airdrop) external onlyOwner {
        airdrop = _airdrop;
    }

    function setMaster(address _master) external onlyOwner {
        master = _master;
    }

    function mintLocked(
        uint256 amount,
        address to,
        uint256 locktime,
        bool isYSL,
        bool isCommunity
    ) external airdropOnly {
        isYSL ? IsYSL(YSL).mintFor(address(this), amount) : IsYSL(sYSL).mintFor(address(this), amount);
        userLocked[to] = LockedFunds(
            block.timestamp + locktime,
            locktime,
            block.timestamp,
            amount,
            0,
            isYSL,
            isCommunity
        );
    }

    function claimCommunity() external {
        LockedFunds storage lf = userLocked[_msgSender()];
        require(lf.isCommunity, "Not a community");
        require(lf.amount != 0, "Not airdropped");
        require(lf.lastAlloc < lf.lockPeriod, "Period is ended");
        uint256 period = block.timestamp - lf.lastAlloc;
        require(period > 1 days, "At least one day to claim");
        uint256 claimable = (lf.amount / lf.lockTime) * period;
        IERC20(sYSL).transfer(_msgSender(), claimable);
        lf.amount -= claimable;
        lf.lastAlloc = block.timestamp;
    }

    function claim() external strict {
        LockedFunds storage lf = userLocked[_msgSender()];
        require(lf.isCommunity, "Community address");
        require(lf.amount != 0, "Not airdropped");
        require(lf.lastAlloc < lf.lockPeriod, "Period is ended");
        uint256 period = block.timestamp - lf.lastAlloc;
        require(period > 1 days, "At least one day to claim");
        uint256 claimable = (lf.amount / lf.lockTime) * period;
        IERC20(sYSL).transfer(_msgSender(), claimable);
        lf.amount -= claimable;
        lf.lastAlloc = block.timestamp;
    }

    function stakeLocked(uint256 _amount, address _sender) external masterOnlyOr(address(this)) {
        LockedFunds storage lf = userLocked[_sender];
        require(lf.amount >= _amount, "Not enough");
        lf.amount -= _amount;
        lf.staked += _amount;
    }

    function unstakeLocked(uint256 _amount, address _sender) external masterOnlyOr(address(this)) {
        LockedFunds storage lf = userLocked[_sender];
        require(lf.staked >= _amount, "Not enough");
        lf.staked -= _amount;
        lf.amount += _amount;
    }

    function getStaked(address _user) external view returns (uint256 staked) {
        staked = userLocked[_user].staked;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface IMasterChief {
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _referrer
    ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IsYSL {
    function YSLSupply() external returns (uint256);

    function isMinted() external returns (bool);

    function mintPurchased(
        address account,
        uint256 amount,
        uint256 lockTime
    ) external;

    function mintFor(address account, uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
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
    constructor() {
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
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
        return msg.data;
    }
}

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
    "runs": 99999
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