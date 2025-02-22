pragma solidity ^0.4.24;


/**
 * @title ERC165
 * @dev https://github.com/ethereum/EIPs/blob/master/EIPS/eip-165.md
 */
interface ERC165 {

  function supportsInterface(bytes4 _interfaceId)
    external
    view
    returns (bool);
}



contract SupportsInterfaceWithLookup is ERC165 {
  bytes4 public constant InterfaceId_ERC165 = 0x01ffc9a7;

  mapping(bytes4 => bool) internal supportedInterfaces;

  constructor()
    public
  {
    _registerInterface(InterfaceId_ERC165);
  }

  function supportsInterface(bytes4 _interfaceId)
    external
    view
    returns (bool)
  {
    return supportedInterfaces[_interfaceId];
  }

  function _registerInterface(bytes4 _interfaceId)
    internal
  {
    require(_interfaceId != 0xffffffff);
    supportedInterfaces[_interfaceId] = true;
  }
}


contract ERC721Basic is ERC165 {

  bytes4 internal constant InterfaceId_ERC721 = 0x80ac58cd;

  bytes4 internal constant InterfaceId_ERC721Exists = 0x4f558e79;

  bytes4 internal constant InterfaceId_ERC721Enumerable = 0x780e9d63;

  bytes4 internal constant InterfaceId_ERC721Metadata = 0x5b5e139f;

  event Transfer(
    address indexed _from,
    address indexed _to,
    uint256 indexed _tokenId
  );
  event Approval(
    address indexed _owner,
    address indexed _approved,
    uint256 indexed _tokenId
  );
  event ApprovalForAll(
    address indexed _owner,
    address indexed _operator,
    bool _approved
  );

  function balanceOf(address _owner) public view returns (uint256 _balance);
  function ownerOf(uint256 _tokenId) public view returns (address _owner);
  function exists(uint256 _tokenId) public view returns (bool _exists);

  function approve(address _to, uint256 _tokenId) public;
  function getApproved(uint256 _tokenId)
    public view returns (address _operator);

  function setApprovalForAll(address _operator, bool _approved) public;
  function isApprovedForAll(address _owner, address _operator)
    public view returns (bool);

  function transferFrom(address _from, address _to, uint256 _tokenId) public;
  function safeTransferFrom(address _from, address _to, uint256 _tokenId)
    public;

  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId,
    bytes _data
  )
    public;
}



contract ERC721Enumerable is ERC721Basic {
  function totalSupply() public view returns (uint256);
  function tokenOfOwnerByIndex(
    address _owner,
    uint256 _index
  )
    public
    view
    returns (uint256 _tokenId);

  function tokenByIndex(uint256 _index) public view returns (uint256);
}


contract ERC721Metadata is ERC721Basic {
  function name() external view returns (string _name);
  function symbol() external view returns (string _symbol);
  function tokenURI(uint256 _tokenId) public view returns (string);
}


contract ERC721 is ERC721Basic, ERC721Enumerable, ERC721Metadata {
}




contract ERC721Receiver {

  bytes4 internal constant ERC721_RECEIVED = 0x150b7a02;

  function onERC721Received(
    address _operator,
    address _from,
    uint256 _tokenId,
    bytes _data
  )
    public
    returns(bytes4);
}



