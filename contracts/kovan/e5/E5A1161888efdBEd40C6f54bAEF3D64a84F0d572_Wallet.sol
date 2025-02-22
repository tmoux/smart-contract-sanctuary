pragma solidity ^0.8.0;

contract Wallet {
    address[] public approvers;
    uint public quorum;
    struct Transfer {
        uint id;
        uint amount;
        address to;
        uint approvals;
        bool sent;
    }
    Transfer[] public transfers;
    mapping(address => mapping(uint => bool)) public approvals;
    
    constructor(address[] memory _approvers, uint _quorum) {
        approvers = _approvers;
        quorum = _quorum;
    }
    
    function getApprovers() external view returns(address[] memory) {
        return approvers;
    }
    
    function getTransfers() external view returns(Transfer[] memory) {
        return transfers;
    }
    
    function createTransfer(uint amount, address to) external onlyApprover() {
        transfers.push(Transfer(
            transfers.length,
            amount,
            to,
            0,
            false
        ));
        // could approve transfer from sender here
    }
    
    function approveTransfer(uint id) external onlyApprover() {
        require(transfers[id].sent == false, 'transfer has already been sent');
        require(approvals[msg.sender][id] == false, 'cannot approve transfer twice');
        
        approvals[msg.sender][id] = true;
        transfers[id].approvals++;
        
        if(transfers[id].approvals >= quorum) {
            transfers[id].sent = true;
            address to = transfers[id].to;
            uint amount = transfers[id].amount;
            payable(to).transfer(amount);
        }
    }
    
    receive() external payable {}
    
    modifier onlyApprover() {
        bool allowed = false;
        
        for(uint i = 0; i < approvers.length; i++) {
            if(approvers[i] == msg.sender) {
                allowed = true;
            }
        }
        require(allowed == true, "only approver allowed");
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