// SPDX-License-Identifier: UNLICENSED
pragma solidity <=0.7.4;

abstract contract ReentrancyGuard {

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface ERC721TokenReceiver
{
  function onERC721Received(
    address _operator,
    address _from,
    uint256 _tokenId,
    bytes calldata _data
  )
    external
    returns(bytes4);
}

interface AggregatorV3Interface {

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

}

interface IERC721 is IERC165 {

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function name() external view returns(string memory);
    function symbol() external view returns(string memory);
    function totalSupply() external view returns(string memory);
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function setApprovalForAll(address operator, bool _approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

library SafeMath {
    
	function add(uint256 a, uint256 b) internal pure returns (uint256) {
		uint256 c = a + b;
		require(c >= a, "SafeMath: addition overflow");

		return c;
	}

	function sub(uint256 a, uint256 b) internal pure returns (uint256) {
		return sub(a, b, "SafeMath: subtraction overflow");
	}

	function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
		require(b <= a, errorMessage);
		uint256 c = a - b;

		return c;
	}

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
		if (a == 0) {
			return 0;
		}

		uint256 c = a * b;
		require(c / a == b, "multiplication overflow");

		return c;
	}

	function div(uint256 a, uint256 b) internal pure returns (uint256) {
		return div(a, b, "SafeMath: division by zero");
	}

	function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
		require(b > 0, errorMessage);
		uint256 c = a / b;
		// assert(a == b * c + a % b); // There is no case in which this doesn't hold

		return c;
	}

}

contract Sale is ReentrancyGuard, ERC721TokenReceiver {

    IERC721 public niftyPunks;
    // AggregatorV3Interface public ref;

    address public admin;
    uint256 public price;           // In-terms of USD = $ 1 = 100000000
    uint256 public sold;
    uint256[] private forSale;

    mapping(bytes => address) private oracles;
    mapping(bytes => address) private contracts;

    modifier hasAccess(){
        require(msg.sender == admin);
        _;
    }

    modifier isZero(address _addr) {
        require(_addr != address(0));
        _;
    }

    constructor(address punksContract_, uint256 initialPrice_){
        admin = msg.sender;
        niftyPunks = IERC721(punksContract_);
        price = initialPrice_;
    }

    function putForSale(uint256 tokenId) public virtual hasAccess returns(bool){
        require(
            niftyPunks.getApproved(tokenId) == address(this) 
            || niftyPunks.isApprovedForAll(msg.sender,address(this)), "Error : Insufficient Access"
        );
        forSale.push(tokenId);
        niftyPunks.safeTransferFrom(msg.sender, address(this) , tokenId);
        return true;
    }

    // function blindBuy() public payable returns(bool){
    //     require(msg.value == price,"Wrong Purchase Price");
    //     uint256 tokenId = forSale[sold];
    //     sold+= 1;
    //     niftyPunks.safeTransferFrom(address(this), msg.sender, tokenId);
    //     payable(admin).transfer(msg.value);
    //     return true;
    // }

    function buyWithEth() public virtual payable returns(uint256) {
        require(resolveToken("ETH",18) <= msg.value,"Underflow Error");
        uint256 tokenId = forSale[sold];
        sold+= 1;
        niftyPunks.safeTransferFrom(address(this), msg.sender, tokenId);
        payable(admin).transfer(msg.value);
        return tokenId;
    }

    function resolveToken(string memory _token, uint256 _decimal) public virtual view returns(uint256){
        uint256 tokenPrice = uint256(fetchPrice(_token));                         // 8 - decimal token price
        return SafeMath.div(
            SafeMath.mul(price,_decimal),tokenPrice
        );
    }
    
    function setPrice(uint256 _price) public hasAccess returns(bool){
        price = _price;
        return true;
    }

    function setOracle(address _oracle, string memory _token) public hasAccess isZero(_oracle) returns(bool){
        oracles[bytes(_token)] = _oracle;
        return true; 
    }

    function setContract(address _contract, string memory _token) public hasAccess isZero(_contract) returns(bool){
        contracts[bytes(_token)] = _contract;
        return true; 
    }

    function fetchPrice(string memory _token) public virtual view returns (int) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(oracles[bytes(_token)]).latestRoundData();
        return price;
    }

    function fetchOracle(string memory _token) public virtual view returns (address){
        return oracles[bytes(_token)];
    }

    function fetchContract(string memory _token) public virtual view returns (address){
        return contracts[bytes(_token)];
    }

    function drain(uint256 tokenId) public virtual hasAccess returns(bool){
        niftyPunks.safeTransferFrom(address(this), admin, tokenId);
        return true;
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    )
        external
        pure
        override
        returns(bytes4)
    {
        _operator;
        _from;
        _tokenId;
        _data;
        return 0x150b7a02;
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