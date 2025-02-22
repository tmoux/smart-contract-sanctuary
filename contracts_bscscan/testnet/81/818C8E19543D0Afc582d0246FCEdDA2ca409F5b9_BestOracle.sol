//SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";

contract BestOracle is Ownable {

mapping(string => Match)   MatchResult;    
     struct Match {
        uint8 homescore;
        uint8 awayscore;
        uint8 ratio;
        string teamwin ;
        uint timestart;
        bool exits;
    }
 
    constructor()  {}   
    
    function addResult(string calldata  _keymatch, uint8 _homescore,uint8 _awayscore,uint8   _ratio,string memory team,uint _time) public returns(bool) {
        //require(MatchResult[_keymatch].exits,"xcxxx");
        // uint t = block.timestamp + 30 hours;
        Match storage M = MatchResult[_keymatch];
        M.homescore = _homescore;
        M.awayscore = _awayscore;
        M.ratio = _ratio;
        M.teamwin = team;
        M.timestart = _time + 30 days;
        M.exits = true;
        return true;
    }
    
    function viewResult(string calldata _keymatch) external view returns(string  memory  _key, uint8 _homescore,uint8 _awayscore,uint8   _ratio,string memory team,uint _time)  {
        require(MatchResult[_keymatch].exits,"xcxxx");
        Match storage M = MatchResult[_keymatch];
        _homescore = M.homescore;
         _awayscore = M.awayscore;
        _ratio = M.ratio ;
        team = M.teamwin ;
         _time = M.timestart;
        return (_keymatch,_homescore, _awayscore, _ratio , team , _time);
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
  "libraries": {}
}