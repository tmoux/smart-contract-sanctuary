pragma solidity 0.4.24;

interface IMintManager {
    function getIndex() external view returns (uint256);
}

interface ISagaExchanger {
    /**
     * @dev Execute a transfer-request sent from the SGNToken contract.
     * @param to The transfer-request destination address.
     * @param value The transfer-request amount.
     */
    function transferFromSGNToken(address to, uint256 value) external;
}

interface IConversionManager {
    function sgn2sga(uint256 amount, uint256 index) external view returns (uint256);
}

interface ISGNAuthorizationManager {
    function isAuthorized(address wallet) external view returns (bool);
}


interface IContractAddressLocator {
    function get(bytes32 interfaceName) external view returns (address);
}

/**
 * @title Contract Address Locator Holder.
 * @dev Hold a contract address locator, which maps a unique interface name to every contract address in the system.
 * @dev Any contract which inherits from this contract can retrieve the address of any contract in the system.
 * @dev Thus, any contract can remain "oblivious" to the replacement of any other contract in the system.
 * @dev In addition to that, any function in any contract can be restricted to a specific caller.
 */
contract ContractAddressLocatorHolder {
    IContractAddressLocator private _contractAddressLocator;

    constructor(IContractAddressLocator contractAddressLocator) internal {
        require(contractAddressLocator != address(0));
        _contractAddressLocator = contractAddressLocator;
    }

    function getServer() external view returns (IContractAddressLocator) {
        return _contractAddressLocator;
    }

    function get(bytes32 interfaceName) internal view returns (address) {
        return _contractAddressLocator.get(interfaceName);
    }

    modifier only(bytes32 interfaceName) {
        require(msg.sender == get(interfaceName));
        _;
    }
}

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
interface IERC20 {
  function totalSupply() external view returns (uint256);

  function balanceOf(address who) external view returns (uint256);

  function allowance(address owner, address spender)
    external view returns (uint256);

  function transfer(address to, uint256 value) external returns (bool);

  function approve(address spender, uint256 value)
    external returns (bool);

  function transferFrom(address from, address to, uint256 value)
    external returns (bool);

  event Transfer(
    address indexed from,
    address indexed to,
    uint256 value
  );

  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 value
  );
}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that revert on error
 */