library SafeMath {

  function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {

    if (a == 0) {
      return 0;
    }

    c = a * b;
    assert(c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {

    return a / b;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
    c = a + b;
    assert(c >= a);
    return c;
  }
}


library AddressUtils {


  function isContract(address addr) internal view returns (bool) {
    uint256 size;
    assembly { size := extcodesize(addr) }
    return size > 0;
  }

}


contract ERC721BasicToken is SupportsInterfaceWithLookup, ERC721Basic {

  using SafeMath for uint256;
  using AddressUtils for address;

  bytes4 private constant ERC721_RECEIVED = 0x150b7a02;

  mapping (uint256 => address) internal tokenOwner;
  mapping (uint256 => address) internal tokenApprovals;
  mapping (address => uint256) internal ownedTokensCount;
  mapping (address => mapping (address => bool)) internal operatorApprovals;

  constructor()
    public
  {
    _registerInterface(InterfaceId_ERC721);
    _registerInterface(InterfaceId_ERC721Exists);
  }

  function balanceOf(address _owner) public view returns (uint256) {
    require(_owner != address(0));
    return ownedTokensCount[_owner];
  }

  function ownerOf(uint256 _tokenId) public view returns (address) {
    address owner = tokenOwner[_tokenId];
    require(owner != address(0));
    return owner;
  }

  function exists(uint256 _tokenId) public view returns (bool) {
    address owner = tokenOwner[_tokenId];
    return owner != address(0);
  }

  function approve(address _to, uint256 _tokenId) public {
    address owner = ownerOf(_tokenId);
    require(_to != owner);
    require(msg.sender == owner || isApprovedForAll(owner, msg.sender));

    tokenApprovals[_tokenId] = _to;
    emit Approval(owner, _to, _tokenId);
  }

  function getApproved(uint256 _tokenId) public view returns (address) {
    return tokenApprovals[_tokenId];
  }

  function setApprovalForAll(address _to, bool _approved) public {
    require(_to != msg.sender);
    operatorApprovals[msg.sender][_to] = _approved;
    emit ApprovalForAll(msg.sender, _to, _approved);
  }

  function isApprovedForAll(
    address _owner,
    address _operator
  )
    public
    view
    returns (bool)
  {
    return operatorApprovals[_owner][_operator];
  }

  function transferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  )
    public
  {
    require(isApprovedOrOwner(msg.sender, _tokenId));
    require(_from != address(0));
    require(_to != address(0));

    clearApproval(_from, _tokenId);
    removeTokenFrom(_from, _tokenId);
    addTokenTo(_to, _tokenId);

    emit Transfer(_from, _to, _tokenId);
  }

  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId
  )
    public
  {
    // solium-disable-next-line arg-overflow
    safeTransferFrom(_from, _to, _tokenId, "");
  }

  function safeTransferFrom(
    address _from,
    address _to,
    uint256 _tokenId,
    bytes _data
  )
    public
  {
    transferFrom(_from, _to, _tokenId);
    // solium-disable-next-line arg-overflow
    require(checkAndCallSafeTransfer(_from, _to, _tokenId, _data));
  }

  function isApprovedOrOwner(
    address _spender,
    uint256 _tokenId
  )
    internal
    view
    returns (bool)
  {
    address owner = ownerOf(_tokenId);
    return (
      _spender == owner ||
      getApproved(_tokenId) == _spender ||
      isApprovedForAll(owner, _spender)
    );
  }


  function _mint(address _to, uint256 _tokenId) internal {
    require(_to != address(0));
    addTokenTo(_to, _tokenId);
    emit Transfer(address(0), _to, _tokenId);
  }

  function _burn(address _owner, uint256 _tokenId) internal {
    clearApproval(_owner, _tokenId);
    removeTokenFrom(_owner, _tokenId);
    emit Transfer(_owner, address(0), _tokenId);
  }

  function clearApproval(address _owner, uint256 _tokenId) internal {
    require(ownerOf(_tokenId) == _owner);
    if (tokenApprovals[_tokenId] != address(0)) {
      tokenApprovals[_tokenId] = address(0);
    }
  }

  function addTokenTo(address _to, uint256 _tokenId) internal {
    require(tokenOwner[_tokenId] == address(0));
    tokenOwner[_tokenId] = _to;
    ownedTokensCount[_to] = ownedTokensCount[_to].add(1);
  }

  function removeTokenFrom(address _from, uint256 _tokenId) internal {
    require(ownerOf(_tokenId) == _from);
    ownedTokensCount[_from] = ownedTokensCount[_from].sub(1);
    tokenOwner[_tokenId] = address(0);
  }

  function checkAndCallSafeTransfer(
    address _from,
    address _to,
    uint256 _tokenId,
    bytes _data
  )
    internal
    returns (bool)
  {
    if (!_to.isContract()) {
      return true;
    }
    bytes4 retval = ERC721Receiver(_to).onERC721Received(
      msg.sender, _from, _tokenId, _data);
    return (retval == ERC721_RECEIVED);
  }
}







