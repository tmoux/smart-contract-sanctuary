// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

contract SimpleStorage {
  bytes private data;

  function updateData(bytes memory _data) external {
    data = _data;
  }
  function readData() external view returns(bytes memory) {
    return data;
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