library SafeMath {

  /**
  * @dev Multiplies two numbers, reverts on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    // Gas optimization: this is cheaper than requiring &#39;a&#39; not being zero, but the
    // benefit is lost if &#39;b&#39; is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (a == 0) {
      return 0;
    }

    uint256 c = a * b;
    require(c / a == b);

    return c;
  }

  /**
  * @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b > 0); // Solidity only automatically asserts when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn&#39;t hold

    return c;
  }

  /**
  * @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a);
    uint256 c = a - b;

    return c;
  }

  /**
  * @dev Adds two numbers, reverts on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a);

    return c;
  }

  /**
  * @dev Divides two numbers and returns the remainder (unsigned integer modulo),
  * reverts when dividing by zero.
  */
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0);
    return a % b;
  }
}

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
 * Originally based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract ERC20 is IERC20 {
  using SafeMath for uint256;

  mapping (address => uint256) private _balances;

  mapping (address => mapping (address => uint256)) private _allowed;

  uint256 private _totalSupply;

  /**
  * @dev Total number of tokens in existence
  */
  function totalSupply() public view returns (uint256) {
    return _totalSupply;
  }

  /**
  * @dev Gets the balance of the specified address.
  * @param owner The address to query the balance of.
  * @return An uint256 representing the amount owned by the passed address.
  */
  function balanceOf(address owner) public view returns (uint256) {
    return _balances[owner];
  }

  /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param owner address The address which owns the funds.
   * @param spender address The address which will spend the funds.
   * @return A uint256 specifying the amount of tokens still available for the spender.
   */
  function allowance(
    address owner,
    address spender
   )
    public
    view
    returns (uint256)
  {
    return _allowed[owner][spender];
  }

  /**
  * @dev Transfer token for a specified address
  * @param to The address to transfer to.
  * @param value The amount to be transferred.
  */
  function transfer(address to, uint256 value) public returns (bool) {
    _transfer(msg.sender, to, value);
    return true;
  }

  /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender&#39;s allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param spender The address which will spend the funds.
   * @param value The amount of tokens to be spent.
   */
  function approve(address spender, uint256 value) public returns (bool) {
    require(spender != address(0));

    _allowed[msg.sender][spender] = value;
    emit Approval(msg.sender, spender, value);
    return true;
  }

  /**
   * @dev Transfer tokens from one address to another
   * @param from address The address which you want to send tokens from
   * @param to address The address which you want to transfer to
   * @param value uint256 the amount of tokens to be transferred
   */
  function transferFrom(
    address from,
    address to,
    uint256 value
  )
    public
    returns (bool)
  {
    require(value <= _allowed[from][msg.sender]);

    _allowed[from][msg.sender] = _allowed[from][msg.sender].sub(value);
    _transfer(from, to, value);
    return true;
  }

  /**
   * @dev Increase the amount of tokens that an owner allowed to a spender.
   * approve should be called when allowed_[_spender] == 0. To increment
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param spender The address which will spend the funds.
   * @param addedValue The amount of tokens to increase the allowance by.
   */
  function increaseAllowance(
    address spender,
    uint256 addedValue
  )
    public
    returns (bool)
  {
    require(spender != address(0));

    _allowed[msg.sender][spender] = (
      _allowed[msg.sender][spender].add(addedValue));
    emit Approval(msg.sender, spender, _allowed[msg.sender][spender]);
    return true;
  }

  /**
   * @dev Decrease the amount of tokens that an owner allowed to a spender.
   * approve should be called when allowed_[_spender] == 0. To decrement
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param spender The address which will spend the funds.
   * @param subtractedValue The amount of tokens to decrease the allowance by.
   */
  function decreaseAllowance(
    address spender,
    uint256 subtractedValue
  )
    public
    returns (bool)
  {
    require(spender != address(0));

    _allowed[msg.sender][spender] = (
      _allowed[msg.sender][spender].sub(subtractedValue));
    emit Approval(msg.sender, spender, _allowed[msg.sender][spender]);
    return true;
  }

  /**
  * @dev Transfer token for a specified addresses
  * @param from The address to transfer from.
  * @param to The address to transfer to.
  * @param value The amount to be transferred.
  */
  function _transfer(address from, address to, uint256 value) internal {
    require(value <= _balances[from]);
    require(to != address(0));

    _balances[from] = _balances[from].sub(value);
    _balances[to] = _balances[to].add(value);
    emit Transfer(from, to, value);
  }

  /**
   * @dev Internal function that mints an amount of the token and assigns it to
   * an account. This encapsulates the modification of balances such that the
   * proper events are emitted.
   * @param account The account that will receive the created tokens.
   * @param value The amount that will be created.
   */
  function _mint(address account, uint256 value) internal {
    require(account != 0);
    _totalSupply = _totalSupply.add(value);
    _balances[account] = _balances[account].add(value);
    emit Transfer(address(0), account, value);
  }

  /**
   * @dev Internal function that burns an amount of the token of a given
   * account.
   * @param account The account whose tokens will be burnt.
   * @param value The amount that will be burnt.
   */
  function _burn(address account, uint256 value) internal {
    require(account != 0);
    require(value <= _balances[account]);

    _totalSupply = _totalSupply.sub(value);
    _balances[account] = _balances[account].sub(value);
    emit Transfer(account, address(0), value);
  }

  /**
   * @dev Internal function that burns an amount of the token of a given
   * account, deducting from the sender&#39;s allowance for said account. Uses the
   * internal burn function.
   * @param account The account whose tokens will be burnt.
   * @param value The amount that will be burnt.
   */
  function _burnFrom(address account, uint256 value) internal {
    require(value <= _allowed[account][msg.sender]);

    // Should https://github.com/OpenZeppelin/zeppelin-solidity/issues/707 be accepted,
    // this function needs to emit an event with the updated approval.
    _allowed[account][msg.sender] = _allowed[account][msg.sender].sub(
      value);
    _burn(account, value);
  }
}

