// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.6.6;

contract Strategists {

    address[] vip = [
    0x627306090abaB3A6e1400e9345bC60c78a8BEf57,
    0xf17f52151EbEF6C7334FAD080c5704D77216b732,
    0xC5fdf4076b8F3A5357c5E395ab970B5B54098Fef,
    0x821aEa9a577a9b44299B9c15c88cf3087F3b5544,
    0x0d1d4e623D10F9FBA5Db95830F7d3839406C6AF2,
    0x2932b7A2355D6fecc4b5c0B6BD44cC31df247a2e,
    0x2191eF87E392377ec08E7c08Eb105Ef5448eCED5,
    0x0F4F2Ac550A1b4e2280d04c21cEa7EBD822934b5,
    0x6330A553Fc93768F612722BB8c2eC78aC90B3bbc,
    0x9b2e0c5456c9981AFBd5dbaDDB9B06F8Cc4b24dA,
    0x8FB9564fA69BE54b3cD8F2C1529E0050C1Ab8314,
    0x4070D17E5d6aB8359B6f8Bf33b4D2A404A52BD61,
    0xACB7c270ab1cC48c0Dc7294c05b3bA37E7751497,
    0x7E77fA182624eFa1E4A7aebF76568f28cD0ffD89,
    0x7D89664f086Ad5704c4224F41a0F12099C60bb6B,
    0xe9Af0Fb4D7e41C087085d3f5DfA144df8AaA5bE4,
    0x464A65839f913Ba7981560088060D54522B9f09f,
    0xDD154d935A26a90bB46C894D587163ceAc21FD4e,
    0x3DFE532adD8D12705e84837632d9d327D315E43F,
    0xe9F35C469a74bE518657Cb54c7b06Af7591C9A37,
    0xBAAc6717A93c9fFBe7eb1Dc4241dCA3C66FcE697
    ];


    mapping(address => bool) private vipMap;

    constructor(){
        for (uint8 i; i < vip.length; i++) {
            vipMap[vip[i]] = true;
        }
    }

    function isVip(address verified) public view returns (bool){
        return vipMap[verified];
    }

}

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "evmVersion": "berlin",
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