contract ERC721Token is SupportsInterfaceWithLookup, ERC721BasicToken, ERC721 {

  // Token name
  string internal name_;

  // Token symbol
  string internal symbol_;

  // Mapping from owner to list of owned token IDs
  mapping(address => uint256[]) internal ownedTokens;

  // Mapping from token ID to index of the owner tokens list
  mapping(uint256 => uint256) internal ownedTokensIndex;

  // Array with all token ids, used for enumeration
  uint256[] internal allTokens;

  // Mapping from token id to position in the allTokens array
  mapping(uint256 => uint256) internal allTokensIndex;

  // Optional mapping for token URIs
  mapping(uint256 => string) internal tokenURIs;

  constructor(string _name, string _symbol) public {
    name_ = _name;
    symbol_ = _symbol;

    // register the supported interfaces to conform to ERC721 via ERC165
    _registerInterface(InterfaceId_ERC721Enumerable);
    _registerInterface(InterfaceId_ERC721Metadata);
  }

  function name() external view returns (string) {
    return name_;
  }

  function symbol() external view returns (string) {
    return symbol_;
  }

  function tokenURI(uint256 _tokenId) public view returns (string) {
    require(exists(_tokenId));
    return tokenURIs[_tokenId];
  }

  function tokenOfOwnerByIndex(
    address _owner,
    uint256 _index
  )
    public
    view
    returns (uint256)
  {
    require(_index < balanceOf(_owner));
    return ownedTokens[_owner][_index];
  }

  function totalSupply() public view returns (uint256) {
    return allTokens.length;
  }

  function tokenByIndex(uint256 _index) public view returns (uint256) {
    require(_index < totalSupply());
    return allTokens[_index];
  }


  function _setTokenURI(uint256 _tokenId, string _uri) internal {
    require(exists(_tokenId));
    tokenURIs[_tokenId] = _uri;
  }


  function addTokenTo(address _to, uint256 _tokenId) internal {
    super.addTokenTo(_to, _tokenId);
    uint256 length = ownedTokens[_to].length;
    ownedTokens[_to].push(_tokenId);
    ownedTokensIndex[_tokenId] = length;
  }


  function removeTokenFrom(address _from, uint256 _tokenId) internal {
    super.removeTokenFrom(_from, _tokenId);

    uint256 tokenIndex = ownedTokensIndex[_tokenId];
    uint256 lastTokenIndex = ownedTokens[_from].length.sub(1);
    uint256 lastToken = ownedTokens[_from][lastTokenIndex];

    ownedTokens[_from][tokenIndex] = lastToken;
    ownedTokens[_from].length--; // This also deletes the contents at the last position of the array

    ownedTokensIndex[_tokenId] = 0;
    ownedTokensIndex[lastToken] = tokenIndex;
  }


  function _mint(address _to, uint256 _tokenId) internal {
    super._mint(_to, _tokenId);

    allTokensIndex[_tokenId] = allTokens.length;
    allTokens.push(_tokenId);
  }


  function _burn(address _owner, uint256 _tokenId) internal {
    super._burn(_owner, _tokenId);

    if (bytes(tokenURIs[_tokenId]).length != 0) {
      delete tokenURIs[_tokenId];
    }

    uint256 tokenIndex = allTokensIndex[_tokenId];
    uint256 lastTokenIndex = allTokens.length.sub(1);
    uint256 lastToken = allTokens[lastTokenIndex];

    allTokens[tokenIndex] = lastToken;
    allTokens[lastTokenIndex] = 0;

    allTokens.length--;
    allTokensIndex[_tokenId] = 0;
    allTokensIndex[lastToken] = tokenIndex;
  }

}


