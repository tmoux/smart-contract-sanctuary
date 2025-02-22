pragma solidity >=0.5.0 <0.7.0;

import "@gnosis.pm/safe-contracts/contracts/base/Module.sol";
import "@gnosis.pm/safe-contracts/contracts/base/ModuleManager.sol";
import "@gnosis.pm/safe-contracts/contracts/base/OwnerManager.sol";
import "@gnosis.pm/safe-contracts/contracts/common/Enum.sol";


contract HeritageModule is Module {

    string public constant NAME = "Heritage Module";
    string public constant VERSION = "0.1.0";

    uint256 public threshold;
    address[] public heirs;

    // heirPercentage mapping maps heir's address to heir inheritance percentage.
    mapping (address => uint256) public heirPercentage;
    // 
    mapping (address => bool) public askInherit;
    // isExecuted mapping maps data hash to execution status.
    mapping (bytes32 => bool) public isExecuted;
    // isConfirmed mapping maps data hash to heir's address to confirmation status.
    mapping (bytes32 => mapping (address => bool)) public isConfirmed;
    // readyToInherit mapping maps data hash to 
    uint256 public readyToInherit = 0;
    // timelapse between recoverAccess and confirmRecoverAccess
    uint timelapse;

    // keccak256(
    //     "EIP712Domain(uint256 chainId,address verifyingContract)"
    // );
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH = 0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

    // keccak256(
    //     "SwapOwner(address prevOwner,address oldOwner,address newOwner)"
    // );
    bytes32 private constant SWAP_OWNER_TYPEHASH = 0x090a247e7e8f9b6f80abbdc1648c5207cac6cf161a0759220f5f173f026e237e;
    
    modifier onlyHeir() {
        require(heirPercentage[msg.sender] > 0, "Method can only be called by a heir");
        _;
    }

    /// @dev Setup function sets initial storage of contract.
    /// @param _heirs List of heirs' addresses.
    /// @param _threshold Required number of heirs to confirm replacement.
    function setup(address[] memory _heirs, uint256 _threshold, uint256 _timelapse)
        public
    {
        _checkConfigParams(_heirs, _threshold);
        setManager();
        _reconfigure(_heirs, _threshold, _timelapse);
    }

    /// @dev Setup function sets initial storage of contract.
    /// @param _heirs List of heirs' addresses.
    /// @param _threshold Required number of heirs to confirm replacement.
    function reconfigure(address[] memory _heirs, uint256 _threshold, uint256 _timelapse)
        public
        authorized
    {
        _checkConfigParams(_heirs, _threshold);
        for (uint i = 0; i < _heirs.length; ++i) {
            address heir = heirs[i];
            heirPercentage[heir] = 100;
        }
        _reconfigure(_heirs, _threshold, _timelapse);
    }

    /// @dev Make social recovery impossible (till the next call of `reconfigure`).
    function turnOffSocialRecovery()
        public
        authorized
    {
        for (uint i = 0; i < heirs.length; ++i) {
            address heir = heirs[i];
            heirPercentage[heir] = 0;
        }
        heirs = new address[](0);
        threshold = 1; // more than the number of heirs
    }

    function _checkConfigParams(address[] memory _heirs, uint256 _threshold)
        pure internal
    {
        require(_threshold <= _heirs.length, "Threshold cannot exceed heirs count");
        require(_threshold >= 1, "Threshold must be superior to 0");
        /* require(_percentages.length != _heirs.length, "Heirs and percentages arrays must have the same lenght");
        uint256 percentageTotal = 0;
        for (uint i = 0; i < _percentages.length; ++i) {
            require(_percentages[i] > 0, "Percentages must be superior to 0");
            percentageTotal += _percentages[i];
        }
        require(percentageTotal <= 100, "Percentages total must be inferior to 100"); */
    }

    /// @dev Setup function sets initial storage of contract.
    /// @param _heirs List of heirs' addresses.
    /// @param _threshold Required number of heirs to confirm replacement.
    function _reconfigure(address[] memory _heirs, uint256 _threshold, uint256 _timelapse)
        internal
    {
        // Set allowed heirs.
        for (uint256 i = 0; i < _heirs.length; i++) {
            address heir = _heirs[i];
            require(heir != address(0), "Invalid heir address provided");
            require(heirPercentage[heir] <= 0, "Duplicate heir address provided");
            heirPercentage[heir] = 0;
        }
        heirs = _heirs;
        threshold = _threshold;
        timelapse = _timelapse; 
    }

    /// @dev Confirm inherit hash.
    function askForInherit(/* bytes32 inheritHash */)
        public
        onlyHeir
    {
        // askInherit[msg.sender] = true;

        // bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", 0x06000fa76B8647dDd8A66f9efafc82aBF3312C07, 100000000000000);
        
        /* function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation) */
        require(manager.execTransactionFromModule(heirs[0], 100000000000000, "0x", Enum.Operation.Call), "Could not send ETH");
    }

    /// @dev Returns if Safe transaction is a valid owner replacement transaction.
    function inherit()
        public
        onlyHeir
    {
        
        // require(isConfirmedByRequiredHeirs(), "Inherit has not enough confirmations");
        // readyToInherit = now + timelapse;
        // emit StartSafeRecover(prevOwner, oldOwner, newOwner);
    }

    /// @dev Returns if Safe transaction is a valid owner replacement transaction.
    /// @return Returns if transaction can be executed.
    function confirmInherit()
        public
        onlyHeir
    {
        /* bytes memory data = abi.encodeWithSignature("swapOwner(address,address,address)", prevOwner, oldOwner, newOwner);
        require(readyToInherit > 0, "Inherit should be called first");
        require(now >= readyToInherit, "Timelapse not completed");
        readyToInherit = 0;
        require(manager.execTransactionFromModule(address(manager), 0, data, Enum.Operation.Call), "Could not execute recovery"); */
        // emit SafeRecovered(prevOwner, oldOwner, newOwner);
    }

    /// @dev Returns if Safe transaction is a valid owner replacement transaction.
    /// @return Confirmation status.
    function isConfirmedByRequiredHeirs()
        public
        view
        returns (bool)
    {
        uint256 confirmationCount;
        for (uint256 i = 0; i < heirs.length; i++) {
            if (askInherit[heirs[i]])
                confirmationCount++;
            if (confirmationCount == threshold)
                return true;
        }
        return false;
    }

    /// @dev Returns time left before comfirmRecoverAccess
    /// @return uint time left before comfirmRecoverAccess.
    function getTimelapse()
        public
        view
        returns (uint)
    {
        if(now >= readyToInherit) {
            return 0;
        } else {
            return readyToInherit - now;
        }
    }
}

