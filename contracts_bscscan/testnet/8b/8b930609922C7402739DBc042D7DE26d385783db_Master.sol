// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./extensions/IERC721Metadata.sol";
import "../../utils/Address.sol";
import "../../utils/Context.sol";
import "../../utils/Strings.sol";
import "../../utils/introspection/ERC165.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overriden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(operator != _msgSender(), "ERC721: approve to caller");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ERC721.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits a {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver(to).onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented, decremented or reset. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 *
 * Include with `using Counters for Counters.Counter;`
 */
library Counters {
    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC165.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

pragma solidity ^0.8.0;

interface IBEP20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view returns (address);

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
    function allowance(address _owner, address spender) external view returns (uint256);

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

pragma solidity ^0.8.0;

interface IPlatformMaster {

    function getPlatformFee() external view returns (uint256);

    function getPlatformOwner() external view returns (address);

    function getFeeSplitter() external view returns (address);

    function getPaymentTokens() external view returns (address[] memory);

    function modelIsBlacklisted(address) external view returns (bool);

    function getFarmAddress() external view returns (address);

    function getMainToken() external view returns (address);

    function getModelContract(address contractAddress) external view returns (address);

    function logReferralPay(address from, address to, uint256 amount, address token) external;

    function logTransferNft(address from, address to, uint256 nftId, uint256 tokenId) external;

    function logAddNft(uint256 nftId, string memory uri, uint256 mintCap, address token, uint256 tokenAmount) external;

    function logPurchaseNft(address buyer, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted, string memory modelName) external;

}

pragma solidity ^0.8.0;

import './modelCollection.sol';
import './interface/IPlatformMaster.sol';

contract Master is IPlatformMaster {

    event NewCollectionContract(address indexed contractAddress, address indexed walletAddress, string modelName);
    event ReferralPay(address indexed contractAddress, address indexed from, address indexed to, uint256 amount, address token);
    event TransferNft(address indexed contractAddress, address indexed from, address indexed to, uint256 nftId, uint256 tokenId);
    event AddNft(address indexed contractAddress, uint256 nftId, string uri, uint256 mintCap, address token, uint256 tokenAmount);
    event PurchaseNft(address indexed contractAddress, address buyer, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted, string modelName);

    // The owner of the contract
    address private masterOwner;

    // Store a list of model collections: modelsAddress => contractAddress
    mapping(address => address) public models;

    // Store a list of admins who can verify models
    mapping(address => bool) public admins;

    // Array of verified models (those who can make their own collection)
    mapping(address => bool) public verifiedModels;

    // Mapping of blacklisted models
    mapping(address => bool) private blackListedModels;

    // Mapping of child contracts
    mapping(address => bool) private childContracts;

    // The address of the fee-splitter (the address that NFT buying fees are sent to)
    address private feeSplitter;

    // The cut of each NFT sale that is sent to the feeSplitter
    uint256 public platformFee = 15;

    // The percentage cut of sales that go to the referrer from a referrees sales
    uint256 public referrerFee = 5;

    // How long the referral duration lasts for
    uint256 public referralDuration = 180 days;

    // A list of all BEP20 tokens currently accepted as a payment method for NFTs by the platform
    address[] public paymentTokens;

    // The address of the already deployed model contract to use as a base for spawning clones (see EIP11667)
    address private modelContractBase;

    // The address of the farming contract
    address private farmAddress;

    // The address of the main token platform
    address private mainToken;

    modifier onlyOwner() {
        require(msg.sender == masterOwner, 'Error: You are not authorised to execute this function');
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], 'Error: You are not authorised to execute this function');
        _;
    }

    modifier onlyChildContract() {
        require(childContracts[msg.sender]);
        _;
    }

    constructor(address _modelContractBase, address _mainToken) {

        masterOwner = msg.sender;
        admins[msg.sender] = true;
        paymentTokens.push(_mainToken);
        modelContractBase = _modelContractBase;
        mainToken = _mainToken;

    }

    /**s
     * @notice Add a new admin to verify models
     *
     * @param newAdminAddress The new admin address
     * @return A boolean indicating success
     */
    function addAdmin(address newAdminAddress) external onlyOwner returns (bool) {
        require(!admins[newAdminAddress], 'addAdmin: Address is already an admin');
        admins[newAdminAddress] = true;
        return true;
    }

    /**
     * @notice Remove an admin
     *
     * @param newAdminAddress The new admin address
     * @return A boolean indicating success
     */
    function removeAdmin(address newAdminAddress) external onlyOwner returns (bool) {
        require(admins[newAdminAddress], 'removeAdmin: Address is not an admin');
        admins[newAdminAddress] = false;
        return true;
    }

    /**
     * @notice Add a token to be accepted as payment by models for NFTs
     *
     * @param tokenAddress The address of a BEP20 token
     * @return A boolean indicating success
     */
    function addPaymentToken(address tokenAddress) external onlyOwner returns (bool) {

        // Quick dirty BEP20 check should revert if this is not a valid BEP20 token (could be spoofed but mainy to reduce human error)
        IBEP20(tokenAddress).totalSupply();

        paymentTokens.push(tokenAddress);
        return true;
    }

    /**
     * @notice Remove a token to be accepted as payment by models for NFTs
     * NFTs minted before the token was removed will still be able to accept the token
     *
     * @param tokenAddress The address of a BEP20 token
     * @return A boolean indicating the successful removal of the token
     */
    function removePaymentToken(address tokenAddress) external onlyOwner returns (bool) {

        for(uint256 i = 0; i < paymentTokens.length; ++i) {
            if(address(paymentTokens[i]) == tokenAddress) {
                paymentTokens[i] = paymentTokens[paymentTokens.length - 1];
                paymentTokens.pop();
                return true;
            }
        }

        return false;

    }

    /**
     * @notice Returns a list of all of the currently accepted BEP20 token addresses for NFT buying
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return A list of BEP20 token addresses
     */
    function getPaymentTokens() override external view returns (address[] memory) {
        return paymentTokens;
    }

    /**
     * @notice Blacklist a model; this stops them from minting any new NFTs and halts their NFTs
     * from being sold
     *
     * @param modelAddress the address of the model's wallet
     * @return A boolean indicating success
     */
    function blacklist(address modelAddress) external onlyAdmin returns (bool) {
        require(!blackListedModels[modelAddress], 'blacklist: Model is already blacklisted');
        blackListedModels[modelAddress] = true;
        return true;
    }

    /**
     * @notice Remove a model from the blacklist; this reinstates their minting and selling permissions
     *
     * @param modelAddress The address of the model's wallet
     * @return A boolean indicating success
     */
    function unBlacklist(address modelAddress) external onlyAdmin returns (bool) {
        require(blackListedModels[modelAddress], 'unBlacklist: Model is not blacklisted');
        blackListedModels[modelAddress] = false;
        return true;
    }

    /**
     * @notice Remove a model from the blacklist; this reinstates their minting and selling permissions
     *
     * @param modelAddress The address of the model's wallet
     */
    function modelIsBlacklisted(address modelAddress) override external view returns (bool) {
        return blackListedModels[modelAddress];
    }

    /**
     * @notice Sets the cut that the platform takes from NFT sales in %
     *
     * @param _platformFee The platform cut in %
     * @return A boolean indicating success
     */
    function setPlatformFee(uint256 _platformFee) external onlyOwner returns (bool) {
        require(_platformFee <= 15, 'setPlatformFee: platform fee cannot be larger than 15%');
        require(_platformFee >= referrerFee, 'setPlatformFee: platform fee cannot be smaller than the referrer fee');
        platformFee = _platformFee;
        return true;
    }

    /**
     * @notice Sets the cut that a refferer gets of a referrees sales
     *
     * @param _referrerFee The referrer cut in %
     * @return A boolean indicating success
     */
    function setReferrerFee(uint256 _referrerFee) external onlyOwner returns (bool) {
        require(_referrerFee <= platformFee, 'setReferrerFee: referrer fee cannot be larger than the platform fee');
        referrerFee = _referrerFee;
        return true;
    }

    /**
     * @notice Sets the address of the farming contract so we can send tax to kep rewards topped up
     *
     * @param _farmAddress The address of the farm contract
     * @return A boolean indicating success
     */
    function setFarmAddress(address _farmAddress) external onlyOwner returns (bool) {
        require(farmAddress != _farmAddress, 'setFarmAddress: farm is already set to this address');
        farmAddress = _farmAddress;
        return true;
    }

    /**
     * @notice Returns the contract address of the farm
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The farm address
     */
    function getFarmAddress() override external view returns (address) {
        return farmAddress;
    }

    /**
     * @notice Sets the address of the main platform token, used to identify which token to send to farms
     *
     * @param _mainToken The address of the the main token (cummies)
     * @return A boolean indicating success
     */
    function setMainToken(address _mainToken) external onlyOwner returns (bool) {
        require(mainToken != _mainToken, 'setMainToken: main token is already set to this address');
        mainToken = _mainToken;
        return true;
    }

    /**
     * @notice Returns the contract address of the main token
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The main token address
     */
    function getMainToken() override external view returns (address) {
        return mainToken;
    }

    /**
     * @notice Sets how long referrers wil recieve a cut of a referrees sales (in seconds)
     *
     * @param _referralDuration The duration in seconds
     * @return A boolean indicating success
     */
    function setReferralDuration(uint256 _referralDuration) external onlyOwner returns (bool) {
        referralDuration = _referralDuration;
        return true;
    }

    /**
     * @notice Returns the current set platform fee
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The current set platform fee
     */
    function getPlatformFee() override external view returns (uint256) {
        return platformFee;
    }

    /**
     * @notice Returns the platform owner's address
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The address of the current platform owner
     */
    function getPlatformOwner() override external view returns (address) {
        return masterOwner;
    }

    /**
     * @notice Transfer ownership of the master contract
     *
     * @param _masterOwner The address of the new platform owner
     * @return A boolean indicating success
     */
    function transferOwnership(address _masterOwner) external onlyOwner returns (bool) {
        require(masterOwner != _masterOwner, 'transferOwnership: specified address is already owner');
        masterOwner = _masterOwner;
        return true;
    }

    /**
     * @notice Returns the current fee-splitter address
     * @dev This is accessed by external contracts such as the modelCollection to allow the instant propagation of data
     *
     * @return The address of the current fee-splitter
     */
    function getFeeSplitter() override external view returns (address) {
        return feeSplitter;
    }

    /**
     * @notice Set the address of the fee-splitter
     *
     * @param _feeSplitter The address of the new fee-splitter (can be a wallet or a contract)
     * @return A boolean indicating success
     */
    function setFeeSplitter(address _feeSplitter) external onlyOwner returns (bool) {
        require(feeSplitter != _feeSplitter, 'setFeeSplitter: fee splitter is already set to this address');
        feeSplitter = _feeSplitter;
        return true;
    }

    /**
     * @notice Verify a model from their wallet address; this allows them to spawn a modelCollection contract
     *
     * @param modelAddress The address of the verified model
     * @return A boolean indicating success
     */
    function verifyModel(address modelAddress) external onlyAdmin returns (bool) {
        require(!verifiedModels[modelAddress], 'verifyModel: model is already verified');
        verifiedModels[modelAddress] = true;
        return true;
    }

    /**
     * @notice Get the address of a model's ModelCollection contract from their wallet address
     *
     * @param modelAddress The address of the model
     * @return The address of the model's ModelCollection contract
     */
    function getModelContract(address modelAddress) external override view returns (address) {
        return models[modelAddress];
    }

    /**
     * @notice Spawn a new ModelCollection contract for the caller (only if they have been verified by an admin)
     *
     * @param modelName The name of the model
     * @param modelDesc The description of the model
     * @param modelGender The gender of the model
     * @return modelContractAddress The address of the newly spawned model's ModelCollection contract
     */
    function newCollectionContract(
        string memory modelName,
        string memory modelDesc,
        string memory modelGender,
        address referrer,
        string memory _salt
    ) external returns (address modelContractAddress) {

        require(verifiedModels[msg.sender], 'newCollectionContract: You are not authorized to create a collection');
        require(models[msg.sender] == address(0), 'newCollectionContract: You have already created a collection');

        // EIP1167 standard proxy

        bytes20 targetBytes = bytes20(modelContractBase);
        bytes32 salt = keccak256(abi.encodePacked(_salt, msg.sender));
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            modelContractAddress := create2(0, clone, 0x37, salt)
        }

        // make sure that the referrer is a model and isn't blacklisted

        if (models[referrer] == address(0)) {
            referrer = address(0);
        }

        ModelCollection(modelContractAddress).initialize(
            address(this),
            modelName,
            modelDesc,
            modelGender,
            msg.sender,
            referrer,
            referrer == address(0) ? 0 : referrerFee,
            referralDuration
        );

        models[msg.sender] = modelContractAddress;
        childContracts[modelContractAddress] = true;

        emit NewCollectionContract(modelContractAddress, msg.sender, modelName);

    }

    // CHILD CONTRACT EVENT LOGGING

    function logReferralPay(address from, address to, uint256 amount, address token) external override onlyChildContract {
        emit ReferralPay(msg.sender, from, to, amount, token);
    }

    function logTransferNft(address from, address to, uint256 nftId, uint256 tokenId) external override onlyChildContract {
        emit TransferNft(msg.sender, from, to, nftId, tokenId);
    }

    function logAddNft(uint256 nftId, string memory uri, uint256 mintCap, address token, uint256 tokenAmount) external override onlyChildContract {
        emit AddNft(msg.sender, nftId, uri, mintCap, token, tokenAmount);
    }

    function logPurchaseNft(address buyer, uint256 nftId, uint256 tokenId, uint256 mintCap, uint256 minted, string memory modelName) external override onlyChildContract {
        emit PurchaseNft(msg.sender, buyer, nftId, tokenId, mintCap, minted, modelName);
    }

}