/**
 * @title Saga Genesis Token.
 * @dev ERC20 compatible.
 * @dev Burnable.
 * @dev KYC protected.
 * @dev Exchange SGN for SGA.
 */
contract SGNToken is ERC20, ContractAddressLocatorHolder {
    string public constant name = "Saga Genesis Token";
    string public constant symbol = "SGN";
    uint8  public constant decimals = 18;

    uint256 public constant TOTAL_SUPPLY = 107000000000000000000000000;

    constructor(IContractAddressLocator contractAddressLocator, address initialOwner) ContractAddressLocatorHolder(contractAddressLocator) public {
        _mint(initialOwner, TOTAL_SUPPLY);
    }

    function getSGNAuthorizationManager() public view returns (ISGNAuthorizationManager) {
        return ISGNAuthorizationManager(get("ISGNAuthorizationManager"));
    }

    function getConversionManager() public view returns (IConversionManager) {
        return IConversionManager(get("IConversionManager"));
    }

    function getSagaExchanger() public view returns (ISagaExchanger) {
        return ISagaExchanger(get("ISagaExchanger"));
    }

    function getMintManager() public view returns (IMintManager) {
        return IMintManager(get("IMintManager"));
    }

    /**
     * @dev Get the current SGA worth of a given SGN amount.
     * @param sgnAmount The amount of SGN.
     * @return The amount of SGA.
     */
    function toSgaAmount(uint256 sgnAmount) external view returns (uint256) {
        return _toSgaAmount(sgnAmount);
    }

    /**
     * @dev Standard ERC20 transfer operation with KYC protection added.
     * @param to The destination address.
     * @param value The amount of SGN.
     * @return Status (true if completed successfully, false otherwise).
     * @notice If destination is Saga Exchanger contract, then exchange SGN for SGA instead of transferring SGN.
     */
    function transfer(address to, uint256 value) public returns (bool) {
        ISGNAuthorizationManager pSGNAuthorizationManager = getSGNAuthorizationManager();
        require(pSGNAuthorizationManager.isAuthorized(msg.sender));
        if (to == address(getSagaExchanger()))
            return _sell(value) > 0;
        require(pSGNAuthorizationManager.isAuthorized(to));
        return super.transfer(to, value);
    }

    /**
     * @dev Standard ERC20 transfer operation with KYC protection added.
     * @param from The source address.
     * @param to The destination address.
     * @param value The amount of SGN.
     * @return Status (true if completed successfully, false otherwise).
     */
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        ISGNAuthorizationManager pSGNAuthorizationManager = getSGNAuthorizationManager();
        require(pSGNAuthorizationManager.isAuthorized(msg.sender));
        require(pSGNAuthorizationManager.isAuthorized(from));
        require(pSGNAuthorizationManager.isAuthorized(to));
        require(to != address(getSagaExchanger()));
        return super.transferFrom(from, to, value);
    }

    /**
     * @dev Exchange SGN for SGA with KYC protection added.
     * @param value The amount of SGN.
     * @return The amount of SGA.
     */
    function sell(uint256 value) external returns (uint256) {
        ISGNAuthorizationManager pSGNAuthorizationManager = getSGNAuthorizationManager();
        require(pSGNAuthorizationManager.isAuthorized(msg.sender));
        return _sell(value);
    }

    /**
     * @dev Exchange SGN for SGA.
     * @param sgnAmount The amount of SGN.
     * @return The amount of SGA.
     */
    function _sell(uint256 sgnAmount) private returns (uint256) {
        uint256 sgaAmount = _toSgaAmount(sgnAmount);
        require(sgaAmount > 0);
        _burn(msg.sender, sgnAmount);
        getSagaExchanger().transferFromSGNToken(msg.sender, sgaAmount);
        return sgaAmount;
    }

    /**
     * @dev Calculate the current SGA worth of a given SGN amount.
     * @param sgnAmount The amount of SGN.
     * @return The amount of SGA.
     */
    function _toSgaAmount(uint256 sgnAmount) private view returns (uint256) {
        return getConversionManager().sgn2sga(sgnAmount, getMintManager().getIndex());
    }
}