contract receiptToken214 is ERC721Token {

  constructor() public ERC721Token("receipttoken214","receipttoken214") { }

  struct Token{
    address paid1;
    address paid2;
    address paid3;
    address paid4;
    address paid5;
    address paid6;
    address paid7;
    string whopaid;
    string fortunecookie;
    uint256 amt;
  }

  Token[] private tokens;

  function create(address paid1, address paid2, address paid3, address paid4, address paid5, address paid6, address paid7, uint256 randnum) public payable returns (uint256 _tokenId) {

string[48] memory arr = 
["Today it&#39;s up to you to create the peacefulness you long for.",
"A friend asks only for your time not your money.",
"If you refuse to accept anything but the best, you very often get it.",
"A smile is your passport into the hearts of others.",
"A good way to keep healthy is to eat more Chinese food.",
"Your high-minded principles spell success.",
"Hard work pays off in the future, laziness pays off now.",
"Change can hurt, but it leads a path to something better.",
"Enjoy the good luck a companion brings you.",
"People are naturally attracted to you.",
"A chance meeting opens new doors to success and friendship.",
"You learn from your mistakes...You will learn a lot today.",
"If you have something good in your life, don&#39;t let it go! ",
"What ever you&#39;re goal is in life, embrace it visualize it, and for it will be yours.",
"Your shoes will make you happy today.",
"You cannot love life until you live the life you love.",
"Be on the lookout for coming events; They cast their shadows beforehand.",
"Land is always on the mind of a flying bird.",
"The man or woman you desire feels the same about you.",
"Meeting adversity well is the source of your strength.",
"A dream you have will come true.",
"Our deeds determine us, as much as we determine our deeds.",
"Never give up. You&#39;re not a failure if you don&#39;t give up.",
"You will become great if you believe in yourself.",
"There is no greater pleasure than seeing your loved ones prosper.",
"A very attractive person has a message for you.",
"You already know the answer to the questions lingering inside your head.",
"It is now, and in this world, that we must live.",
"You must try, or hate yourself for not trying.",
"You can make your own happiness.",
"The greatest risk is not taking one.",
"The love of your life is stepping into your planet this summer.",
"Love can last a lifetime, if you want it to.",
"Adversity is the parent of virtue.",
"Serious trouble will bypass you.",
"A short stranger will soon enter your life with blessings to share.",
"Now is the time to try something new.",
"Wealth awaits you very soon.",
"If you feel you are right, stand firmly by your convictions.",
"If winter comes, can spring be far behind?",
"Keep your eye out for someone special.",
"You are very talented in many ways.",
"A stranger, is a friend you have not spoken to yet.",
"A new voyage will fill your life with untold memories.",
"You will travel to many exotic places in your lifetime.",
"Your ability for accomplishment will follow with success.",
"Nothing astonishes men so much as common sense and plain dealing.",
"Its amazing how much good you can do if you dont care who gets the credit."];

    uint256 amt=msg.value/7;
    paid1.transfer(amt);
    paid2.transfer(amt);
    paid3.transfer(amt);
    paid4.transfer(amt);
    paid5.transfer(amt);
    paid6.transfer(amt);
    paid7.transfer(amt);

    string memory whopaid=getWhoPiad(paid1,paid2,paid3,paid4,paid5,paid6,paid7,amt);
    

    Token memory _newToken = Token({
        paid1: paid1,
        paid2: paid2,
        paid3: paid3,
        paid4: paid4,
        paid5: paid5,
	    paid6: paid6,
	    paid7: paid7,
	    whopaid: whopaid,
        fortunecookie: arr[uint(randnum) % 48],
	    amt: amt
    });
    _tokenId = tokens.push(_newToken) - 1;
    
    string memory tokenUri = createTokenUri(_tokenId);
    _mint(msg.sender,_tokenId);
    _setTokenURI(_tokenId, tokenUri);
    
    
    
    
    
    emit Create(_tokenId,msg.sender,whopaid,amt,arr[uint(randnum) % 48],tokenUri);
    return _tokenId;
  }

  event Create(
    uint _id,
    address indexed _owner,string whopaid,uint256 amt, 
    string fortunecookie,
    string tokenUri
  );

  function get(uint256 _id) public view returns (address owner, string whopaid,string fortunecookie) {
    return (
    
      tokenOwner[_id],
      tokens[_id].whopaid,
      tokens[_id].fortunecookie
    );
  }

  function tokensOfOwner(address _owner) public view returns(uint256[]) {
    return ownedTokens[_owner];
  }


function toAsciiString(address x) returns (string) {
    bytes memory s = new bytes(40);
    for (uint i = 0; i < 20; i++) {
        byte b = byte(uint8(uint(x) / (2**(8*(19 - i)))));
        byte hi = byte(uint8(b) / 16);
        byte lo = byte(uint8(b) - 16 * uint8(hi));
        s[2*i] = char(hi);
        s[2*i+1] = char(lo);            
    }
    return string(s);
}

function char(byte b) returns (byte c) {
    if (b < 10) return byte(uint8(b) + 0x30);
    else return byte(uint8(b) + 0x57);
}

  function createTokenUri(uint256 tokenidnum) internal  returns (string){
    string memory uri = "https://www.millionetherwords.com/exchange/displaytoken/?s=";
    
    uri = strConcat(uri,uint2str(tokenidnum));
    
    return uri;
  }
  
  
  
  function getWhoPiad(address paid1, address paid2, address paid3, address paid4, address paid5, address paid6, address paid7,uint256 amt) internal  returns (string){
    string memory whopaid = "";
    
    whopaid = strConcat(whopaid,toAsciiString(paid1));
    whopaid = strConcat(whopaid,"-");

    whopaid = strConcat(whopaid,toAsciiString(paid2));
    whopaid = strConcat(whopaid,"-");
    
    whopaid = strConcat(whopaid,toAsciiString(paid3));
    whopaid = strConcat(whopaid,"-");
    
    whopaid = strConcat(whopaid,toAsciiString(paid4));
    whopaid = strConcat(whopaid,"-");
    
    whopaid = strConcat(whopaid,toAsciiString(paid5));
    whopaid = strConcat(whopaid,"-");
    
    whopaid = strConcat(whopaid,toAsciiString(paid6));
    whopaid = strConcat(whopaid,"-");
    
    whopaid = strConcat(whopaid,toAsciiString(paid7));
    whopaid = strConcat(whopaid,"-");
    
    whopaid = strConcat(whopaid,uint2str(amt));
    return whopaid;
  }

function uint2str(uint i) internal pure returns (string){
    if (i == 0) return "0";
    uint j = i;
    uint length;
    while (j != 0){
        length++;
        j /= 10;
    }
    bytes memory bstr = new bytes(length);
    uint k = length - 1;
    while (i != 0){
        bstr[k--] = byte(48 + i % 10);
        i /= 10;
    }
    return string(bstr);
}

  function appendUint8ToString(string inStr, uint8 v) internal pure returns (string str) {
        uint maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint i = 0;
        while (v != 0) {
            uint remainder = v % 10;
            v = v / 10;
            reversed[i++] = byte(48 + remainder);
        }
        bytes memory inStrb = bytes(inStr);
        bytes memory s = new bytes(inStrb.length + i);
        uint j;
        for (j = 0; j < inStrb.length; j++) {
            s[j] = inStrb[j];
        }
        for (j = 0; j < i; j++) {
            s[j + inStrb.length] = reversed[i - 1 - j];
        }
        str = string(s);
    }

    function strConcat(string _a, string _b) internal pure returns (string) {
        bytes memory _ba = bytes(_a);
        bytes memory _bb = bytes(_b);
        string memory ab = new string(_ba.length + _bb.length);
        bytes memory bab = bytes(ab);
        uint k = 0;
        for (uint i = 0; i < _ba.length; i++) bab[k++] = _ba[i];
        for (i = 0; i < _bb.length; i++) bab[k++] = _bb[i];
        return string(bab);
    }

}