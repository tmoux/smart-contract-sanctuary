pragma solidity ^0.6.0;

contract Owned {
    address payable public owner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only available for owner");
        _;
    }

    function transferOwnership(address payable _newOwner) public onlyOwner {
        owner = _newOwner;
        emit OwnershipTransferred(msg.sender, _newOwner);
    }
}

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import './Owned.sol';
import './TerminateContractTemplate.sol';
import './interface/IERC20.sol';
import './interface/IExecute.sol';

contract TSC is TerminateContractTemplate {
    
    struct DepositERC20 {
        address tokens;
        uint256 value;
        string description;
        uint256 deposited;
    }
    
    struct DepositETH {
        uint256 value;
        string description;
        uint256 deposited;
    }
    
    struct TransferETH {
        address payable receiver;
        uint256 value;
        string description;
        bool transfered;
    }
    
    struct UploadSignature {
        address signer;
        bytes32 source;  // sha256 of document
        string description;
        bytes signature;
    }
    
    struct ListDepositERC20 {
        mapping(uint256 => DepositERC20) list;
        uint256 size;
    }
    
    struct ListDepositETH {
        mapping(uint256 => DepositETH) list;
        uint256 size;
    }
    
    struct ListTransferETH {
        mapping(uint256 => TransferETH) list;
        uint256 size;
    }
    
    struct ListUploadSignature {
        mapping(uint256 => UploadSignature) list;
        uint256 size;
    }
    
    struct Reward {
        address tokens;
        uint256 value;
    }
    
    struct StartTimingRequired {
        address tokens;
        uint256 value;
    }

    address payable public partner;
    
    uint256 public timeout;
    
    address payable public execute_contract;
    
    StartTimingRequired public startTimmingRequired;
    Reward public reward;
    
    ListDepositERC20 private listDepositERC20;
    ListDepositETH private listDepositETH;
    ListTransferETH private listTransferETH;
    ListUploadSignature private listUploadSignature;
    
    bool public ready;
    bool public isStartTimming;
    
    string public description;
    
    event StartContract(uint256 timestamp);
    event StartTiming(uint256 timestamp);
    event SignatureUploaded(uint256 indexed _index, bytes32 _source, address _signers, bytes _signature ,uint256 _timestamp);
    event DepositEthCompleted(uint256 indexed _index, uint256 _value, uint256 _timestamp);
    event DepositErc20Completed(uint256 indexed _index, address _tokens, uint256 _value, uint256 _timestamp);
    event TransferEthCompleted(uint256 indexed _index, address _receiver, uint256 _value, uint256 _timestamp);
    event ContractClosed(uint256 _timestamp, bool completed);
    
    modifier onlyPartner() {
        require(msg.sender == partner, "TSC: Only partner");
        _;
    }
    
    modifier onlyNotReady() {
        require(!ready, "TSC: Contract readied");
        _;
    }
    
    modifier onlyStartTimming() {
        require(isStartTimming, "TSC: Required start timming");
        _;
    }
    
    function setExecuteContract(address payable _address) public onlyOwner onlyNotReady isLive {
        execute_contract = _address;
    }
    
    function setupFunctions(
        
        address[] memory _depositERC20Tokens,
        uint256[] memory _depositERC20Values,
        string[] memory _depositERC20Descriptions,
        
        uint256[] memory _depositETHValues,
        string[] memory _depositETHDescriptions,
        
        address payable [] memory _transferETHReceivers,
        uint256[] memory _transferETHValues,
        string[] memory _transferETHDescriptions,
        
        address[] memory _signers,
        bytes32[] memory _source,
        string[] memory _signatureDescriptions
        
    ) public onlyOwner onlyNotReady isLive {
        require(_depositERC20Tokens.length == _depositERC20Values.length && _depositERC20Values.length == _depositERC20Descriptions.length, "TSC: Deposit ERC20 function not match");
        require(_transferETHReceivers.length == _transferETHValues.length && _transferETHValues.length == _transferETHDescriptions.length, "TSC: Transfer ETH function not match");
        require(_signers.length == _source.length && _source.length == _signatureDescriptions.length, "TSC: Signature function not match");
        require(_depositETHValues.length == _depositETHDescriptions.length, "TSC: Deposit ETH function not match");
        
        _setUpDepositErc20Functions(_depositERC20Tokens, _depositERC20Values, _depositERC20Descriptions);
        _setupDepositEthFunctions(_depositETHValues, _depositETHDescriptions);
        _setupTransferEthFunctions(_transferETHReceivers, _transferETHValues, _transferETHDescriptions);
        _setupUploadSignatureFunctions(_signers, _source, _signatureDescriptions);
    }
    
    
    function setupBasic (
        uint256 _timeout,
        uint256 _deadline,
    
        address _tokens_address_start, 
        uint256 _tokens_amount_start,
        
        address payable _partner, 
        string memory _description, 
        address payable _execute_contract,
        
        address _rewardToken,
        uint256 _rewardValue
    ) public onlyOwner onlyNotReady isLive returns(bool) {
        _setupBasic(_timeout, _deadline, _tokens_address_start, _tokens_amount_start, _partner, _description, _execute_contract, _rewardToken, _rewardValue);
    }
    
    
    function _setupBasic (
        uint256 _timeout,
        uint256 _deadline,
    
        address _tokens_address_start, 
        uint256 _tokens_amount_start,
        
        address payable _partner, 
        string memory _description, 
        address payable _execute_contract,
        
        address _rewardToken,
        uint256 _rewardValue
    ) private returns(bool) {
        partner = _partner;
        description = _description;
        execute_contract = _execute_contract;
        
        timeout = _timeout;
        expiration = _deadline;
        startTimmingRequired = StartTimingRequired({ tokens: _tokens_address_start, value: _tokens_amount_start });
        reward = Reward({ tokens: _rewardToken, value: _rewardValue });
        return true;
    }
    
    function _setUpDepositErc20Functions( address[] memory _tokens, uint256[] memory _values, string[] memory _descriptions) private returns(bool)  {
        for(uint256 i = 0; i < _tokens.length; i++) {
            require(_tokens[i] != address(0x0), "TSC: ERC20 tokens address in Deposit ERC20 Function is required different 0x0");
            require(_values[i] > 0, "TSC: value of ERC20 in Deposit ERC20 Function is required greater than 0");
            listDepositERC20.list[i] = DepositERC20(_tokens[i], _values[i], _descriptions[i], 0);
        }
        listDepositERC20.size = _tokens.length;
        return true;
    }
    
    function _setupDepositEthFunctions(uint256[] memory _values, string[] memory _descriptions) private returns(bool) {
        for(uint256 i = 0; i < _values.length; i++) {
            require(_values[i] > 0, "TSC: value of ETH in Deposit ETH Function is required greater than 0");
            listDepositETH.list[i] = DepositETH(_values[i], _descriptions[i], 0);
        }
        listDepositETH.size = _values.length;
        return true;
    }
    
    function _setupTransferEthFunctions(address payable[] memory _receivers, uint256[] memory _values, string[] memory _descriptions) private returns(bool) {
        for(uint256 i = 0; i < _receivers.length; i++) {
            require(_receivers[i] != address(0x0), "TSC: receiver in  in Transfer ETH Function is required different 0x0");
            require(_values[i] > 0, "TSC: value of ETH in Transfer ETH Function is required greater than 0");
            listTransferETH.list[i] = TransferETH(_receivers[i], _values[i], _descriptions[i], false);
        }
        listTransferETH.size = _receivers.length;
        return true;
    }
    
    function _setupUploadSignatureFunctions(address[] memory _signers, bytes32[] memory _source, string[] memory _signatureDescriptions) private returns(bool) {
        for(uint256 i = 0; i < _signers.length; i++) {
            require(_signers[i] != address(0x0), "TSC: signer in  in Upload Signature Function is required different 0x0");
            listUploadSignature.list[i] = UploadSignature(_signers[i], _source[i], _signatureDescriptions[i], "");
        }
        listUploadSignature.size = _signers.length;
        return true;
    }
    
    function start() public onlyOwner onlyNotReady isLive {
        require(startTimmingRequired.tokens != address(0x0), "TSC: Please setup ERC20 address to start");
        require(timeout > 0, "TSC: Please setup time out");
        require(execute_contract != address(0x0), "TSC: Please setup execute contract");
        if (reward.tokens != address(0x0)) {
            require(IERC20(reward.tokens).balanceOf(address(this)) >= reward.value, "TSC: Please deposit ERC20 token reward");
        } else {
            require(address(this).balance >= reward.value, "TSC: Please deposit ETH reward");
        }
        ready = true;
        emit StartContract(block.timestamp);
    }
    
    function startTimming() public onlyPartner isLive {
        require(!isStartTimming, "TSC: Timming started");
        require(IERC20(startTimmingRequired.tokens).transferFrom(msg.sender, address(this), startTimmingRequired.value), "TSC: Please approve transfer tokens for this contract");
        
        if (expiration > block.timestamp + timeout) {
            expiration = block.timestamp + timeout;
        }
        isStartTimming = true;
        emit StartTiming(block.timestamp);
    }
    
    receive() external payable onlyPartner isLive onlyStartTimming {
        uint256 total = msg.value;
        uint256 i = 0; 
        while (total > 0 && i < listDepositETH.size) {
            if (listDepositETH.list[i].deposited < listDepositETH.list[i].value) {
                uint256 remain = listDepositETH.list[i].value - listDepositETH.list[i].deposited;
                if (total > remain) {
                    total -= remain;
                    listDepositETH.list[i].deposited = listDepositETH.list[i].value;
                    emit DepositEthCompleted(i, listDepositETH.list[i].deposited, block.timestamp);
                } else {
                    total = 0;
                    listDepositETH.list[i].deposited += total;
                }
            }
            i++;
        }
    }
    
    function close() public isOver {
        bool completed = true;
        /*
        for (uint256 i = 0; i < listDepositETH.size; i++) {
            if (!isPassDepositErc20(i)) {
                completed = false;
                break;
            }
        }
        if (completed) {
            for (uint256 i = 0; i < listTransferETH.size; i++) {
                if (!isPassTransferEth(i)) {
                    completed = false;
                    break;
                }
            }
        }
        if (completed) {
            for (uint256 i = 0; i < listDepositERC20.size; i++) {
                if (!isPassDepositErc20(i)) {
                    completed = false;
                    break;
                }
            }
        }
        if (completed) {
            for (uint256 i = 0; i < listUploadSignature.size; i++) {
                if (!isPassSignature(i)) {
                    completed = false;
                    break;
                }
            }
        }
        */
        emit ContractClosed(block.timestamp, completed);
        if (execute_contract != address(0)) {
            if (reward.tokens != address(0x0) && reward.value > 0) {
                    IERC20(reward.tokens).transfer(execute_contract, reward.value);
            }
            if (startTimmingRequired.tokens != address(0x0) && startTimmingRequired.value > 0) {
                IERC20(startTimmingRequired.tokens).transfer(execute_contract, startTimmingRequired.value);
            }
            for (uint256 i = 0; i < listDepositERC20.size; i++) {
                if (listDepositERC20.list[i].tokens != address(0x0) && listDepositERC20.list[i].value > 0) {
                    IERC20(listDepositERC20.list[i].tokens).transfer(execute_contract, listDepositERC20.list[i].value);
                }
            }
            execute_contract.transfer(address(this).balance);
            if (completed) {
                IExecute(execute_contract).execute();
            } else {
                IExecute(execute_contract).revert();
                
            }
        } else {
            if (completed) {
                _closeCompleted();
            } else {
                _closeNotCompleted();
            }
        }
        if (completed) {
            address payable sender = address(uint160(address(msg.sender)));
            selfdestruct(sender);   
        } else {
            selfdestruct(partner);   
        }
    }
    
    function _closeCompleted() private {
        if (reward.tokens != address(0x0) && reward.value > 0) {
            IERC20(reward.tokens).transfer(partner, reward.value);
        }
        if (reward.tokens == address(0x0) && reward.value > 0) {
            partner.transfer(reward.value);
        }
        if (startTimmingRequired.tokens != address(0x0) && startTimmingRequired.value > 0) {
            IERC20(startTimmingRequired.tokens).transfer(partner, startTimmingRequired.value);
        }
        
        for (uint256 i = 0; i < listDepositERC20.size; i++) {
            if (listDepositERC20.list[i].tokens != address(0x0) && listDepositERC20.list[i].value > 0) {
                IERC20(listDepositERC20.list[i].tokens).transfer(partner, listDepositERC20.list[i].value);
            }
        }
    }
    
    function _closeNotCompleted() private {
        if (reward.tokens != address(0x0) && reward.value > 0) {
            IERC20(reward.tokens).transfer(msg.sender, reward.value);
        }
        if (startTimmingRequired.tokens != address(0x0) && startTimmingRequired.value > 0) {
            IERC20(startTimmingRequired.tokens).transfer(msg.sender, startTimmingRequired.value);
        }
        
        for (uint256 i = 0; i < listDepositERC20.size; i++) {
            if (listDepositERC20.list[i].tokens != address(0x0) && listDepositERC20.list[i].value > 0) {
                IERC20(listDepositERC20.list[i].tokens).transfer(msg.sender, listDepositERC20.list[i].value);
            }
        }
    }
    
    function depositEth(uint256 _index) public payable onlyPartner isLive onlyStartTimming {
        require(listDepositETH.size > _index, "TSC: Invalid required functions");
        require(listDepositETH.list[_index].deposited < listDepositETH.list[_index].value, "TSC: Deposit over");
        require(msg.value >= listDepositETH.list[_index].value);
        listDepositETH.list[_index].deposited += msg.value;
        emit DepositEthCompleted(_index, listDepositETH.list[_index].deposited, block.timestamp);
    }
    
    function transferEth(uint256 _index) public payable onlyPartner isLive onlyStartTimming {
        require(listTransferETH.size > _index, "TSC: Invalid required functions");
        require(listTransferETH.list[_index].transfered == false, "TSC: Function is passed");
        require(msg.value >= listTransferETH.list[_index].value);
        listTransferETH.list[_index].transfered = true;
        listTransferETH.list[_index].receiver.transfer(listTransferETH.list[_index].value);
        emit TransferEthCompleted(_index, listTransferETH.list[_index].receiver, listTransferETH.list[_index].value, block.timestamp);
    }
    
    function depositErc20(uint256 _index) public payable onlyPartner isLive onlyStartTimming {
        require(listDepositERC20.size > _index, "TSC: Invalid required functions");
        require(listDepositERC20.list[_index].deposited <= listDepositERC20.list[_index].value, "TSC: Function is passed");
        
        require(IERC20(listDepositERC20.list[_index].tokens).transferFrom(msg.sender, address(execute_contract), listDepositERC20.list[_index].value), "TSC: Please approve transfer tokens for this contract");
        
        listDepositERC20.list[_index].deposited = listDepositERC20.list[_index].value;
        emit DepositErc20Completed(_index, listDepositERC20.list[_index].tokens, listDepositERC20.list[_index].value, block.timestamp);
    }
    
    function uploadSignature(uint256 _index, bytes memory _signature) public onlyPartner isLive onlyStartTimming {
        require(listUploadSignature.size > _index, "TSC: Invalid required functions");
        require(verify(listUploadSignature.list[_index].signer, listUploadSignature.list[_index].source, _signature));
        listUploadSignature.list[_index].signature = _signature;
        emit SignatureUploaded(_index, listUploadSignature.list[_index].source, listUploadSignature.list[_index].signer, _signature, block.timestamp);
    }
    
    function verify(address _signer, bytes32 _messageHash, bytes memory _signature) private pure returns (bool) {
        return recoverSigner(_messageHash, _signature) == _signer;
    }
    
    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) private pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }
    
    function getEthSignedMessageHash(bytes32 _messageHash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }
    
    function splitSignature(bytes memory sig) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // implicitly return (r, s, v)
    }
    
    function isPassDepositErc20(uint256 _index) public view returns(bool) {
        require(listDepositERC20.size > _index, "TSC: Invalid required functions");
        return listDepositERC20.list[_index].value <= listDepositERC20.list[_index].deposited;
    }
    
    function isPassDepositEth(uint256 _index) public view returns(bool) {
        require(listDepositETH.size > _index, "TSC: Invalid required functions");
        return listDepositETH.list[_index].value <= listDepositETH.list[_index].deposited;
    }
    
    function isPassTransferEth(uint256 _index) public view returns(bool) {
        require(listTransferETH.size > _index, "TSC: Invalid required functions");
        return listTransferETH.list[_index].transfered;
    }
    
    function isPassSignature(uint256 _index) public view returns(bool) {
        require(listUploadSignature.size > _index, "TSC: Invalid required functions");
        return listUploadSignature.list[_index].signature.length > 0;
    }
    
    function listDepositEthSize() public view returns(uint256) {
        return listDepositETH.size;
    }
    
    function listDepositErc20Size() public view returns(uint256) {
        return listDepositERC20.size;
    }
    
    function listTransferEthSize() public view returns(uint256) {
        return listTransferETH.size;
    }
    
    function listUploadSignatureSize() public view returns(uint256) {
        return listUploadSignature.size;
    }
    
    function depositEthFunction(uint256 _index) public view returns(uint256 _value, string memory _description, uint256 _deposited) {
        require(listDepositETH.size > _index, "TSC: Invalid required functions");
        
        _value = listDepositETH.list[_index].value;
        _description = listDepositETH.list[_index].description;
        _deposited = listDepositETH.list[_index].deposited;
    }
    
    function depositErc20Function(uint256 _index) public view returns(address _tokens, uint256 _value, string memory _symbol,string memory _description, uint256 _deposited) {
        require(listDepositERC20.size > _index, "TSC: Invalid required functions");
        _tokens = listDepositERC20.list[_index].tokens;
        _value = listDepositERC20.list[_index].value;
        _description = listDepositERC20.list[_index].description;
        _deposited = listDepositERC20.list[_index].deposited;
        if (_tokens != address(0x0)) {
            _symbol = IERC20(_tokens).symbol();
        }
    }
    
    function transferEthFunction(uint256 _index) public view returns(address _receiver, uint256 _value, string memory _description, bool _transfered) {
        require(listTransferETH.size > _index, "TSC: Invalid required functions");
        
        _receiver = listTransferETH.list[_index].receiver;
        _value = listTransferETH.list[_index].value;
        _description = listTransferETH.list[_index].description;
        _transfered = listTransferETH.list[_index].transfered;
    }
    
    function uploadSignatureFunction(uint256 _index) public view returns(address _signer, bytes32 _source, string memory _description, bytes memory _signature) {
        require(listUploadSignature.size > _index, "TSC: Invalid required functions");
        
        _signer = listUploadSignature.list[_index].signer;
        _source = listUploadSignature.list[_index].source;
        _description = listUploadSignature.list[_index].description;
        _signature = listUploadSignature.list[_index].signature;
    }

}

pragma solidity ^0.6.0;

import './Owned.sol';

contract TerminateContractTemplate is Owned {
    uint256 public expiration;
    constructor() public {
        expiration = 0;
    }
    
    function setExpiration(uint256 _expiration) public virtual onlyOwner  {
        expiration = _expiration;
    }
    
    function terminate() public virtual onlyOwner isOver {
        selfdestruct(owner);
    }
    
    modifier isLive() {
        require(expiration == 0 || block.timestamp < expiration, "Terminated: Time over");
        _;
    }
    
    modifier isOver() {
        require(expiration != 0 && block.timestamp > expiration, "Terminated: Contract is live");
        _;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    
    function symbol() external view returns (string memory);
    
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

pragma solidity ^0.6.0;

interface IExecute {
    function execute() external returns (bool);
    function revert() external returns (bool);
}

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
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