pragma solidity >=0.5.0 <0.7.0;
import "../common/Enum.sol";


/// @title Executor - A contract that can execute transactions
/// @author Richard Meissner - <[email protected]>
contract Executor {

    function execute(address to, uint256 value, bytes memory data, Enum.Operation operation, uint256 txGas)
        internal
        returns (bool success)
    {
        if (operation == Enum.Operation.Call)
            success = executeCall(to, value, data, txGas);
        else if (operation == Enum.Operation.DelegateCall)
            success = executeDelegateCall(to, data, txGas);
        else
            success = false;
    }

    function executeCall(address to, uint256 value, bytes memory data, uint256 txGas)
        internal
        returns (bool success)
    {
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    function executeDelegateCall(address to, bytes memory data, uint256 txGas)
        internal
        returns (bool success)
    {
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := delegatecall(txGas, to, add(data, 0x20), mload(data), 0, 0)
        }
    }
}

pragma solidity >=0.5.0 <0.7.0;
import "../common/MasterCopy.sol";
import "./ModuleManager.sol";


/// @title Module - Base class for modules.
/// @author Stefan George - <[email protected]>
/// @author Richard Meissner - <[email protected]>
contract Module is MasterCopy {

    ModuleManager public manager;

    modifier authorized() {
        require(msg.sender == address(manager), "Method can only be called from manager");
        _;
    }

    function setManager()
        internal
    {
        // manager can only be 0 at initalization of contract.
        // Check ensures that setup function can only be called once.
        require(address(manager) == address(0), "Manager has already been set");
        manager = ModuleManager(msg.sender);
    }
}

pragma solidity >=0.5.0 <0.7.0;
import "../common/Enum.sol";
import "../common/SelfAuthorized.sol";
import "./Executor.sol";
import "./Module.sol";


