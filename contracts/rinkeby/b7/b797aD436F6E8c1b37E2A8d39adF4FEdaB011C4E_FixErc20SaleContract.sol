//SPDX-License-Identifier: Unlicensed
pragma solidity >=0.6.0 <0.8.0;

import "../base/Initialisation.sol";
import "./pricing/typePricingFixed.sol";
import "contracts/access/controllerPanel.sol";
import "../interfaces/IEC721.sol";
import "../interfaces/IERC20.sol";
import "./time/saleTime.sol";

// Purchase individual art with fix price ERC20.

contract FixErc20SaleContract is
    saleTime,
    typePricingFixed,
    Initialisation,
    controllerPanel
{
    address payable public wallet;
    uint256 public totalSold = 0;
    IERC20 public payment_token;

    IEC721 generic;

    // setup pricing.. VRF if used
    function setup(
        address payable _wallet,
        IEC721 _generic,
        IERC20 _payment_token,
        uint256 _sale_start,
        uint256 _sale_end
    ) public virtual notInitialised onlyAllowed {
        wallet = _wallet;
        generic = _generic;
        payment_token = _payment_token;
        saleTime.setup(_sale_start, _sale_end);
        setInitialised();
    }

    function getCardPrice(uint256 _id) public view returns (uint256) {
        (uint256 _typeID, string memory _type) = generic.getCardTypeFromID(_id);
        return getPricing(_type);
    }

    function buyCard(uint256 _id) public payable saleActive() {
        uint256 price = getCardPrice(_id);
        require(
            price != 0,
            "Price must not be zero"
        );
        require(
            payment_token.allowance(msg.sender, address(this)) >= price,
            "Allowance not set"
        );
        require(
            payment_token.balanceOf(msg.sender) >= price,
            "Insufficient Balance"
        );
        // Trust me, it works.
        require(
            payment_token.transferFrom(msg.sender, wallet, price),
            "Transfer failed"
        );
        _assignCard(_id);
        totalSold++;
    }

    function _assignCard(uint256 _id) internal {
        generic.mint(_id, 0);
    }

    function presetPrice(string memory _type, uint256 _price)
        external
        onlyAllowed
    {
        // Type must match types in Generic contract !
        typePricingFixed.setPricing(_type, _price);
    }

    function setNewSalesDate(uint256 _start, uint256 _end)
        external
        onlyAllowed
    {
        saleTime.internal_setNewSalesDate(_start, _end);
    }

    function extendSales(uint8 _NoOfweeks) external onlyAllowed {
        saleTime.internal_extendSales(_NoOfweeks);
    }

    function stopSales() external onlyAllowed {
        saleTime.internal_stopSales();
    }
}

//SPDX-License-Identifier: Unlicensed
pragma solidity >=0.6.0 <0.8.0;

abstract contract Initialisation {
    bool public _initialised = false;

    function setInitialised() public notInitialised {
        _initialised = true;
    }

    modifier notInitialised() {
        require(!_initialised, "Must not be initialised!");
        _;
    }

    modifier isInitialised() {
        require(_initialised, "Must be initialised!");
        _;
    }
}

//SPDX-License-Identifier: Unlicensed
pragma solidity >=0.6.0 <0.8.0;

abstract contract typePricingFixed {
    mapping(string => uint256) public typePrice;

    function setPricing(string memory _type, uint256 _price) internal {
        typePrice[_type] = _price;
    }

    function getPricing(string memory _type) public view returns (uint256) {
        return typePrice[_type];
    }
}

//SPDX-License-Identifier: Unlicensed

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract controllerPanel is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _controllers;

    event ApprovedController(address indexed account, address indexed sender);
    event RevokedController(address indexed account, address indexed sender);

    modifier onlyAllowed() {
        require(
            _controllers.contains(msg.sender) || owner() == msg.sender,
            "Not Authorised"
        );
        _;
    }

    function getControllers()
        external
        view
        returns (address[] memory _allowed)
    {
        _allowed = new address[](_controllers.length());
        for (uint256 i = 0; i < _controllers.length(); i++) {
            _allowed[i] = _controllers.at(i);
        }
        return _allowed;
    }

    function approveController(address _controller) external onlyOwner {
        require(
            !_controllers.contains(_controller),
            "Controller already added."
        );
        _controllers.add(_controller);
        emit ApprovedController(_controller, msg.sender);
    }

    function revokeController(address _controller) external onlyOwner {
        require(
            _controllers.contains(_controller),
            "Controller do not hold admin rights."
        );
        _controllers.remove(_controller);
        emit RevokedController(_controller, msg.sender);
    }

    function isController(address _controller) public view returns (bool) {
        return (owner() == _controller || _controllers.contains(_controller));
    }
}

// SPDX-License-Identifier: LGPL-3.0+
pragma solidity ^0.7.3;

interface IEC721 {
    function purchaseCard(
        address,
        string calldata,
        uint256
    ) external;

    function mint(uint256 _newItemId, uint256 _traits)
        external
        returns (uint256);

    function mintWithVRF(uint256 _newItemId) external returns (uint256);

    function getCardTypeFromID(uint256 _id)
        external
        view
        returns (uint256, string memory);

    function getCardTypeMinted(uint256 _cardID) external view returns (uint256);

    function getCardTypeInitial(uint256 _cardID)
        external
        view
        returns (uint256);

    function getCardTypeAvailable(uint256 _cardID)
        external
        view
        returns (uint256);

    function turnOffSaleLock() external;
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
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

//SPDX-License-Identifier: Unlicensed
pragma solidity >=0.6.0 <0.8.0;

import "../../base/Timestamp.sol";

abstract contract saleTime is Timestamp {
    uint256 public sale_start;
    uint256 public sale_end;

    modifier saleActive() {
        require(getTimestamp() >= sale_start, "Sale not started");
        require(getTimestamp() <= sale_end, "Sale ended");
        _;
    }

    // setup pricing.. VRF if used
    function setup(uint256 _start, uint256 _end) internal {
        sale_start = _start;
        sale_end = _end;
    }

    function internal_setNewSalesDate(uint256 _start, uint256 _end) internal {
        sale_start = _start;
        sale_end = _end;
    }

    function internal_extendSales(uint8 _NoOfweeks) internal {
        // extend no of weeks.
        sale_end = getTimestamp() + (_NoOfweeks * 1 weeks);
    }

    function internal_stopSales() internal {
        // end sales.
        sale_end = getTimestamp();
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
    constructor () internal {
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

//SPDX-License-Identifier: Unlicensed
pragma solidity >=0.6.0 <0.8.0;

abstract contract Timestamp {
    function getTimestamp() public view virtual returns (uint256) {
        return block.timestamp;
    }
}

{
  "optimizer": {
    "enabled": true,
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