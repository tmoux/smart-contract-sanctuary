// SPDX-License-Identifier: MIT

			pragma solidity 0.6.12;


			contract GreetZ {
			  string greeting;

			  constructor(string memory _greeting) public {

			    greeting = _greeting;
			  }

			  function greet() public view returns (string memory) {
			    return greeting;
			  }

			  function setGreeting(string memory _greeting) public {

			    greeting = _greeting;
			  }
			}

{
  "optimizer": {
    "enabled": false,
    "runs": 200
  },
  "evmVersion": "istanbul",
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