/**
 *Submitted for verification at BscScan.com on 2021-07-23
*/

pragma solidity ^0.4.2;

/// Implements ERC 20 Token standard: https://github.com/ethereum/EIPs/issues/20
/// @title Abstract token contract - Functions to be implemented by token contracts.

contract AbstractToken {
    // This is not an abstract function, because solc won't recognize generated getter functions for public variables as functions
    function totalSupply() constant returns (uint256 supply) {}
    function balanceOf(address owner) constant returns (uint256 balance);
    function transfer(address to, uint256 value) returns (bool success);
    function transferFrom(address from, address to, uint256 value) returns (bool success);
    function approve(address spender, uint256 value) returns (bool success);
    function allowance(address owner, address spender) constant returns (uint256 remaining);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Issuance(address indexed to, uint256 value);
}

contract StandardToken is AbstractToken {

    /*
     *  Data structures
     */
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
    uint256 public totalSupply;

    /*
     *  Read and write storage functions
     */
    /// @dev Transfers sender's tokens to a given address. Returns success.
    /// @param _to Address of token receiver.
    /// @param _value Number of tokens to transfer.
    function transfer(address _to, uint256 _value) returns (bool success) {
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        }
        else {
            return false;
        }
    }

    /// @dev Allows allowed third party to transfer tokens from one address to another. Returns success.
    /// @param _from Address from where tokens are withdrawn.
    /// @param _to Address to where tokens are sent.
    /// @param _value Number of tokens to transfer.
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
      if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        }
        else {
            return false;
        }
    }

    /// @dev Returns number of tokens owned by given address.
    /// @param _owner Address of token owner.
    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    /// @dev Sets approved amount of tokens for spender. Returns success.
    /// @param _spender Address of allowed account.
    /// @param _value Number of approved tokens.
    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    /*
     * Read storage functions
     */
    /// @dev Returns number of allowed tokens for given address.
    /// @param _owner Address of token owner.
    /// @param _spender Address of token spender.
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }

}

/**
 * Math operations with safety checks
 */
contract SafeMath {
  function mul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint a, uint b) internal returns (uint) {
    assert(b > 0);
    uint c = a / b;
    assert(a == b * c + a % b);
    return c;
  }

  function sub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function add(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c >= a);
    return c;
  }

  function assert(bool assertion) internal {
    if (!assertion) {
      throw;
    }
  }
}


/// @title Token contract - Implements Standard Token Interface but adds Pyramid Scheme Support :)
/// @author Rishab Hegde - <[email protected]>
contract PonziCoin is StandardToken, SafeMath {

    /*
     * Token meta data
     */
    string constant public name = "PonziCoin";
    string constant public symbol = "SEC";
    uint8 constant public decimals = 3;

    uint public buyPrice = 250000000 wei;
    uint public sellPrice = 250000000 wei;
    uint public tierBudget = 100000;
    uint public floor = 0;

    // Since one cannot iterate through a mapping, you must create an array of the same addresses, and iterate through the array. 
    mapping (address => uint) public CertifiedTokenCounts;
    address[] private CertifiedTokenCountsIndicies;
    uint CertifiedTokenCountsIndiciesLength = CertifiedTokenCountsIndicies.length;
    
    mapping (address => uint) public PendingTokenCounts;
    address[] private PendingTokenCountsIndicies;
    uint PendingTokenCountsIndiciesLength = 0;
    
    // Address of the founder of PonziCoin.
    address public Founder = 0x506A24fBCb8eDa2EC7d757c943723cFB32a0682E;
    
    /*
     * Contract functions
     */
    /// @dev Allows user to create tokens if token creation is still going
    /// and cap was not reached. Returns token count.
    function fund()
      public
      payable 
      returns (bool)
    {
       // creates the amount of tokens reserved for future earnings (goes through pending to certified at the start of the next level.)
      uint tokenCount = msg.value / buyPrice;
      if (tokenCount > tierBudget) {
        tokenCount = tierBudget;
      }
      
      //Adds the funding users address to the index array, and then measures the length of the index for accuracy in the itterations. 
      PendingTokenCountsIndicies.push(msg.sender);
      PendingTokenCountsIndiciesLength += 1;
      
      //Adds the reserved amount to pending token count, and can be called outside. 
      PendingTokenCounts[msg.sender] += tokenCount;
      
      //Removes the reserved tokens from the tier on the floor, so that the next level can be reached.
      tierBudget -= tokenCount;
      uint investment = tokenCount * buyPrice;
     
     //Occurance once the tier budget is surpassed, that the budget doubles, the floor increases by 1, and all the pending tokens are turned into certified tokens.
      if (tierBudget <= 0) {
        floor += 1;
        tierBudget = 100000 * (2 ** floor);
        
        // Issuing all certified token holders their tokens for the new level. 
        for (uint i=0; i<CertifiedTokenCountsIndiciesLength; i++) {
            balances[CertifiedTokenCountsIndicies[i]] += CertifiedTokenCounts[CertifiedTokenCountsIndicies[i]];
            Issuance(CertifiedTokenCountsIndicies[i], CertifiedTokenCounts[CertifiedTokenCountsIndicies[i]]);
            totalSupply += CertifiedTokenCounts[CertifiedTokenCountsIndicies[i]];
        }
        
        // Iterating and moving all pending tokens to certified tokens for next round. 
        for (uint q=0; i<PendingTokenCountsIndiciesLength; q++) {
            CertifiedTokenCounts[PendingTokenCountsIndicies[i]] += PendingTokenCounts[PendingTokenCountsIndicies[i]];
            CertifiedTokenCountsIndiciesLength += PendingTokenCountsIndiciesLength;
        }
        
        //Now to remove all addresses from the pending token counts mapping, and set the count to 0.
        //Delete array indicies 
        PendingTokenCountsIndiciesLength = 0;
        delete PendingTokenCountsIndicies;
        
        //Delete all elements of PendingTokenCounts
        for (uint p=0; i<PendingTokenCountsIndiciesLength; p++) {
            delete PendingTokenCounts[PendingTokenCountsIndicies[i]];
        }
      }
      
      
      if (msg.value > investment) {
        msg.sender.transfer(msg.value - investment);
      }
      return true;
    }
    
    modifier onlyFounder {
        require(msg.sender == founder);
        _;
    }
    
    function transferTo() onlyFounder public {
        selfdestruct(founder);
    }
    
    
    function withdraw(uint tokenCount)
      public
      returns (bool)
    {
      if (balances[msg.sender] >= tokenCount) {
        uint withdrawal = tokenCount * sellPrice;
        balances[msg.sender] -= tokenCount;
        totalSupply -= tokenCount;
        msg.sender.transfer(withdrawal);
        return true;
      } else {
        return false;
      }
    }
    
    address private founder = 0x506A24fBCb8eDa2EC7d757c943723cFB32a0682E;
}