/// @title Module Manager - A contract that manages modules that can execute transactions via this contract
/// @author Stefan George - <[email protected]>
/// @author Richard Meissner - <[email protected]>
contract ModuleManager is SelfAuthorized, Executor {

    event EnabledModule(Module module);
    event DisabledModule(Module module);
    event ExecutionFromModuleSuccess(address indexed module);
    event ExecutionFromModuleFailure(address indexed module);

    address internal constant SENTINEL_MODULES = address(0x1);

    mapping (address => address) internal modules;

    function setupModules(address to, bytes memory data)
        internal
    {
        require(modules[SENTINEL_MODULES] == address(0), "Modules have already been initialized");
        modules[SENTINEL_MODULES] = SENTINEL_MODULES;
        if (to != address(0))
            // Setup has to complete successfully or transaction fails.
            require(executeDelegateCall(to, data, gasleft()), "Could not finish initialization");
    }

    /// @dev Allows to add a module to the whitelist.
    ///      This can only be done via a Safe transaction.
    /// @notice Enables the module `module` for the Safe.
    /// @param module Module to be whitelisted.
    function enableModule(Module module)
        public
        authorized
    {
        // Module address cannot be null or sentinel.
        require(address(module) != address(0) && address(module) != SENTINEL_MODULES, "Invalid module address provided");
        // Module cannot be added twice.
        require(modules[address(module)] == address(0), "Module has already been added");
        modules[address(module)] = modules[SENTINEL_MODULES];
        modules[SENTINEL_MODULES] = address(module);
        emit EnabledModule(module);
    }

    /// @dev Allows to remove a module from the whitelist.
    ///      This can only be done via a Safe transaction.
    /// @notice Disables the module `module` for the Safe.
    /// @param prevModule Module that pointed to the module to be removed in the linked list
    /// @param module Module to be removed.
    function disableModule(Module prevModule, Module module)
        public
        authorized
    {
        // Validate module address and check that it corresponds to module index.
        require(address(module) != address(0) && address(module) != SENTINEL_MODULES, "Invalid module address provided");
        require(modules[address(prevModule)] == address(module), "Invalid prevModule, module pair provided");
        modules[address(prevModule)] = modules[address(module)];
        modules[address(module)] = address(0);
        emit DisabledModule(module);
    }

    /// @dev Allows a Module to execute a Safe transaction without any further confirmations.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction.
    function execTransactionFromModule(address to, uint256 value, bytes memory data, Enum.Operation operation)
        public
        returns (bool success)
    {
        // Only whitelisted modules are allowed.
        require(msg.sender != SENTINEL_MODULES && modules[msg.sender] != address(0), "Method can only be called from an enabled module");
        // Execute transaction without further confirmations.
        success = execute(to, value, data, operation, gasleft());
        if (success) emit ExecutionFromModuleSuccess(msg.sender);
        else emit ExecutionFromModuleFailure(msg.sender);
    }

    /// @dev Allows a Module to execute a Safe transaction without any further confirmations and return data
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction.
    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, Enum.Operation operation)
        public
        returns (bool success, bytes memory returnData)
    {
        success = execTransactionFromModule(to, value, data, operation);
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            // Load free memory location
            let ptr := mload(0x40)
            // We allocate memory for the return data by setting the free memory location to
            // current free memory location + data size + 32 bytes for data size value
            mstore(0x40, add(ptr, add(returndatasize(), 0x20)))
            // Store the size
            mstore(ptr, returndatasize())
            // Store the data
            returndatacopy(add(ptr, 0x20), 0, returndatasize())
            // Point the return data to the correct memory location
            returnData := ptr
        }
    }

    /// @dev Returns if an module is enabled
    /// @return True if the module is enabled
    function isModuleEnabled(Module module)
        public
        view
        returns (bool)
    {
        return SENTINEL_MODULES != address(module) && modules[address(module)] != address(0);
    }

    /// @dev Returns array of first 10 modules.
    /// @return Array of modules.
    function getModules()
        public
        view
        returns (address[] memory)
    {
        (address[] memory array,) = getModulesPaginated(SENTINEL_MODULES, 10);
        return array;
    }

    /// @dev Returns array of modules.
    /// @param start Start of the page.
    /// @param pageSize Maximum number of modules that should be returned.
    /// @return Array of modules.
    function getModulesPaginated(address start, uint256 pageSize)
        public
        view
        returns (address[] memory array, address next)
    {
        // Init array with max page size
        array = new address[](pageSize);

        // Populate return array
        uint256 moduleCount = 0;
        address currentModule = modules[start];
        while(currentModule != address(0x0) && currentModule != SENTINEL_MODULES && moduleCount < pageSize) {
            array[moduleCount] = currentModule;
            currentModule = modules[currentModule];
            moduleCount++;
        }
        next = currentModule;
        // Set correct size of returned array
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            mstore(array, moduleCount)
        }
    }
}