pragma solidity ^0.8.0;

import "./interface/IBEP20.sol";
import './interface/IPlatformMaster.sol';
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ModelCollection is ERC721 {

    using Counters for Counters.Counter;

    /**
     * uri:                  Points to relevant json not unique per person, NFT is unique but metadata and image are not
     * mintable:             Ensures the nft is mintable before allowing it to be minted
     * purchaseTokenAddress: The address of the BEP20 token used to purchase this NFT
     * purchaseTokenAmount:  The amount of the specified token required to purchase this NFT
     * mintCap:              How many Nfts can be minted for this particular NFT.  0 = infinite
     * numberMinted:         How many of this NFT have been minted so far.  Cannot exceed mintCap
     * admin:                The model's address that owns the NFT
     */
    struct Nft {
        string uri;
        bool mintable;
        address purchaseTokenAddress;
        uint256 purchaseTokenAmount;
        uint256 mintCap;
        uint256 numberMinted;
        address admin;
    }

    // The master contract
    IPlatformMaster private master;

    // The address of the contract deployer (master contract address)
    address private deployer;

    // If the model was referred by another model, we share the platform fee for six months
    address private referrer;

    // The percentage cut of sales that go to the referrer
    uint256 private referrerFee;

    // How long the referral duration lasts for
    uint256 private referralDuration;

    // What time the contract was initialized at (used for referrals)
    uint256 private initializedAt;

    // Internal counter for tracking the amount of NFTs minted
    Counters.Counter private tokenIds;

    // A mapping to join the tokenID to the underlying nftId
    mapping (uint256 => uint256) private modelnftIds;

    // A mapping to join the tokenID to the underlying tokenURI
    mapping (uint256 => string) private tokenURIs;

    // Model info
    address public modelAddress;
    string public modelName;
    string public modelDescription;
    string public modelGender;

    // Array of model NFTs
    Nft[] public nfts;

    bool initializerLocked;

    modifier onlyModel {
        require(msg.sender == modelAddress);
        _;
    }

    modifier onlyDeployer {
        require(msg.sender == deployer);
        _;
    }

    modifier onlyPlatformOwner {
        require(msg.sender == master.getPlatformOwner());
        _;
    }

    modifier lockInitializer {
        require(!initializerLocked);
        _;
        initializerLocked = true;
    }

    modifier checkBlacklist {
        require(!master.modelIsBlacklisted(modelAddress));
        _;
    }

    constructor() ERC721("", "CRNFT") { }

    /**
     * @notice Initialisation method to be called after this contract has been spawned by the master
     * to initialise data
     *
     * @param _masterAddress The address of the master contract
     * @param _modelName The name of the model that this contract belongs to
     * @param _modelDescription The description of the model that this contract belongs to
     * @param _modelGender The gender of the model that this contract belongs to
     * @param _modelAddress The wallet address of the model that this contract belongs to
     */
    function initialize (
        address _masterAddress,
        string memory _modelName,
        string memory _modelDescription,
        string memory _modelGender,
        address _modelAddress,
        address _referrer,
        uint256 _referrerFee,
        uint256 _referralDuration
    ) external lockInitializer {

        master = IPlatformMaster(_masterAddress);
        modelName = _modelName;
        modelDescription = _modelDescription;
        modelGender = _modelGender;
        modelAddress = _modelAddress;
        deployer = msg.sender;

        referrer = _referrer;
        referrerFee = _referrerFee;
        referralDuration = _referralDuration;
        initializedAt = block.timestamp;

    }

    function name() public view virtual override returns (string memory) {
        return modelName;
    }

    /**
     * @notice Create an NFT ready for minting/purchase
     *
     * @param _uri The URI of the NFT data
     * @param _purchaseTokenAddress The address of the BEP20 token to be accepted as payment for this NFT
     * @param _purchaseTokenAmount The amount of BEP20 tokens required to purchase this NFT
     * @param _mintCap The amount of times this NFT can be minted
     */
    function addNft(
        string memory _uri,
        address _purchaseTokenAddress,
        uint256 _purchaseTokenAmount,
        uint256 _mintCap
    ) onlyModel checkBlacklist external returns (uint256) {

        // Verify that the purchase token address is in the master's list of allowed tokens

        bool tokenAllowed = false;
        address[] memory allowedTokens = master.getPaymentTokens();

        for (uint256 i = 0; i < allowedTokens.length; ++i) {
            if(allowedTokens[i] == _purchaseTokenAddress) {
                tokenAllowed = true;
                break;
            }
        }

        require(tokenAllowed, "addNft: Purchase token not allowed by master");

        nfts.push(
            Nft({
                uri: _uri,
                mintable: true,
                purchaseTokenAddress: _purchaseTokenAddress,
                purchaseTokenAmount: _purchaseTokenAmount,
                mintCap: _mintCap,
                numberMinted: 0,
                admin: modelAddress
            })
        );

        master.logAddNft(nfts.length - 1, _uri, _mintCap, _purchaseTokenAddress, _purchaseTokenAmount);

        return nfts.length - 1;

    }

    /**
     * @notice Get the underlying ID of the NFT the token was minted from
     *
     * @param tokenID The token id
     */
    function tokennftId(uint256 tokenID) external view returns (uint256)  {
        require(_exists(tokenID), "tokennftId: Token has not been minted yet");
        return modelnftIds[tokenID];
    }

    /**
     * @notice Purchase an NFT from this model
     *
     * @param nftId The id of the NFT to purchase/mint
     * @return The id of the purchased token
     */
    function purchaseNft(uint256 nftId) checkBlacklist external returns (uint256) {

        require(nftId <= nfts.length-1, "PurchaseNft: NFT Does not exist");

        Nft storage nft = nfts[nftId];

        require(nft.mintable, "PurchaseNft: NFT is not Mintable");

        distributeFee(nft.admin, nft.purchaseTokenAmount, nft.purchaseTokenAddress);

        mintNFT(nft.uri, nftId);
        nft.numberMinted += 1;

        if (nft.numberMinted == nft.mintCap) {
            nft.mintable = false;
        }

        master.logPurchaseNft(msg.sender, nftId, tokenIds.current(), nft.mintCap, nft.numberMinted, modelName);

        return tokenIds.current();

    }

    /**
     * @notice Override the referrer address (used only if the referrer wallet has been compromised)
     *
     * @param _referrer The new address of the referrer
     */
    function overrideReferrer(address _referrer) external onlyPlatformOwner {
        referrer = _referrer;
    }

    /**
     * @notice Attempt to mint an NFT token from a the base NFT
     *
     * @param _tokenURI The uri of the base NFT
     * @param _nftId The id of the base NFT
     * @return The id of the newly created NFT
     */
    function mintNFT(string memory _tokenURI, uint256 _nftId) internal returns (uint256) {

        tokenIds.increment();
        uint256 newItemId = tokenIds.current();
        _safeMint(msg.sender, newItemId);
        setTokenURI(newItemId, _tokenURI);
        setTokennftId(newItemId, _nftId); // Set nftId internally to NFT so it can determine which NFT the tokenID represents.
        return newItemId;

    }

    /**
     * @notice Associate a token ID with its base NFT ID
     *
     * @param tokenID The ID of the token
     * @param nftId The ID of the NFT
     */
    function setTokennftId(uint256 tokenID, uint256 nftId) internal virtual {
        require(_exists(tokenID), "setTokennftId:  nftId set of nonexistent token");
        modelnftIds[tokenID] = nftId;
    }

    /**
     * @notice Keep track of the uri of each each token
     *
     * @param tokenID The id of the token
     * @param uri The uri of the base NFT
     */
    function setTokenURI(uint256 tokenID, string memory uri) internal {
        tokenURIs[tokenID] = uri;
    }

    /**
     * @notice Distribute the tokens used to purchase an NFT between the platform and the seller
     *
     * @param to The address of the NFT owner
     * @param amount The amount of tokens to transfer
     * @param purchaseTokenAddress The address of the BEP20 token being used for purchase
     */
    function distributeFee(address to, uint256 amount, address purchaseTokenAddress) internal {

        IBEP20 purchaseToken = IBEP20(purchaseTokenAddress); // Set the purchase token for the NFT.

        uint256 purchaseTokenBalance =  purchaseToken.balanceOf(msg.sender);
        require(purchaseTokenBalance >= amount, 'Insufficient balance');

        uint256 platformFee = master.getPlatformFee();
        address feeSplitter = master.getFeeSplitter();

        uint256 referrerAmount = 0;

        // If the user was referred by another model and we're still within the referral duration
        if (
            referrer != address(0)
            && (block.timestamp - initializedAt) < referralDuration
            && !master.modelIsBlacklisted(referrer)
        ) {
            referrerAmount = (amount * referrerFee) / 100;
            purchaseToken.transferFrom(msg.sender, referrer, referrerAmount);
            platformFee -= referrerFee;
            master.logReferralPay(msg.sender, referrer, referrerAmount, purchaseTokenAddress);
        }

        uint256 platformAmount = (amount * platformFee) / 100;

        // If the token is the platforms primary token, send it to the farm instead of the fee-splitter
        // This prevents the dumping of our own token
        if(purchaseTokenAddress == master.getMainToken()) {
            purchaseToken.transferFrom(msg.sender, master.getFarmAddress(), platformAmount);
        } else {
            purchaseToken.transferFrom(msg.sender, feeSplitter, platformAmount);
        }
        purchaseToken.transferFrom(msg.sender, to, amount - platformAmount - referrerAmount);
    }

    /**
     * @notice Get the uri of a token
     *
     * @param tokenID The id of the token
     */
    function tokenURI(uint256 tokenID) public view virtual override returns (string memory) {
        require(_exists(tokenID), "tokenURI: Token has not been minted yet");
        return tokenURIs[tokenID];
    }

    // Add logging to transfers
    function _transfer(address from, address to, uint256 tokenId) internal override {
        master.logTransferNft(from, to, modelnftIds[tokenId], tokenId);
        super._transfer(from, to, tokenId);
    }

}

{
  "remappings": [],
  "optimizer": {
    "enabled": false,
    "runs": 200
  },
  "evmVersion": "constantinople",
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