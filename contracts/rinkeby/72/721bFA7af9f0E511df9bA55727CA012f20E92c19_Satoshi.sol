/**
    Token Creation Contract

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version. 
    
    A copy also available at <https://www.gnu.org/licenses/>.


*/
//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.7.0;

import './interfaces/IERC20.sol';
import './interfaces/ISatoshiERC20.sol';
import './libraries/SafeMath.sol';

contract Satoshi is ISatoshiERC20 {
    using SafeMath for uint;

    string public override constant name = 'Satoshi';
    string public override constant version = '1';
    string public override constant symbol = 'SATS';
    // decimals of WBTC is 8
    // we cannot set decimals to 0 to get it done
    // it will not be compatible with Uniswap LP
    // hence we use 18 decimals and need a conversion between WBTC and SATS
    // there will be friction when converting back from SATS to WBTC
    uint8 public override constant decimals = 18;
    uint public override constant supplyCap = 2099999997690000 * 10**18; // safeguard totalSupply to be never more than 21 trillion SATS, i.e. 21M BTC
    uint public override totalSupply;
    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;

    address public override constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // hardcoded WBTC token contract address

    bytes32 public override DOMAIN_SEPARATOR;
    // keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');
    bytes32 public override constant DOMAIN_TYPE_HASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public override constant PERMIT_TYPE_HASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public override nonces;

    //event Approval(address indexed owner, address indexed spender, uint value);
    //event Transfer(address indexed from, address indexed to, uint value);

    constructor() {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                address(this)
            )
        );
    }

    function _mint(address to, uint value) internal {
        require(to != address(0), "Satoshi: BLACKHOLE_NOT_ALLOWED");
        totalSupply = totalSupply.add(value);
        require(totalSupply <= supplyCap, "Satoshi: SUPPLY_CAP_EXCEEDED");
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        require(to != address(0), "Satoshi: BLACKHOLE_NOT_ALLOWED");
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external override returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external override {
        require(deadline >= block.timestamp, 'Satoshi: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPE_HASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'Satoshi: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }

    // unit of sats. i.e. unpack 5000 => 5000 sats
    function unpack(uint unit_sats, address receiver) public override returns (bool) {
        // amount of wbtc
        // amount of satoshi = amount of wbtc * 10^10 (decimals 18 - 8 = 10)
        // btc:sats = 1:10^8, therefore 
        // multiplier = 10^8 * 10^10 = 10^18 = decimals
        uint amount_wbtc = unit_sats.min(IERC20(WBTC).balanceOf(msg.sender)); // amount of wbtc
        uint mint_amount = amount_wbtc.mul(10**decimals); // amount of satoshi

        require(IERC20(WBTC).transferFrom(msg.sender, address(this), amount_wbtc), 'Satoshi: WBTC_TRANSFER_FAILED');
        _mint(receiver, mint_amount);

        return true;
    }

    // unit of sats. i.e. pack 5000 => 0.00005000 WBTC
    function pack(uint unit_sats, address receiver) public override returns (bool) {
        // amount of satoshi
        // amount of wbtc = amount of satoshi / 10^10 (decimals 18 - 8 = 10)
        // btc:sats = 1:10^8, therefore divisor = 10^8 * 10^10 = 10^18
        uint amount_wbtc = unit_sats;
        uint amount_sats = unit_sats.mul(10**decimals);
        uint burn_amount = amount_sats.min(balanceOf[msg.sender]);

        _burn(msg.sender, burn_amount);
        require(IERC20(WBTC).transfer(receiver, amount_wbtc));

        return true;
    }

    function unpack(uint unit_sats) external override returns (bool) {
        return unpack(unit_sats, msg.sender);
    }

    function pack(uint unit_sats) external override returns (bool) {
        return pack(unit_sats, msg.sender);
    }

}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

interface ISatoshiERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function version() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function supplyCap() external pure returns (uint);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function WBTC() external pure returns (address);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function DOMAIN_TYPE_HASH() external view returns (bytes32);
    function PERMIT_TYPE_HASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    function unpack(uint amount, address receiver) external returns (bool);
    function pack(uint amount, address receiver) external returns (bool);
    function unpack(uint amount) external returns (bool);
    function pack(uint amount) external returns (bool);
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.7.0;

// @title Optimized overflow and underflow safe math operations
// @notice Contains methods for doing math operations that revert on overflow or underflow for minimal gas cost
library SafeMath {

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(x == 0 || (z = x * y) / x == y);
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x >= y ? x : y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
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