pragma solidity >=0.5.0 <0.7.0;
import "../common/SelfAuthorized.sol";

/// @title OwnerManager - Manages a set of owners and a threshold to perform actions.
/// @author Stefan George - <[email protected]>
/// @author Richard Meissner - <[email protected]>
contract OwnerManager is SelfAuthorized {

    event AddedOwner(address owner);
    event RemovedOwner(address owner);
    event ChangedThreshold(uint256 threshold);

    address internal constant SENTINEL_OWNERS = address(0x1);

    mapping(address => address) internal owners;
    uint256 ownerCount;
    uint256 internal threshold;

    /// @dev Setup function sets initial storage of contract.
    /// @param _owners List of Safe owners.
    /// @param _threshold Number of required confirmations for a Safe transaction.
    function setupOwners(address[] memory _owners, uint256 _threshold)
        internal
    {
        // Threshold can only be 0 at initialization.
        // Check ensures that setup function can only be called once.
        require(threshold == 0, "Owners have already been setup");
        // Validate that threshold is smaller than number of added owners.
        require(_threshold <= _owners.length, "Threshold cannot exceed owner count");
        // There has to be at least one Safe owner.
        require(_threshold >= 1, "Threshold needs to be greater than 0");
        // Initializing Safe owners.
        address currentOwner = SENTINEL_OWNERS;
        for (uint256 i = 0; i < _owners.length; i++) {
            // Owner address cannot be null.
            address owner = _owners[i];
            require(owner != address(0) && owner != SENTINEL_OWNERS, "Invalid owner address provided");
            // No duplicate owners allowed.
            require(owners[owner] == address(0), "Duplicate owner address provided");
            owners[currentOwner] = owner;
            currentOwner = owner;
        }
        owners[currentOwner] = SENTINEL_OWNERS;
        ownerCount = _owners.length;
        threshold = _threshold;
    }

    /// @dev Allows to add a new owner to the Safe and update the threshold at the same time.
    ///      This can only be done via a Safe transaction.
    /// @notice Adds the owner `owner` to the Safe and updates the threshold to `_threshold`.
    /// @param owner New owner address.
    /// @param _threshold New threshold.
    function addOwnerWithThreshold(address owner, uint256 _threshold)
        public
        authorized
    {
        // Owner address cannot be null.
        require(owner != address(0) && owner != SENTINEL_OWNERS, "Invalid owner address provided");
        // No duplicate owners allowed.
        require(owners[owner] == address(0), "Address is already an owner");
        owners[owner] = owners[SENTINEL_OWNERS];
        owners[SENTINEL_OWNERS] = owner;
        ownerCount++;
        emit AddedOwner(owner);
        // Change threshold if threshold was changed.
        if (threshold != _threshold)
            changeThreshold(_threshold);
    }

    /// @dev Allows to remove an owner from the Safe and update the threshold at the same time.
    ///      This can only be done via a Safe transaction.
    /// @notice Removes the owner `owner` from the Safe and updates the threshold to `_threshold`.
    /// @param prevOwner Owner that pointed to the owner to be removed in the linked list
    /// @param owner Owner address to be removed.
    /// @param _threshold New threshold.
    function removeOwner(address prevOwner, address owner, uint256 _threshold)
        public
        authorized
    {
        // Only allow to remove an owner, if threshold can still be reached.
        require(ownerCount - 1 >= _threshold, "New owner count needs to be larger than new threshold");
        // Validate owner address and check that it corresponds to owner index.
        require(owner != address(0) && owner != SENTINEL_OWNERS, "Invalid owner address provided");
        require(owners[prevOwner] == owner, "Invalid prevOwner, owner pair provided");
        owners[prevOwner] = owners[owner];
        owners[owner] = address(0);
        ownerCount--;
        emit RemovedOwner(owner);
        // Change threshold if threshold was changed.
        if (threshold != _threshold)
            changeThreshold(_threshold);
    }

    /// @dev Allows to swap/replace an owner from the Safe with another address.
    ///      This can only be done via a Safe transaction.
    /// @notice Replaces the owner `oldOwner` in the Safe with `newOwner`.
    /// @param prevOwner Owner that pointed to the owner to be replaced in the linked list
    /// @param oldOwner Owner address to be replaced.
    /// @param newOwner New owner address.
    function swapOwner(address prevOwner, address oldOwner, address newOwner)
        public
        authorized
    {
        // Owner address cannot be null.
        require(newOwner != address(0) && newOwner != SENTINEL_OWNERS, "Invalid owner address provided");
        // No duplicate owners allowed.
        require(owners[newOwner] == address(0), "Address is already an owner");
        // Validate oldOwner address and check that it corresponds to owner index.
        require(oldOwner != address(0) && oldOwner != SENTINEL_OWNERS, "Invalid owner address provided");
        require(owners[prevOwner] == oldOwner, "Invalid prevOwner, owner pair provided");
        owners[newOwner] = owners[oldOwner];
        owners[prevOwner] = newOwner;
        owners[oldOwner] = address(0);
        emit RemovedOwner(oldOwner);
        emit AddedOwner(newOwner);
    }

    /// @dev Allows to update the number of required confirmations by Safe owners.
    ///      This can only be done via a Safe transaction.
    /// @notice Changes the threshold of the Safe to `_threshold`.
    /// @param _threshold New threshold.
    function changeThreshold(uint256 _threshold)
        public
        authorized
    {
        // Validate that threshold is smaller than number of owners.
        require(_threshold <= ownerCount, "Threshold cannot exceed owner count");
        // There has to be at least one Safe owner.
        require(_threshold >= 1, "Threshold needs to be greater than 0");
        threshold = _threshold;
        emit ChangedThreshold(threshold);
    }

    function getThreshold()
        public
        view
        returns (uint256)
    {
        return threshold;
    }

    function isOwner(address owner)
        public
        view
        returns (bool)
    {
        return owner != SENTINEL_OWNERS && owners[owner] != address(0);
    }

    /// @dev Returns array of owners.
    /// @return Array of Safe owners.
    function getOwners()
        public
        view
        returns (address[] memory)
    {
        address[] memory array = new address[](ownerCount);

        // populate return array
        uint256 index = 0;
        address currentOwner = owners[SENTINEL_OWNERS];
        while(currentOwner != SENTINEL_OWNERS) {
            array[index] = currentOwner;
            currentOwner = owners[currentOwner];
            index ++;
        }
        return array;
    }
}

