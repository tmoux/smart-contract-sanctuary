//SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// Libraries
import "@openzeppelin/contracts/utils/Address.sol";
import "../libs/SettingsLib.sol";

// Contracts
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../roles/RolesManagerConsts.sol";

// Interfaces
import "./IPlatformSettings.sol";
import "../roles/IRolesManager.sol";

contract PlatformSettings is IPlatformSettings {
    using Address for address;
    using SettingsLib for SettingsLib.Setting;

    /** Constants */

    /* State Variables */

    /**
        @notice This mapping represents the platform settings where:

        - The key is the platform setting name.
        - The value is the platform setting. It includes the value, minimum and maximum values.
     */
    mapping(bytes32 => SettingsLib.Setting) public settings;

    bool public paused;

    address public override rolesManager;

    /** Modifiers */

    modifier onlyPauser(address account) {
        _rolesManager().requireHasRole(
            _rolesManagerConsts().PAUSER_ROLE(),
            account,
            "SENDER_ISNT_PAUSER"
        );
        _;
    }

    modifier onlyConfigurator(address account) {
        _rolesManager().requireHasRole(
            _rolesManagerConsts().CONFIGURATOR_ROLE(),
            account,
            "SENDER_ISNT_CONFIGURATOR"
        );
        _;
    }

    /* Constructor */

    constructor(address rolesManagerAddress) public {
        require(rolesManagerAddress.isContract(), "ROLES_MANAGER_MUST_BE_CONTRACT");
        rolesManager = rolesManagerAddress;
    }

    /** External Functions */

    /**
        @notice It creates a new platform setting given a name, value, min and max values.
        @param name setting name to create.
        @param value the initial value for the given setting name.
        @param min the min value for the setting.
        @param max the max value for the setting.
     */
    function createSetting(
        bytes32 name,
        uint256 value,
        uint256 min,
        uint256 max
    ) external override onlyConfigurator(msg.sender) {
        require(name != "", "NAME_MUST_BE_PROVIDED");
        settings[name].create(value, min, max);

        emit PlatformSettingCreated(name, msg.sender, value, min, max);
    }

    /**
        @notice It updates an existent platform setting given a setting name.
        @notice It only allows to update the value (not the min or max values).
        @notice In case you need to update the min or max values, you need to remove it, and create it again.
        @param settingName setting name to update.
        @param newValue the new value to set.
     */
    function updateSetting(bytes32 settingName, uint256 newValue)
        external
        onlyConfigurator(msg.sender)
    {
        uint256 oldValue = settings[settingName].update(newValue);

        emit PlatformSettingUpdated(settingName, msg.sender, oldValue, newValue);
    }

    /**
        @notice Removes a current platform setting given a setting name.
        @param name to remove.
     */
    function removeSetting(bytes32 name) external override onlyConfigurator(msg.sender) {
        uint256 oldValue = settings[name].value;
        settings[name].remove();

        emit PlatformSettingRemoved(name, msg.sender, oldValue);
    }

    function pause() external override onlyPauser(msg.sender) {
        require(!paused, "PLATFORM_ALREADY_PAUSED");

        paused = true;

        emit PlatformPaused(msg.sender);
    }

    function unpause() external override onlyPauser(msg.sender) {
        require(paused, "PLATFORM_ISNT_PAUSED");

        paused = false;

        emit PlatformUnpaused(msg.sender);
    }

    /* View Functions */

    function requireIsPaused() external view override {
        require(paused, "PLATFORM_ISNT_PAUSED");
    }

    function requireIsNotPaused() external view override {
        require(!paused, "PLATFORM_IS_PAUSED");
    }

    /**
        @notice It gets the current platform setting for a given setting name
        @param name to get.
        @return the current platform setting.
     */
    function getSetting(bytes32 name) external view override returns (SettingsLib.Setting memory) {
        return _getSetting(name);
    }

    /**
        @notice It gets the current platform setting value for a given setting name
        @param name to get.
        @return the current platform setting value.
     */
    function getSettingValue(bytes32 name) external view override returns (uint256) {
        return _getSetting(name).value;
    }

    /**
        @notice It tests whether a setting name is already configured.
        @param name setting name to test.
        @return true if the setting is already configured. Otherwise it returns false.
     */
    function hasSetting(bytes32 name) external view override returns (bool) {
        return _getSetting(name).exists;
    }

    /**
        @notice It gets whether the platform is paused or not.
        @return true if platform is paused. Otherwise it returns false.
     */
    function isPaused() external view override returns (bool) {
        return paused;
    }

    /** Internal functions */

    /**
        @notice It gets the platform setting for a given setting name.
        @param name the setting name to look for.
        @return the current platform setting for the given setting name.
     */
    function _getSetting(bytes32 name) internal view returns (SettingsLib.Setting memory) {
        return settings[name];
    }

    function _rolesManager() internal view returns (IRolesManager) {
        return IRolesManager(rolesManager);
    }

    function _rolesManagerConsts() internal view returns (RolesManagerConsts) {
        return RolesManagerConsts(_rolesManager().consts());
    }

    /** Private functions */
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
        // This method relies in extcodesize, which returns 0 for contracts in
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
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
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

//SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.6.12;

library SettingsLib {
    /**
        It defines a setting. It includes: value, min, and max values.
     */
    struct Setting {
        uint256 value;
        uint256 min;
        uint256 max;
        bool exists;
    }

    /**
        @notice It creates a new setting given a name, min and max values.
        @param value initial value for the setting.
        @param min min value allowed for the setting.
        @param max max value allowed for the setting.
     */
    function create(
        Setting storage self,
        uint256 value,
        uint256 min,
        uint256 max
    ) internal {
        requireNotExists(self);
        require(value >= min, "VALUE_MUST_BE_GT_MIN_VALUE");
        require(value <= max, "VALUE_MUST_BE_LT_MAX_VALUE");
        self.value = value;
        self.min = min;
        self.max = max;
        self.exists = true;
    }

    /**
        @notice Checks whether the current setting exists or not.
        @dev It throws a require error if the setting already exists.
        @param self the current setting.
     */
    function requireNotExists(Setting storage self) internal view {
        require(!self.exists, "SETTING_ALREADY_EXISTS");
    }

    /**
        @notice Checks whether the current setting exists or not.
        @dev It throws a require error if the current setting doesn't exist.
        @param self the current setting.
     */
    function requireExists(Setting storage self) internal view {
        require(self.exists, "SETTING_NOT_EXISTS");
    }

    /**
        @notice It updates a current setting.
        @dev It throws a require error if:
            - The new value is equal to the current value.
            - The new value is not lower than the max value.
            - The new value is not greater than the min value
        @param self the current setting.
        @param newValue the new value to set in the setting.
     */
    function update(Setting storage self, uint256 newValue) internal returns (uint256 oldValue) {
        requireExists(self);
        require(self.value != newValue, "NEW_VALUE_REQUIRED");
        require(newValue >= self.min, "NEW_VALUE_MUST_BE_GT_MIN_VALUE");
        require(newValue <= self.max, "NEW_VALUE_MUST_BE_LT_MAX_VALUE");
        oldValue = self.value;
        self.value = newValue;
    }

    /**
        @notice It removes a current setting.
        @param self the current setting to remove.
     */
    function remove(Setting storage self) internal {
        requireExists(self);
        self.value = 0;
        self.min = 0;
        self.max = 0;
        self.exists = false;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../GSN/Context.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor () internal {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

//SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.6.12;

contract RolesManagerConsts {
    /**
        @notice It is the AccessControl.DEFAULT_ADMIN_ROLE role.
     */
    bytes32 public constant OWNER_ROLE = keccak256("");

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    bytes32 public constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");

    bytes32 public constant VAULT_CONFIGURATOR_ROLE = keccak256("VAULT_CONFIGURATOR_ROLE");

    bytes32 public constant VAULT_REGISTRAR_ROLE = keccak256("VAULT_REGISTRAR_ROLE");
}

//SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libs/SettingsLib.sol";

interface IPlatformSettings {
    event PlatformPaused(address indexed pauser);

    event PlatformUnpaused(address indexed unpauser);

    event PlatformSettingCreated(
        bytes32 indexed name,
        address indexed creator,
        uint256 value,
        uint256 minValue,
        uint256 maxValue
    );

    event PlatformSettingRemoved(bytes32 indexed name, address indexed remover, uint256 value);

    event PlatformSettingUpdated(
        bytes32 indexed name,
        address indexed remover,
        uint256 oldValue,
        uint256 newValue
    );

    function createSetting(
        bytes32 name,
        uint256 value,
        uint256 min,
        uint256 max
    ) external;

    function removeSetting(bytes32 name) external;

    function getSetting(bytes32 name) external view returns (SettingsLib.Setting memory);

    function getSettingValue(bytes32 name) external view returns (uint256);

    function hasSetting(bytes32 name) external view returns (bool);

    function rolesManager() external view returns (address);

    function isPaused() external view returns (bool);

    function requireIsPaused() external view;

    function requireIsNotPaused() external view;

    function pause() external;

    function unpause() external;
}

//SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.6.12;

interface IRolesManager {
    event MaxMultiItemsUpdated(address indexed updater, uint8 oldValue, uint8 newValue);

    function setMaxMultiItems(uint8 newMaxMultiItems) external;

    function multiGrantRole(bytes32 role, address[] calldata accounts) external;

    function multiRevokeRole(bytes32 role, address[] calldata accounts) external;

    function consts() external view returns (address);

    function maxMultiItems() external view returns (uint8);

    function requireHasRole(bytes32 role, address account) external view;

    function requireHasRole(
        bytes32 role,
        address account,
        string calldata message
    ) external view;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

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
  "libraries": {}
}