pragma solidity ^0.6.0;

import "./interfaces/IHasBlackListERC20Token.sol";
import "./interfaces/ISpender.sol";

contract SpenderSimulation {
    ISpender public immutable spender;

    mapping(address => bool) public hasBlackListERC20Tokens;

    modifier checkBlackList(address _tokenAddr, address _user) {
        if (hasBlackListERC20Tokens[_tokenAddr]) {
            IHasBlackListERC20Token hasBlackListERC20Token = IHasBlackListERC20Token(_tokenAddr);
            require(!hasBlackListERC20Token.isBlackListed(_user), "SpenderSimulation: user in token's blacklist");
        }
        _;
    }

    /************************************************************
    *                       Constructor                         *
    *************************************************************/
    constructor (ISpender _spender, address[] memory _hasBlackListERC20Tokens) public {
        spender = _spender;

        for (uint256 i = 0; i < _hasBlackListERC20Tokens.length; i++) {
            hasBlackListERC20Tokens[_hasBlackListERC20Tokens[i]] = true;
        }
    }

    /************************************************************
    *                    Helper functions                       *
    *************************************************************/
    /// @dev Spend tokens on user's behalf but reverts if succeed.
    /// This is only intended to be run off-chain to check if the transfer will succeed.
    /// @param _user The user to spend token from.
    /// @param _tokenAddr The address of the token.
    /// @param _amount Amount to spend.
    function simulate(address _user, address _tokenAddr, uint256 _amount) external checkBlackList(_tokenAddr, _user) {
        spender.spendFromUser(_user, _tokenAddr, _amount);

        // All checks passed: revert with success reason string
        revert("SpenderSimulation: transfer simulation success");
    }
}

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHasBlackListERC20Token is IERC20 {
    function isBlackListed(address user) external returns (bool);
    function addBlackList(address user) external;
    function removeBlackList(address user) external;
}

pragma solidity ^0.6.0;

interface ISpender {
    function spendFromUser(address _user, address _tokenAddr, uint256 _amount) external;
    function spendFromUserTo(address _user, address _tokenAddr, address _receiverAddr, uint256 _amount) external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
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

{
  "optimizer": {
    "enabled": true,
    "runs": 1000
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  },
  "metadata": {
    "useLiteralContent": true
  },
  "libraries": {}
}