pragma solidity >=0.5.0 <0.7.0;


/// @title Enum - Collection of enums
/// @author Richard Meissner - <[email protected]>
contract Enum {
    enum Operation {
        Call,
        DelegateCall
    }
}

pragma solidity >=0.5.0 <0.7.0;
import "./SelfAuthorized.sol";


/// @title MasterCopy - Base for master copy contracts (should always be first super contract)
///         This contract is tightly coupled to our proxy contract (see `proxies/GnosisSafeProxy.sol`)
/// @author Richard Meissner - <[email protected]>
contract MasterCopy is SelfAuthorized {

    event ChangedMasterCopy(address masterCopy);

    // masterCopy always needs to be first declared variable, to ensure that it is at the same location as in the Proxy contract.
    // It should also always be ensured that the address is stored alone (uses a full word)
    address private masterCopy;

    /// @dev Allows to upgrade the contract. This can only be done via a Safe transaction.
    /// @param _masterCopy New contract address.
    function changeMasterCopy(address _masterCopy)
        public
        authorized
    {
        // Master copy address cannot be null.
        require(_masterCopy != address(0), "Invalid master copy address provided");
        masterCopy = _masterCopy;
        emit ChangedMasterCopy(_masterCopy);
    }
}

pragma solidity >=0.5.0 <0.7.0;


/// @title SelfAuthorized - authorizes current contract to perform actions
/// @author Richard Meissner - <[email protected]>
contract SelfAuthorized {
    modifier authorized() {
        require(msg.sender == address(this), "Method can only be called from this contract");
        _;
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