// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;

/* Contract Imports */
import { Ownable } from "./Lib_Ownable.sol";

/**
 * @title Lib_AddressManager
 */
contract Lib_AddressManager is Ownable {

    /**********
     * Events *
     **********/

    event AddressSet(
        string _name,
        address _newAddress
    );


    /*************
     * Variables *
     *************/

    mapping (bytes32 => address) private addresses;


    /********************
     * Public Functions *
     ********************/

    /**
     * Changes the address associated with a particular name.
     * @param _name String name to associate an address with.
     * @param _address Address to associate with the name.
     */
    function setAddress(
        string memory _name,
        address _address
    )
        public
        onlyOwner
    {
        addresses[_getNameHash(_name)] = _address;

        emit AddressSet(
            _name,
            _address
        );
    }

    /**
     * Retrieves the address associated with a given name.
     * @param _name Name to retrieve an address for.
     * @return Address associated with the given name.
     */
    function getAddress(
        string memory _name
    )
        public
        view
        returns (
            address
        )
    {
        return addresses[_getNameHash(_name)];
    }


    /**********************
     * Internal Functions *
     **********************/

    /**
     * Computes the hash of a name.
     * @param _name Name to compute a hash for.
     * @return Hash of the given name.
     */
    function _getNameHash(
        string memory _name
    )
        internal
        pure
        returns (
            bytes32
        )
    {
        return keccak256(abi.encodePacked(_name));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;

/**
 * @title Ownable
 * @dev Adapted from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol
 */
abstract contract Ownable {

    /*************
     * Variables *
     *************/

    address public owner;


    /**********
     * Events *
     **********/

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );


    /***************
     * Constructor *
     ***************/

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }


    /**********************
     * Function Modifiers *
     **********************/

    modifier onlyOwner() {
        require(
            owner == msg.sender,
            "Ownable: caller is not the owner"
        );
        _;
    }


    /********************
     * Public Functions *
     ********************/

    /**
     * Sets the owner of this contract to the zero address, effectively renouncing ownership
     * completely. Can only be called by the current owner of this contract.
     */
    function renounceOwnership()
        public
        virtual
        onlyOwner
    {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    /**
     * Transfers ownership of this contract to a new address. Can only be called by the current
     * owner of this contract.
     * @param _newOwner Address of the new contract owner.
     */
    function transferOwnership(
        address _newOwner
    )
        public
        virtual
        onlyOwner
    {
        require(
            _newOwner != address(0),
            "Ownable: new owner cannot be the zero address"
        );

        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;

/* Library Imports */
import { Lib_AddressManager } from "./Lib_AddressManager.sol";

/**
 * @title Lib_ResolvedDelegateProxy
 */
contract Lib_ResolvedDelegateProxy {

    /*************
     * Variables *
     *************/

    // Using mappings to store fields to avoid overwriting storage slots in the
    // implementation contract. For example, instead of storing these fields at
    // storage slot `0` & `1`, they are stored at `keccak256(key + slot)`.
    // See: https://solidity.readthedocs.io/en/v0.7.0/internals/layout_in_storage.html
    // NOTE: Do not use this code in your own contract system. 
    //      There is a known flaw in this contract, and we will remove it from the repository
    //      in the near future. Due to the very limited way that we are using it, this flaw is
    //      not an issue in our system. 
    mapping (address => string) private implementationName;
    mapping (address => Lib_AddressManager) private addressManager;


    /***************
     * Constructor *
     ***************/

    /**
     * @param _libAddressManager Address of the Lib_AddressManager.
     * @param _implementationName implementationName of the contract to proxy to.
     */
    constructor(
        address _libAddressManager,
        string memory _implementationName
    )
    {
        addressManager[address(this)] = Lib_AddressManager(_libAddressManager);
        implementationName[address(this)] = _implementationName;
    }


    /*********************
     * Fallback Function *
     *********************/

    fallback()
        external
        payable
    {
        address target = addressManager[address(this)].getAddress(
            (implementationName[address(this)])
        );

        require(
            target != address(0),
            "Target address must be initialized."
        );

        (bool success, bytes memory returndata) = target.delegatecall(msg.data);

        if (success == true) {
            assembly {
                return(add(returndata, 0x20), mload(returndata))
            }
        } else {
            assembly {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
    }
}

{
  "evmVersion": "istanbul",
  "libraries": {},
  "metadata": {
    "bytecodeHash": "ipfs",
    "useLiteralContent": true
  },
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "remappings": [],
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