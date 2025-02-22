pragma solidity ^0.4.19;

// File: contracts/SafeMath.sol

/**
 * Math operations with safety checks
 */
library SafeMath {
  function mul(uint a, uint b) internal pure returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint a, uint b) internal pure returns (uint) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn&#39;t hold
    return c;
  }

  function sub(uint a, uint b) internal pure returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function add(uint a, uint b) internal pure returns (uint) {
    uint c = a + b;
    assert(c >= a);
    return c;
  }

  function max64(uint64 a, uint64 b) internal pure returns (uint64) {
    return a >= b ? a : b;
  }

  function min64(uint64 a, uint64 b) internal pure returns (uint64) {
    return a < b ? a : b;
  }

  function max256(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? a : b;
  }

  function min256(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }
}

// File: contracts/ERC20.sol

/**
 * @title ERC20Basic
 * @dev Simpler version of ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/179
 */
contract ERC20Basic {
  uint256 public totalSupply;
  function balanceOf(address who) public view returns (uint256);
  function transfer(address to, uint256 value) public returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
}

/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {
  function allowance(address owner, address spender) public view returns (uint256);
  function transferFrom(address from, address to, uint256 value) public returns (bool);
  function approve(address spender, uint256 value) public returns (bool);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title Basic token
 * @dev Basic version of StandardToken, with no allowances.
 */
contract BasicToken is ERC20Basic {
  using SafeMath for uint256;

  mapping(address => uint256) balances;

 /**
  * @dev transfer token for a specified address
  * @param _to The address to transfer to.
  * @param _value The amount to be transferred.
  */
  function transfer(address _to, uint256 _value) public returns (bool) {
    require(_to != address(0));
    require(_value <= balances[msg.sender]);

    // SafeMath.sub will throw if there is not enough balance.
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    Transfer(msg.sender, _to, _value);
    return true;
  }

 /**
  * @dev Gets the balance of the specified address.
  * @param _owner The address to query the the balance of.
  * @return An uint256 representing the amount owned by the passed address.
  */
  function balanceOf(address _owner) public view returns (uint256 balance) {
    return balances[_owner];
  }

}

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * @dev https://github.com/ethereum/EIPs/issues/20
 * @dev Based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is ERC20, BasicToken {

  mapping (address => mapping (address => uint256)) internal allowed;


  /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amount of tokens to be transferred
   */
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
    require(_to != address(0));
    require(_value <= balances[_from]);
    require(_value <= allowed[_from][msg.sender]);

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    Transfer(_from, _to, _value);
    return true;
  }

  /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   *
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender&#39;s allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
  function approve(address _spender, uint256 _value) public returns (bool) {
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

  /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param _owner address The address which owns the funds.
   * @param _spender address The address which will spend the funds.
   * @return A uint256 specifying the amount of tokens still available for the spender.
   */
  function allowance(address _owner, address _spender) public view returns (uint256) {
    return allowed[_owner][_spender];
  }

  /**
   * @dev Increase the amount of tokens that an owner allowed to a spender.
   *
   * approve should be called when allowed[_spender] == 0. To increment
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param _spender The address which will spend the funds.
   * @param _addedValue The amount of tokens to increase the allowance by.
   */
  function increaseApproval(address _spender, uint _addedValue) public returns (bool) {
    allowed[msg.sender][_spender] = allowed[msg.sender][_spender].add(_addedValue);
    Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
    return true;
  }

  /**
   * @dev Decrease the amount of tokens that an owner allowed to a spender.
   *
   * approve should be called when allowed[_spender] == 0. To decrement
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param _spender The address which will spend the funds.
   * @param _subtractedValue The amount of tokens to decrease the allowance by.
   */
  function decreaseApproval(address _spender, uint _subtractedValue) public returns (bool) {
    uint oldValue = allowed[msg.sender][_spender];
    if (_subtractedValue > oldValue) {
      allowed[msg.sender][_spender] = 0;
    } else {
      allowed[msg.sender][_spender] = oldValue.sub(_subtractedValue);
    }
    Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
    return true;
  }

}

// File: contracts/ERC223.sol

/**
 * ERC20-compatible version of ERC223
 * https://github.com/Dexaran/ERC223-token-standard/tree/ERC20_compatible
 */
contract ERC223Basic is StandardToken {
    function transfer(address to, uint value, bytes data) public;
    event Transfer(address indexed from, address indexed to, uint value, bytes indexed data);
}

/**
 * Contract that is working with ERC223 tokens
 */
contract ERC223ReceivingContract {
    function tokenFallback(address _from, uint _value, bytes _data) public;
}

/**
 * ERC20-compatible version of ERC223
 * https://github.com/Dexaran/ERC223-token-standard/tree/ERC20_compatible
 */
contract ERC223BasicToken is ERC223Basic {
    using SafeMath for uint;

    /**
     * @dev Fix for the ERC20 short address attack.
     */
    modifier onlyPayloadSize(uint size) {
        require(msg.data.length >= size + 4);
        _;
    }

    // Function that is called when a user or another contract wants to transfer funds .
    function transfer(address to, uint value, bytes data) onlyPayloadSize(2 * 32) public {
        // Standard function transfer similar to ERC20 transfer with no _data .
        // Added due to backwards compatibility reasons .
        uint codeLength;

        assembly {
            // Retrieve the size of the code on target address, this needs assembly .
            codeLength := extcodesize(to)
        }

        balances[msg.sender] = balances[msg.sender].sub(value);
        balances[to] = balances[to].add(value);
        if(codeLength > 0) {
            ERC223ReceivingContract receiver = ERC223ReceivingContract(to);
            receiver.tokenFallback(msg.sender, value, data);
        }
        Transfer(msg.sender, to, value);  // ERC20 transfer event
        Transfer(msg.sender, to, value, data);  // ERC223 transfer event
    }

    // Standard function transfer similar to ERC20 transfer with no _data .
    // Added due to backwards compatibility reasons .
    function transfer(address to, uint256 value) onlyPayloadSize(2 * 32)  public returns (bool) {
        uint codeLength;

        assembly {
            // Retrieve the size of the code on target address, this needs assembly .
            codeLength := extcodesize(to)
        }

        balances[msg.sender] = balances[msg.sender].sub(value);
        balances[to] = balances[to].add(value);
        if(codeLength > 0) {
            ERC223ReceivingContract receiver = ERC223ReceivingContract(to);
            bytes memory empty;
            receiver.tokenFallback(msg.sender, value, empty);
        }
        Transfer(msg.sender, to, value);  // ERC20 transfer event
        return true;
    }
}

// File: contracts/DogRacingToken.sol

/**
 * DogRacing Token
 */
contract DogRacingToken is ERC223BasicToken {
  using SafeMath for uint256;

  string constant public name = "Dog Racing";
  string constant public symbol = "DGR";
  uint8 constant public decimals = 3;
  uint256 constant public totalSupply 	= 326250000 * 1000;	// Supply is in the smallest units

  address public owner;   // owner address

  modifier onlyOwner {
    require(owner == msg.sender);
    _;
  }

  function DogRacingToken() public {
    owner = msg.sender;
    balances[owner] = totalSupply;   // All tokens are assigned to the owner
  }

  // Owner may burn own tokens
  function burnTokens(uint256 amount) onlyOwner external {
    balances[owner] = balances[owner].sub(amount);
  }
}

// File: contracts/DogRacingCrowdsale.sol

/**
 * DogRacing Crowdsale
 */
contract DogRacingCrowdsale {
  using SafeMath for uint256;

  DogRacingToken public token;		// Token contract address

  uint256 public stage1_start;		// Crowdsale timing
  uint256 public stage2_start;
  uint256 public stage3_start;
  uint256 public stage4_start;
  uint256 public crowdsale_end;

  uint256 public stage1_price;		// Prices in token millis / ETH
  uint256 public stage2_price;		
  uint256 public stage3_price;		
  uint256 public stage4_price;

  uint256 public hard_cap_wei;		// Crowdsale hard cap in wei

  address public owner;   			// Owner address

  uint256 public wei_raised;		// Total Wei raised by crowdsale

  event TokenPurchase(address buyer, uint256 weiAmount, uint256 tokensAmount);

  modifier onlyOwner {
    require(owner == msg.sender);
   _;
  }

  modifier withinCrowdsaleTime {
	require(now >= stage1_start && now < crowdsale_end);
	_;
  }

  modifier afterCrowdsale {
	require(now >= crowdsale_end);
	_;
  }

  modifier withinCap {
  	require(wei_raised < hard_cap_wei);
	_;
  }

  // Constructor
  function DogRacingCrowdsale(DogRacingToken _token,
  							  uint256 _stage1_start, uint256 _stage2_start, uint256 _stage3_start, uint256 _stage4_start, uint256 _crowdsale_end,
  							  uint256 _stage1_price, uint256 _stage2_price, uint256 _stage3_price, uint256 _stage4_price,
  							  uint256 _hard_cap_wei) public {
  	require(_stage1_start > now);
  	require(_stage2_start > _stage1_start);
  	require(_stage3_start > _stage2_start);
  	require(_stage4_start > _stage3_start);
  	require(_crowdsale_end > _stage4_start);
  	require(_stage1_price > 0);
  	require(_stage2_price < _stage1_price);
  	require(_stage3_price < _stage2_price);
  	require(_stage4_price < _stage3_price);
  	require(_hard_cap_wei > 0);
    require(_token != address(0));

  	owner = msg.sender;

  	token = _token;

  	stage1_start = _stage1_start;
  	stage2_start = _stage2_start;
  	stage3_start = _stage3_start;
  	stage4_start = _stage4_start;
  	crowdsale_end = _crowdsale_end;

  	stage1_price = _stage1_price;
  	stage2_price = _stage2_price;
  	stage3_price = _stage3_price;
  	stage4_price = _stage4_price;

  	hard_cap_wei = _hard_cap_wei;
  }

  // get current price in token millis / ETH
  function getCurrentPrice() public view withinCrowdsaleTime returns (uint256) {
  	if (now < stage2_start) {
  		return stage1_price;
  	} else if (now < stage3_start) {
  		return stage2_price;
  	} else if (now < stage4_start) {
  		return stage3_price;
  	} else {
  		return stage4_price;
  	}
  }

  // get amount in token millis for amount in wei
  function getTokenAmount(uint256 weiAmount) internal view returns (uint256) {
    uint256 price = getCurrentPrice();
    return weiAmount.mul(price).div(1 ether);
  }

  // fallback function
  function () external payable {
    buyTokens(msg.sender);
  }

  // tokens fallback function
  function tokenFallback(address, uint256, bytes) external pure {
  }

  // tokens purchase
  function buyTokens(address beneficiary) public withinCrowdsaleTime withinCap payable {
   	uint256 wei_amount = msg.value;
    
    require(beneficiary != address(0));
    require(wei_amount != 0);
 
    // calculate token amount to be sold
    uint256 tokens = getTokenAmount(wei_amount);

    // update state
    wei_raised = wei_raised.add(wei_amount);
    require(wei_raised <= hard_cap_wei);

    // deliver tokens
    token.transfer(beneficiary, tokens);

    TokenPurchase(beneficiary, wei_amount, tokens);

    // deliver ether
    owner.transfer(msg.value);
  }

  // Remaining tokens withdrawal
  function withdrawTokens() external onlyOwner afterCrowdsale {
  	uint256 tokens_remaining = token.balanceOf(address(this));
  	token.transfer(owner, tokens_remaining);
  }

}