// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./libraries/SafeERC20.sol";

/// @title TokensSale
/// @dev A token sale contract that accepts only desired USD stable coins as a payment. Blocks any direct ETH deposits.
contract GMSCommunitySaleTest {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // token sale limits per account in USD with 2 decimals (cents)
    uint256 public minPerAccount;
    uint256 public maxPerAccount;

    // cap in USD for token sale with 2 decimals (cents)
    uint256 public cap;

    // timestamp and duration are expressed in UNIX time, the same units as block.timestamp
    uint256 public startTime;
    uint256 public duration;

    // used to prevent gas usage when sale is ended
    bool private _ended;

    // accounts balances in USD with 2 decimals (cents)
    mapping(address => uint256) public balances;

    // collected stable coins balances
    mapping(address => uint256) private _deposited;

    // collected amound in USD with 2 decimals (cents)
    uint256 public collected;

    // whitelist
    mapping(address => bool) public whitelisted;
    bool public whitelistedOnly = true;

    // list of supprted stable coins
    EnumerableSet.AddressSet private stableCoins;

    // owner address
    address public owner;
    address public newOwner;

    // blocks ETH direct deposits by default
    bool private allowETH = false;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event WhitelistChanged(bool newEnabled);
    event Purchased(address indexed purchaser, uint256 amount);

    /// @dev creates a token sale contract that accepts only USD stable coins
    /// @param _owner address of the owner
    /// @param _minPerAccount min limit in USD cents that account needs to spend
    /// @param _maxPerAccount max allocation in USD cents per account
    /// @param _cap sale limit amount in USD cents
    /// @param _startTime the time (as Unix time) of sale start
    /// @param _duration duration in seconds of token sale
    /// @param _stableCoinsAddresses array of ERC20 token addresses of stable coins accepted in the sale
    constructor(
        address _owner,
        uint256 _minPerAccount,
        uint256 _maxPerAccount,
        uint256 _cap,
        uint256 _startTime,
        uint256 _duration,
        address[] memory _stableCoinsAddresses
    ) {
        require(_owner != address(0), "GMSCommunitySaleTest: Owner is a zero address");
        require(_cap > 0, "GMSCommunitySaleTest: Cap is 0");
        require(_duration > 0, "GMSCommunitySaleTest: Duration is 0");
        require(_startTime + _duration > block.timestamp, "GMSCommunitySaleTest: Final time is before current time");

        owner = _owner;
        minPerAccount = _minPerAccount;
        maxPerAccount = _maxPerAccount;
        cap = _cap;
        startTime = _startTime;
        duration = _duration;

        for (uint256 i = 0; i < _stableCoinsAddresses.length; i++) {
            stableCoins.add(_stableCoinsAddresses[i]);
        }

        emit OwnershipTransferred(address(0), msg.sender);
    }

    // -----------------------------------------------------------------------
    // GETTERS
    // -----------------------------------------------------------------------

    /// @return the end time of the sale
    function endTime() external view returns (uint256) {
        return startTime + duration;
    }

    /// @return the balance of the account in USD cents
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    /// @return the amount in USD cents of remaining allocation
    function remainingAllocation(address account) external view returns (uint256) {
        if (!whitelistedOnly || whitelisted[account]) {
            if (maxPerAccount > 0) {
                return maxPerAccount - balances[account];
            } else {
                return cap - collected;
            }
        } else {
            return 0;
        }
    }

    /// @return information if account is whitelisted
    function isWhitelisted(address account) external view returns (bool) {
        if (whitelistedOnly) {
            return whitelisted[account];
        } else {
            return true;
        }
    }

    /// @return addresses with all stable coins supported in the sale
    function acceptableStableCoins() external view returns (address[] memory) {
        address[] memory addresses = new address[](stableCoins.length());
        
        for (uint256 i = 0; i < stableCoins.length(); i++) {
            addresses[i] = stableCoins.at(i);
        }

        return addresses;
    }

    /// @return info if sale is still ongoing
    function isLive() public view returns (bool) {
        return !_ended && block.timestamp > startTime && block.timestamp < startTime + duration;
    }

    // -----------------------------------------------------------------------
    // INTERNAL
    // -----------------------------------------------------------------------

    function _isBalanceSufficient(uint256 _amount) private view returns (bool) {
        return _amount + collected <= cap;
    }

    // -----------------------------------------------------------------------
    // MODIFIERS
    // -----------------------------------------------------------------------

    modifier onlyWhitelisted() {
        require(!whitelistedOnly || whitelisted[msg.sender], "GMSCommunitySaleTest: Account is not whitelisted");
        _;
    }

    modifier isOngoing() {
        require(isLive(), "GMSCommunitySaleTest: Sale is not active");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "GMSCommunitySaleTest: Only for contract Owner");
        _;
    }

    modifier isEnded() {
        require(_ended || block.timestamp > startTime + duration, "GMSCommunitySaleTest: Not ended");
        _;
    }

    // -----------------------------------------------------------------------
    // SETTERS
    // -----------------------------------------------------------------------

    /// @notice buy tokens using USD stable coins
    /// @dev use approve/transferFrom flow
    /// @param stableCoinAddress stable coin token address
    /// @param amount amount of USD cents
    function buyWith(address stableCoinAddress, uint256 amount) external isOngoing onlyWhitelisted {
        require(stableCoins.contains(stableCoinAddress), "GMSCommunitySaleTest: Stable coin not supported");
        require(amount > 0, "GMSCommunitySaleTest: Amount is 0");
        require(_isBalanceSufficient(amount), "GMSCommunitySaleTest: Insufficient remaining amount");
        require(amount + balances[msg.sender] >= minPerAccount, "GMSCommunitySaleTest: Amount too low");
        require(maxPerAccount == 0 || balances[msg.sender] + amount <= maxPerAccount, "GMSCommunitySaleTest: Amount too high");

        uint8 decimals = IERC20(stableCoinAddress).safeDecimals();
        uint256 stableCoinUnits = amount * (10**(decimals-2));

        // solhint-disable-next-line max-line-length
        require(IERC20(stableCoinAddress).allowance(msg.sender, address(this)) >= stableCoinUnits, "GMSCommunitySaleTest: Insufficient stable coin allowance");
        IERC20(stableCoinAddress).safeTransferFrom(msg.sender, stableCoinUnits);

        balances[msg.sender] += amount;
        collected += amount;
        _deposited[stableCoinAddress] += stableCoinUnits;

        emit Purchased(msg.sender, amount);
    }

    function endPresale() external onlyOwner {
        require(collected >= cap, "GMSCommunitySaleTest: Limit not reached");
        _ended = true;
    }

    function withdrawFunds() external onlyOwner isEnded {
        _ended = true;

        uint256 amount;

        for (uint256 i = 0; i < stableCoins.length(); i++) {
            address stableCoin = address(stableCoins.at(i));
            amount = IERC20(stableCoin).balanceOf(address(this));
            if (amount > 0) {
                IERC20(stableCoin).safeTransfer(owner, amount);
            }
        }

        amount = address(this).balance;
        if (amount > 0) {
            payable(owner).transfer(amount);
        }
    }

    function recoverErc20(address token) external onlyOwner {
        uint256 amount = IERC20(token).balanceOf(address(this));
        amount -= _deposited[token];
        if (amount > 0) {
            IERC20(token).safeTransfer(owner, amount);
        }
    }

    function recoverEth() external onlyOwner isEnded {
        payable(owner).transfer(address(this).balance);
    }

    function changeOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "GMSCommunitySaleTest: New Owner is a zero address");
        newOwner = _newOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == newOwner, "GMSCommunitySaleTest: Only new Owner");
        newOwner = address(0);
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
    }

    function setWhitelistedOnly(bool enabled) public onlyOwner {
        whitelistedOnly = enabled;
        emit WhitelistChanged(enabled);
    }

    function addWhitelistedAddresses(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelisted[addresses[i]] = true;
        }
    }

    function setAllowETH(bool enabled) public onlyOwner {
        allowETH = enabled;
    }

    receive() external payable {
        require(allowETH, "GMSCommunitySaleTest: Revert on all ETH transfers");
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";

library SafeERC20 {
    function safeSymbol(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x95d89b41));
        return success && data.length > 0 ? abi.decode(data, (string)) : "???";
    }

    function safeName(IERC20 token) internal view returns (string memory) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x06fdde03));
        return success && data.length > 0 ? abi.decode(data, (string)) : "???";
    }

    function safeDecimals(IERC20 token) internal view returns (uint8) {
        (bool success, bytes memory data) = address(token).staticcall(abi.encodeWithSelector(0x313ce567));
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 18;
    }

    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: Transfer failed");
    }

    function safeTransferFrom(IERC20 token, address from, uint256 amount) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = address(token).call(abi.encodeWithSelector(0x23b872dd, from, address(this), amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeERC20: TransferFrom failed");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // EIP 2612
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}

{
  "optimizer": {
    "enabled": true,
    "runs": 999999
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
  "libraries": {}
}