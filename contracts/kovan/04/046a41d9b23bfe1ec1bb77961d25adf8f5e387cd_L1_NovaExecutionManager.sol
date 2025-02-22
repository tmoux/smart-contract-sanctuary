// @unsupported: ovm
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@eth-optimism/contracts/libraries/bridge/OVM_CrossDomainEnabled.sol";

import "./L2_NovaRegistry.sol";
import "./external/DSAuth.sol";
import "./libraries/NovaExecHashLib.sol";
import "./libraries/SigLib.sol";

contract L1_NovaExecutionManager is DSAuth, OVM_CrossDomainEnabled {
    /*///////////////////////////////////////////////////////////////
                            HARD REVERT CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The revert message text used to cause a hard revert.
    string public constant HARD_REVERT_TEXT = "__NOVA__HARD__REVERT__";
    /// @dev The hash of the hard revert message.
    bytes32 internal constant HARD_REVERT_HASH = keccak256(abi.encodeWithSignature("Error(string)", HARD_REVERT_TEXT));

    /*///////////////////////////////////////////////////////////////
                          GAS ESTIMATION CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The base cost of creating an Ethereum transaction.
    uint256 public constant BASE_TRANSACTION_GAS = 21_000;

    /// @notice The amount of gas to assume for each byte of calldata.
    uint256 public constant AVERAGE_GAS_PER_CALLDATA_BYTE = 10;

    /// @notice The amount of gas to assume the execCompleted message consumes.
    uint256 public constant EXEC_COMPLETED_MESSAGE_GAS = 111500;

    /*///////////////////////////////////////////////////////////////
                       CROSS DOMAIN MESSAGE CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The xDomainGasLimit to use for the call to execCompleted.
    uint32 public constant EXEC_COMPLETED_MESSAGE_GAS_LIMIT = 1_000_000;

    /*///////////////////////////////////////////////////////////////
                             REGISTRY ADDRESS
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the L2_NovaRegistry to send cross domain messages to.
    address public immutable L2_NovaRegistryAddress;

    /// @param _L2_NovaRegistryAddress The address of the L2_NovaRegistry to send cross domain messages to.
    /// @param _messenger The L1 xDomainMessenger contract to use for sending cross domain messages.
    constructor(address _L2_NovaRegistryAddress, address _messenger) OVM_CrossDomainEnabled(_messenger) {
        L2_NovaRegistryAddress = _L2_NovaRegistryAddress;
    }

    /*///////////////////////////////////////////////////////////////
                                  EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when `exec` is called.
    /// @param execHash The execHash computed from arguments and transaction context.
    /// @param reverted Will be true if the strategy call reverted, will be false if not.
    /// @param gasUsed The gas estimate computed during the call.
    event Exec(bytes32 indexed execHash, address relayer, bool reverted, uint256 gasUsed);

    /*///////////////////////////////////////////////////////////////
                       EXECUTION CONTEXT CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The 'default' value for `currentExecHash`.
    /// @notice Outside of an active `exec` call `currentExecHash` will always equal DEFAULT_EXECHASH.
    bytes32 public constant DEFAULT_EXECHASH = 0xFEEDFACECAFEBEEFFEEDFACECAFEBEEFFEEDFACECAFEBEEFFEEDFACECAFEBEEF;

    /*///////////////////////////////////////////////////////////////
                        EXECUTION CONTEXT STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The execHash computed from the currently executing call to `exec`.
    /// @notice This will be reset to DEFAULT_EXECHASH after each execution completes.
    bytes32 public currentExecHash = DEFAULT_EXECHASH;
    /// @notice The address who called `exec`.
    /// @notice This will not be reset after each execution completes.
    address public currentRelayer;
    /// @dev The address of the strategy that is currently being called.
    /// @dev This will not be reset after each execution completes.
    address internal currentlyExecutingStrategy;

    /*///////////////////////////////////////////////////////////////
                           STATEFUL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes a request and sends tip/inputs to a specific address.
    /// @param nonce The nonce of the request.
    /// @param strategy The strategy requested in the request.
    /// @param l1Calldata The calldata associated with the request.
    /// @param l2Recipient The address of the account on L2 to receive the tip/inputs.
    /// @param deadline Timestamp after which the transaction will revert.
    function exec(
        uint256 nonce,
        address strategy,
        bytes calldata l1Calldata,
        address l2Recipient,
        uint256 deadline
    ) external {
        // Measure gas left at the start of execution.
        uint256 startGas = gasleft();

        // Check that the deadline has not already passed.
        require(block.timestamp <= deadline, "PAST_DEADLINE");

        // This prevents the strategy from performing a reentrancy attack.
        require(currentExecHash == DEFAULT_EXECHASH, "ALREADY_EXECUTING");

        // Check authorization of the caller (equivalent to DSAuth's `auth` modifier).
        require(isAuthorized(msg.sender, msg.sig), "ds-auth-unauthorized");

        // We cannot allow providing address(0) for l2Recipient, as the registry
        // uses address(0) to indicate a request has not had its tokens removed yet.
        require(l2Recipient != address(0), "NEED_RECIPIENT");

        // We cannot allow calling the execution manager itself, as a malicious
        // relayer could call DSAuth and OVM_CrossDomainEnabled inherited functions
        // to change owners, blacklist relayers, and send cross domain messages at will.
        require(strategy != address(this), "UNSAFE_STRATEGY");

        // Extract the 4 byte function signature from l1Calldata.
        bytes4 calldataSig = SigLib.fromCalldata(l1Calldata);

        // We canot allow calling IERC20.transferFrom directly, as a malicious
        // relayer could steal tokens approved to the registry by other relayers.
        require(calldataSig != IERC20.transferFrom.selector, "UNSAFE_CALLDATA");

        // We cannot allow calling iAbs_BaseCrossDomainMessenger.sendMessage directly,
        // as a malicious relayer could use it to trigger the registry's execCompleted
        // function and claim bounties without actually executing the proper request(s).
        require(calldataSig != iOVM_CrossDomainMessenger.sendMessage.selector, "UNSAFE_CALLDATA");

        // Compute the execHash.
        bytes32 execHash =
            NovaExecHashLib.compute({nonce: nonce, strategy: strategy, l1Calldata: l1Calldata, gasPrice: tx.gasprice});

        // Initialize execution context.
        currentExecHash = execHash;
        currentRelayer = msg.sender;
        currentlyExecutingStrategy = strategy;

        // Call the strategy.
        (bool success, bytes memory returnData) = strategy.call(l1Calldata);

        // Revert if the strategy hard reverted.
        require(success || keccak256(returnData) != HARD_REVERT_HASH, "HARD_REVERT");

        // Reset currentExecHash to default so `transferFromRelayer` becomes uncallable again.
        currentExecHash = DEFAULT_EXECHASH;

        // Estimate how much gas the relayer will have paid (not accounting for refunds):
        uint256 gasUsedEstimate =
            BASE_TRANSACTION_GAS + /* Base gas cost of an Etheruem transaction */
                (msg.data.length * AVERAGE_GAS_PER_CALLDATA_BYTE) + /* Calldata cost estimate */
                (startGas - gasleft()) + /* Gas used so far */
                EXEC_COMPLETED_MESSAGE_GAS; /* sendCrossDomainMessage cost */

        // Send message to unlock the bounty on L2.
        sendCrossDomainMessage(
            L2_NovaRegistryAddress,
            EXEC_COMPLETED_MESSAGE_GAS_LIMIT,
            abi.encodeWithSelector(
                L2_NovaRegistry(L2_NovaRegistryAddress).execCompleted.selector,
                // Computed execHash:
                execHash,
                // The reward recipient on L2:
                l2Recipient,
                // Did the call revert:
                !success,
                // Estimated gas used in total:
                gasUsedEstimate
            )
        );

        emit Exec(execHash, msg.sender, !success, gasUsedEstimate);
    }

    /// @notice Transfers tokens from the relayer (the account that called execute) has approved to the execution manager for the currently executing strategy.
    /// @notice Can only be called by the currently executing strategy (if there is one at all).
    /// @notice Will trigger a hard revert if the correct amount of tokens are not approved when called.
    /// @param token The ER20-compliant token to transfer to the currently executing strategy.
    /// @param amount The amount of `token` (scaled by its decimals) to transfer to the currently executing strategy.
    function transferFromRelayer(address token, uint256 amount) external auth {
        // Only the currently executing strategy is allowed to call this function.
        require(msg.sender == currentlyExecutingStrategy, "NOT_CURRENT_STRATEGY");

        // Ensure currentExecHash is not set to DEFAULT_EXECHASH as otherwise
        // a strategy could call this function outside of an active execution.
        require(currentExecHash != DEFAULT_EXECHASH, "NO_ACTIVE_EXECUTION");

        // Transfer the token from the relayer the currently executing strategy (msg.sender is enforced to be the currentlyExecutingStrategy above).
        (bool success, bytes memory returndata) =
            address(token).call(
                // Encode a call to transferFrom.
                abi.encodeWithSelector(IERC20(token).transferFrom.selector, currentRelayer, msg.sender, amount)
            );

        // Hard revert if the transferFrom call reverted.
        require(success, HARD_REVERT_TEXT);

        // If it returned something, hard revert if it is not a positive bool.
        if (returndata.length > 0) {
            if (returndata.length == 32) {
                // It returned a bool, hard revert if it is not a positive bool.
                require(abi.decode(returndata, (bool)), HARD_REVERT_TEXT);
            } else {
                // It returned some data that was not a bool, let's hard revert.
                revert(HARD_REVERT_TEXT);
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                            PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Convience function that triggers a hard revert.
    function hardRevert() external pure {
        // Call revert with the hard revert text.
        revert(HARD_REVERT_TEXT);
    }
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

// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;

/* Interface Imports */
import { iOVM_CrossDomainMessenger } from
    "../../iOVM/bridge/messaging/iOVM_CrossDomainMessenger.sol";

/**
 * @title OVM_CrossDomainEnabled
 * @dev Helper contract for contracts performing cross-domain communications
 *
 * Compiler used: defined by inheriting contract
 * Runtime target: defined by inheriting contract
 */
contract OVM_CrossDomainEnabled {

    /*************
     * Variables *
     *************/

    // Messenger contract used to send and recieve messages from the other domain.
    address public messenger;


    /***************
     * Constructor *
     ***************/

    /**
     * @param _messenger Address of the CrossDomainMessenger on the current layer.
     */
    constructor(
        address _messenger
    ) {
        messenger = _messenger;
    }


    /**********************
     * Function Modifiers *
     **********************/

    /**
     * Enforces that the modified function is only callable by a specific cross-domain account.
     * @param _sourceDomainAccount The only account on the originating domain which is
     *  authenticated to call this function.
     */
    modifier onlyFromCrossDomainAccount(
        address _sourceDomainAccount
    ) {
        require(
            msg.sender == address(getCrossDomainMessenger()),
            "OVM_XCHAIN: messenger contract unauthenticated"
        );

        require(
            getCrossDomainMessenger().xDomainMessageSender() == _sourceDomainAccount,
            "OVM_XCHAIN: wrong sender of cross-domain message"
        );

        _;
    }


    /**********************
     * Internal Functions *
     **********************/

    /**
     * Gets the messenger, usually from storage. This function is exposed in case a child contract
     * needs to override.
     * @return The address of the cross-domain messenger contract which should be used.
     */
    function getCrossDomainMessenger()
        internal
        virtual
        returns (
            iOVM_CrossDomainMessenger
        )
    {
        return iOVM_CrossDomainMessenger(messenger);
    }

    /**
     * Sends a message to an account on another domain
     * @param _crossDomainTarget The intended recipient on the destination domain
     * @param _message The data to send to the target (usually calldata to a function with
     *  `onlyFromCrossDomainAccount()`)
     * @param _gasLimit The gasLimit for the receipt of the message on the target domain.
     */
    function sendCrossDomainMessage(
        address _crossDomainTarget,
        uint32 _gasLimit,
        bytes memory _message
    )
        internal
    {
        getCrossDomainMessenger().sendMessage(_crossDomainTarget, _message, _gasLimit);
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@eth-optimism/contracts/libraries/bridge/OVM_CrossDomainEnabled.sol";

import "./external/DSAuth.sol";

import "./libraries/NovaExecHashLib.sol";

contract L2_NovaRegistry is DSAuth, OVM_CrossDomainEnabled, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /*///////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The minimum delay between when `unlockTokens` and `withdrawTokens` can be called.
    uint256 public constant MIN_UNLOCK_DELAY_SECONDS = 300;

    /// @notice The maximum amount of input tokens that may be added to a request.
    uint256 public constant MAX_INPUT_TOKENS = 5;

    /// @notice The ERC20 ETH users must use to pay for the L1 gas usage of request.
    IERC20 public immutable ETH;

    /// @param _ETH The ERC20 ETH users must use to pay for the L1 gas usage of request.
    /// @param _messenger The L2 xDomainMessenger contract to trust for receiving messages.
    constructor(address _ETH, address _messenger) OVM_CrossDomainEnabled(_messenger) {
        ETH = IERC20(_ETH);
    }

    /*///////////////////////////////////////////////////////////////
                    EXECUTION MANAGER ADDRESS STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the only contract authorized to make cross domain calls to `execCompleted`.
    address public L1_NovaExecutionManagerAddress;

    /// @notice Authorizes the `_L1_NovaExecutionManagerAddress` to make cross domain calls to `execCompleted`.
    /// @notice Each call to `connectExecutionManager` overrides the previous value, you cannot have multiple authorized execution managers at once.
    /// @param _L1_NovaExecutionManagerAddress The address to be authorized to make cross domain calls to `execCompleted`.
    function connectExecutionManager(address _L1_NovaExecutionManagerAddress) external auth {
        L1_NovaExecutionManagerAddress = _L1_NovaExecutionManagerAddress;

        emit ConnectExecutionManager(_L1_NovaExecutionManagerAddress);
    }

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when `connectExecutionManager` is called.
    event ConnectExecutionManager(address _L1_NovaExecutionManagerAddress);

    /// @notice Emitted when `requestExec` is called.
    /// @param execHash The unique identifier generated for this request.
    /// @param strategy The address of the "strategy" contract on L1 a relayer should call with `calldata`.
    event RequestExec(bytes32 indexed execHash, address indexed strategy);

    /// @notice Emitted when `execCompleted` is called.
    /// @param execHash The unique identifier associated with the request executed.
    /// @param rewardRecipient The address the relayer specified to be the recipient of the tokens on L2.
    /// @param reverted If the strategy reverted on L1 during execution.
    /// @param gasUsed The amount of gas used by the execution tx on L1.
    event ExecCompleted(bytes32 indexed execHash, address indexed rewardRecipient, bool reverted, uint256 gasUsed);

    /// @notice Emitted when `claimInputTokens` is called.
    /// @param execHash The unique identifier associated with the request that had its input tokens claimed.
    event ClaimInputTokens(bytes32 indexed execHash);

    /// @notice Emitted when `withdrawTokens` is called.
    /// @param execHash The unique identifier associated with the request that had its tokens withdrawn.
    event WithdrawTokens(bytes32 indexed execHash);

    /// @notice Emitted when `unlockTokens` is called.
    /// @param execHash The unique identifier associated with the request that had a token unlock scheduled.
    /// @param unlockTimestamp When the unlock will set into effect and the creator will be able to call `withdrawTokens`.
    event UnlockTokens(bytes32 indexed execHash, uint256 unlockTimestamp);

    /// @notice Emitted when `relockTokens` is called.
    /// @param execHash The unique identifier associated with the request that had its tokens relocked.
    event RelockTokens(bytes32 indexed execHash);

    /// @notice Emitted when `speedUpRequest` is called.
    /// @param execHash The unique identifier associated with the request that was uncled and replaced by the newExecHash.
    /// @param newExecHash The execHash of the resubmitted request (copy of its uncle with an updated gasPrice).
    /// @param newNonce The nonce of the resubmitted request.
    /// @param switchTimestamp When the uncled request (`execHash`) will have its tokens transferred to the resubmitted request (`newExecHash`).
    event SpeedUpRequest(
        bytes32 indexed execHash,
        bytes32 indexed newExecHash,
        uint256 newNonce,
        uint256 switchTimestamp
    );

    /*///////////////////////////////////////////////////////////////
                       GLOBAL NONCE COUNTER STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The most recent nonce assigned to an execution request.
    uint256 public systemNonce;

    /*///////////////////////////////////////////////////////////////
                           PER REQUEST STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps execHashes to the creator of each request.
    mapping(bytes32 => address) public getRequestCreator;
    /// @notice Maps execHashes to the address of the strategy associated with the request.
    mapping(bytes32 => address) public getRequestStrategy;
    /// @notice Maps execHashes to the calldata associated with the request.
    mapping(bytes32 => bytes) public getRequestCalldata;
    /// @notice Maps execHashes to the gas limit a relayer should use to execute the request.
    mapping(bytes32 => uint256) public getRequestGasLimit;
    /// @notice Maps execHashes to the gas price a relayer must use to execute the request.
    mapping(bytes32 => uint256) public getRequestGasPrice;
    /// @notice Maps execHashes to the additional tip in wei relayers will receive for executing them.
    mapping(bytes32 => uint256) public getRequestTip;
    /// @notice Maps execHashes to the nonce of each request.
    /// @notice This is just for convenience, does not need to be on-chain.
    mapping(bytes32 => uint256) public getRequestNonce;

    /// @notice A token/amount pair that a relayer will need on L1 to execute the request (and will be returned to them on L2).
    /// @param l2Token The token on L2 to transfer to the relayer upon a successful execution.
    /// @param amount The amount of the `l2Token` to the relayer upon a successful execution (scaled by the `l2Token`'s decimals).
    /// @dev Relayers may have to reference a registry/list of some sort to determine the equivalent L1 token they will need.
    /// @dev The decimal scheme may not align between the L1 and L2 tokens, a relayer should check via off-chain logic.
    struct InputToken {
        IERC20 l2Token;
        uint256 amount;
    }

    /// @notice Maps execHashes to the input tokens a relayer must have to execute the request.
    mapping(bytes32 => InputToken[]) public requestInputTokens;

    function getRequestInputTokens(bytes32 execHash) external view returns (InputToken[] memory) {
        return requestInputTokens[execHash];
    }

    /*///////////////////////////////////////////////////////////////
                       INPUT TOKEN RECIPIENT STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct containing data about the status of the request's input tokens.
    /// @param recipient The user who is entitled to take the request's input tokens.
    /// If recipient is not address(0), this means the request is no longer executable.
    /// @param isClaimed Will be true if the input tokens have been removed, false if not.
    struct InputTokenRecipientData {
        address recipient;
        bool isClaimed;
    }

    /// @notice Maps execHashes to a struct which contains data about the status of the request's input tokens.
    mapping(bytes32 => InputTokenRecipientData) public getRequestInputTokenRecipientData;

    /*///////////////////////////////////////////////////////////////
                              UNLOCK STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps execHashes to a timestamp representing when the request will have its tokens unlocked, meaning the creator can withdraw their bounties/inputs.
    /// @notice Will be 0 if no unlock has been scheduled.
    mapping(bytes32 => uint256) public getRequestUnlockTimestamp;

    /*///////////////////////////////////////////////////////////////
                              UNCLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps execHashes which represent resubmitted requests (via speedUpRequest) to their corresponding "uncled" request's execHash.
    /// @notice An uncled request is a request that has had its tokens removed via `speedUpRequest` in favor of a resubmitted request generated in the transaction.
    /// @notice Will be bytes32("") if `speedUpRequest` has not been called with the `execHash`.
    mapping(bytes32 => bytes32) public getRequestUncle;

    /// @notice Maps execHashes to a timestamp representing when the request will be disabled and replaced by a re-submitted request with a higher gas price (via `speedUpRequest`).
    /// @notice Will be 0 if `speedUpRequest` has not been called with the `execHash`.
    mapping(bytes32 => uint256) public getRequestDeathTimestamp;

    /*///////////////////////////////////////////////////////////////
                           STATEFUL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Request `strategy` to be executed with `l1Calldata`.
    /// @notice The caller must approve `(gasPrice * gasLimit) + tip` of `ETH` before calling.
    /// @param strategy The address of the "strategy" contract on L1 a relayer should call with `calldata`.
    /// @param l1Calldata The abi encoded calldata a relayer should call the `strategy` with on L1.
    /// @param gasLimit The gas limit a relayer should use on L1.
    /// @param gasPrice The gas price (in wei) a relayer should use on L1.
    /// @param tip The additional wei to pay as a tip for any relayer that executes this request.
    /// @param inputTokens An array of MAX_INPUT_TOKENS or less token/amount pairs that a relayer will need on L1 to execute the request (and will be returned to them on L2).
    /// @return execHash The "execHash" (unique identifier) for this request.
    function requestExec(
        address strategy,
        bytes calldata l1Calldata,
        uint256 gasLimit,
        uint256 gasPrice,
        uint256 tip,
        InputToken[] calldata inputTokens
    ) public nonReentrant auth returns (bytes32 execHash) {
        // Do not allow more than MAX_INPUT_TOKENS input tokens.
        require(inputTokens.length <= MAX_INPUT_TOKENS, "TOO_MANY_INPUTS");

        // Increment global nonce.
        systemNonce += 1;
        // Compute execHash for this request.
        execHash = NovaExecHashLib.compute({
            nonce: systemNonce,
            strategy: strategy,
            l1Calldata: l1Calldata,
            gasPrice: gasPrice
        });

        // Store all critical request data.
        getRequestCreator[execHash] = msg.sender;
        getRequestStrategy[execHash] = strategy;
        getRequestCalldata[execHash] = l1Calldata;
        getRequestGasLimit[execHash] = gasLimit;
        getRequestGasPrice[execHash] = gasPrice;
        getRequestTip[execHash] = tip;
        // Storing the nonce is just for convenience; it does not need to be on-chain.
        getRequestNonce[execHash] = systemNonce;

        emit RequestExec(execHash, strategy);

        // Transfer in ETH to pay for max gas usage + tip.
        ETH.safeTransferFrom(msg.sender, address(this), gasLimit.mul(gasPrice).add(tip));

        // Transfer input tokens in that the msg.sender has approved.
        for (uint256 i = 0; i < inputTokens.length; i++) {
            inputTokens[i].l2Token.safeTransferFrom(msg.sender, address(this), inputTokens[i].amount);

            // Copy over this index to the requestInputTokens mapping (we can't just put a calldata/memory array directly into storage so we have to go index by index).
            requestInputTokens[execHash].push(inputTokens[i]);
        }
    }

    /// @notice Calls `requestExec` with all relevant parameters along with calling `unlockTokens` with the `autoUnlockDelay` argument.
    /// @dev See `requestExec` and `unlockTokens` for more information.
    function requestExecWithTimeout(
        address strategy,
        bytes calldata l1Calldata,
        uint256 gasLimit,
        uint256 gasPrice,
        uint256 tip,
        InputToken[] calldata inputTokens,
        uint256 autoUnlockDelaySeconds
    ) external returns (bytes32 execHash) {
        // Create a request and get its execHash.
        execHash = requestExec(strategy, l1Calldata, gasLimit, gasPrice, tip, inputTokens);

        // Schedule an unlock set to complete autoUnlockDelay seconds from now.
        unlockTokens(execHash, autoUnlockDelaySeconds);
    }

    /// @notice Claims input tokens earned from executing a request.
    /// @notice Request creators must also call this function if their request reverted (as input tokens are not sent to relayers if the request reverts).
    /// @notice Anyone may call this function, but the tokens will be sent to the proper input token recipient
    /// (either the l2Recpient given in `execCompleted` or the request creator if the request reverted).
    /// @param execHash The hash of the executed request.
    function claimInputTokens(bytes32 execHash) external nonReentrant auth {
        // Get a pointer to the input token recipient data.
        InputTokenRecipientData storage inputTokenRecipientData = getRequestInputTokenRecipientData[execHash];

        // Ensure input tokens for this request are ready to be sent to a recipient.
        require(inputTokenRecipientData.recipient != address(0), "NO_RECIPIENT");
        // Ensure that the tokens have not already been claimed.
        require(!inputTokenRecipientData.isClaimed, "ALREADY_CLAIMED");

        // Mark the input tokens as claimed.
        inputTokenRecipientData.isClaimed = true;

        emit ClaimInputTokens(execHash);

        // Loop over each input token to transfer it to the recipient.
        InputToken[] memory inputTokens = requestInputTokens[execHash];
        for (uint256 i = 0; i < inputTokens.length; i++) {
            inputTokens[i].l2Token.safeTransfer(inputTokenRecipientData.recipient, inputTokens[i].amount);
        }
    }

    /// @notice Unlocks a request's tokens with a delay. Once the delay has passed, anyone may call `withdrawTokens` on behalf of the creator to send the bounties/input tokens back.
    /// @notice msg.sender must be the creator of the request associated with the `execHash`.
    /// @param execHash The unique hash of the request to unlock.
    /// @param unlockDelaySeconds The delay in seconds until the creator can withdraw their tokens. Must be greater than or equal to `MIN_UNLOCK_DELAY_SECONDS`.
    function unlockTokens(bytes32 execHash, uint256 unlockDelaySeconds) public auth {
        // Ensure the request has not already had its tokens removed.
        (bool tokensRemoved, ) = areTokensRemoved(execHash);
        require(!tokensRemoved, "TOKENS_REMOVED");
        // Make sure that an unlock is not arleady scheduled.
        require(getRequestUnlockTimestamp[execHash] == 0, "UNLOCK_ALREADY_SCHEDULED");
        // Make sure the caller is the creator of the request.
        require(getRequestCreator[execHash] == msg.sender, "NOT_CREATOR");
        // Make sure the delay is greater than the minimum.
        require(unlockDelaySeconds >= MIN_UNLOCK_DELAY_SECONDS, "DELAY_TOO_SMALL");

        // Set the delay timestamp to (current timestamp + the delay)
        uint256 unlockTimestamp = block.timestamp.add(unlockDelaySeconds);
        getRequestUnlockTimestamp[execHash] = unlockTimestamp;

        emit UnlockTokens(execHash, unlockTimestamp);
    }

    /// @notice Cancels a scheduled unlock.
    /// @param execHash The unique hash of the request which has an unlock scheduled.
    function relockTokens(bytes32 execHash) external auth {
        // Ensure the request has not already had its tokens removed.
        (bool tokensRemoved, ) = areTokensRemoved(execHash);
        require(!tokensRemoved, "TOKENS_REMOVED");
        // Make sure the caller is the creator of the request.
        require(getRequestCreator[execHash] == msg.sender, "NOT_CREATOR");
        // Ensure the request is scheduled to unlock.
        require(getRequestUnlockTimestamp[execHash] != 0, "NO_UNLOCK_SCHEDULED");

        // Reset the unlock timestamp to 0.
        delete getRequestUnlockTimestamp[execHash];

        emit RelockTokens(execHash);
    }

    /// @notice Withdraws tokens (input/gas/bounties) from an unlocked request.
    /// @notice The creator of the request associated with `execHash` must call `unlockTokens` and wait the `unlockDelaySeconds` they specified before calling `withdrawTokens`.
    /// @notice Anyone may call this function, but the tokens will still go the creator of the request associated with the `execHash`.
    /// @param execHash The unique hash of the request to withdraw from.
    function withdrawTokens(bytes32 execHash) external nonReentrant auth {
        // Ensure that the tokens are unlocked.
        (bool tokensUnlocked, ) = areTokensUnlocked(execHash);
        require(tokensUnlocked, "NOT_UNLOCKED");
        // Ensure that the tokens have not already been removed.
        (bool tokensRemoved, ) = areTokensRemoved(execHash);
        require(!tokensRemoved, "TOKENS_REMOVED");

        // Get the request creator.
        address creator = getRequestCreator[execHash];

        // Store that the request has had its input tokens removed.
        getRequestInputTokenRecipientData[execHash] = InputTokenRecipientData(creator, true);

        emit WithdrawTokens(execHash);

        // Transfer the ETH which would have been used for (gas + tip) back to the creator.
        ETH.safeTransfer(
            creator,
            getRequestGasPrice[execHash].mul(getRequestGasLimit[execHash]).add(getRequestTip[execHash])
        );

        // Transfer input tokens back to the creator.
        InputToken[] memory inputTokens = requestInputTokens[execHash];
        for (uint256 i = 0; i < inputTokens.length; i++) {
            inputTokens[i].l2Token.safeTransfer(creator, inputTokens[i].amount);
        }
    }

    /// @notice Resubmit a request with a higher gas price.
    /// @notice This will "uncle" the `execHash` which means after `MIN_UNLOCK_DELAY_SECONDS` it will be disabled and the `newExecHash` will be enabled.
    /// @notice msg.sender must be the creator of the request associated with the `execHash`.
    /// @param execHash The execHash of the request you wish to resubmit with a higher gas price.
    /// @param gasPrice The updated gas price to use for the resubmitted request.
    /// @return newExecHash The unique identifier for the resubmitted request.
    function speedUpRequest(bytes32 execHash, uint256 gasPrice) external auth returns (bytes32 newExecHash) {
        // Ensure that msg.sender is the creator of the request.
        require(getRequestCreator[execHash] == msg.sender, "NOT_CREATOR");
        // Ensure tokens have not already been removed.
        (bool tokensRemoved, ) = areTokensRemoved(execHash);
        require(!tokensRemoved, "TOKENS_REMOVED");
        // Ensure the request has not already been sped up.
        require(getRequestDeathTimestamp[execHash] == 0, "ALREADY_SPED_UP");

        // Get the previous gas price.
        uint256 previousGasPrice = getRequestGasPrice[execHash];

        // Ensure that the new gas price is greater than the previous.
        require(gasPrice > previousGasPrice, "LESS_THAN_PREVIOUS_GAS_PRICE");

        // Get the timestamp when the `execHash` would become uncled if this `speedUpRequest` call succeeds.
        uint256 switchTimestamp = MIN_UNLOCK_DELAY_SECONDS.add(block.timestamp);

        // Ensure that if there is a token unlock scheduled it would be after the switch.
        // Tokens cannot be withdrawn after the switch which is why it's safe if they unlock after.
        uint256 tokenUnlockTimestamp = getRequestUnlockTimestamp[execHash];
        require(tokenUnlockTimestamp == 0 || tokenUnlockTimestamp > switchTimestamp, "UNLOCK_BEFORE_SWITCH");

        // Get more data about the previous request.
        address previousStrategy = getRequestStrategy[execHash];
        bytes memory previousCalldata = getRequestCalldata[execHash];
        uint256 previousGasLimit = getRequestGasLimit[execHash];

        // Generate a new execHash for the resubmitted request.
        systemNonce += 1;
        newExecHash = NovaExecHashLib.compute({
            nonce: systemNonce,
            strategy: previousStrategy,
            l1Calldata: previousCalldata,
            gasPrice: gasPrice
        });

        // Fill out data for the resubmitted request.
        getRequestCreator[newExecHash] = msg.sender;
        getRequestStrategy[newExecHash] = previousStrategy;
        getRequestCalldata[newExecHash] = previousCalldata;
        getRequestGasLimit[newExecHash] = previousGasLimit;
        getRequestGasPrice[newExecHash] = gasPrice;
        getRequestTip[newExecHash] = getRequestTip[execHash];
        // Storing the nonce is just for convenience; it does not need to be on-chain.
        getRequestNonce[execHash] = systemNonce;

        // Map the resubmitted request to its uncle.
        getRequestUncle[newExecHash] = execHash;

        // Set the uncled request to die in MIN_UNLOCK_DELAY_SECONDS.
        getRequestDeathTimestamp[execHash] = switchTimestamp;

        emit SpeedUpRequest(execHash, newExecHash, systemNonce, switchTimestamp);

        // Transfer in additional ETH to pay for the new gas limit.
        ETH.safeTransferFrom(msg.sender, address(this), gasPrice.sub(previousGasPrice).mul(previousGasLimit));
    }

    /*///////////////////////////////////////////////////////////////
                  CROSS DOMAIN MESSENGER ONLY FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @dev Distributes inputs/tips to the relayer as a result of a successful execution.
    /// @dev Only the linked L1_NovaExecutionManager can call via the cross domain messenger.
    /// @param execHash The computed execHash of the execution.
    /// @param rewardRecipient The address the relayer specified to be the recipient of the tokens on L2.
    /// @param reverted If the strategy reverted on L1 during execution.
    /// @param gasUsed The amount of gas used by the execution tx on L1.
    function execCompleted(
        bytes32 execHash,
        address rewardRecipient,
        bool reverted,
        uint256 gasUsed
    ) external onlyFromCrossDomainAccount(L1_NovaExecutionManagerAddress) {
        // Ensure that this request exists.
        require(getRequestCreator[execHash] != address(0), "NOT_CREATED");
        // Ensure tokens have not already been removed.
        (bool tokensRemoved, ) = areTokensRemoved(execHash);
        require(!tokensRemoved, "TOKENS_REMOVED");

        // Get relevant request data.
        uint256 gasLimit = getRequestGasLimit[execHash];
        uint256 gasPrice = getRequestGasPrice[execHash];
        uint256 tip = getRequestTip[execHash];
        address creator = getRequestCreator[execHash];

        // Give the proper input token recipient the ability to claim the tokens.
        getRequestInputTokenRecipientData[execHash].recipient = reverted ? creator : rewardRecipient;

        // The amount of ETH to pay for the gas used (capped at the gas limit).
        uint256 gasPayment = gasPrice.mul(gasUsed > gasLimit ? gasLimit : gasUsed);

        // The amount of ETH to pay as the tip to the rewardRecepient.
        // If the transaction reverted the recipient will get 50% of the tip
        // and the creator will be refunded the remaining portion.
        uint256 recipientTip = reverted ? (tip.div(2)) : tip;

        emit ExecCompleted(execHash, rewardRecipient, reverted, gasUsed);

        // Refund the creator any unused gas + refund some of the tip if reverted
        ETH.safeTransfer(creator, gasLimit.mul(gasPrice).sub(gasPayment).add(tip.sub(recipientTip)));
        // Pay the recipient the gas payment + the tip.
        ETH.safeTransfer(rewardRecipient, gasPayment.add(recipientTip));
    }

    /*///////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if the request has had any of its tokens removed.
    /// @param execHash The request to check.
    /// @return tokensRemoved A boolean indicating if the request has had any of its tokens removed.
    /// @return changeTimestamp A timestamp indicating when the request might have one of its tokens removed or added.
    /// Will be 0 if there is no removal/addition expected.
    /// Will also be 0 if the request has had its tokens withdrawn or it has been executed.
    /// It will be a timestamp if the request will have its tokens added soon (it's a resubmitted copy of an uncled request)
    /// or if the request will have its tokens removed soon (its an uncle scheduled to die soon).
    function areTokensRemoved(bytes32 execHash) public view returns (bool tokensRemoved, uint256 changeTimestamp) {
        address inputTokenRecipient = getRequestInputTokenRecipientData[execHash].recipient;
        if (inputTokenRecipient != address(0)) {
            // The request has been executed or had its tokens withdrawn,
            // so we know it's tokens are removed and won't be added back.
            return (true, 0);
        }

        uint256 deathTimestamp = getRequestDeathTimestamp[execHash];
        if (deathTimestamp != 0) {
            if (block.timestamp >= deathTimestamp) {
                // This request is an uncle which has died, meaning it's tokens
                // have been removed and sent to a resubmitted request.
                return (true, 0);
            } else {
                // This request is an uncle which has not died yet, so we know
                // it has tokens that will be removed on it's deathTimestamp.
                return (false, deathTimestamp);
            }
        }

        bytes32 uncleExecHash = getRequestUncle[execHash];
        if (uncleExecHash == "") {
            // This request does not have an uncle and has passed all
            // the previous removal checks, so we know it has tokens.
            return (false, 0);
        }

        address uncleInputTokenRecipient = getRequestInputTokenRecipientData[uncleExecHash].recipient;
        if (uncleInputTokenRecipient != address(0)) {
            // This request is a resubmitted version of its uncle which was
            // executed before the uncle could "die" and switch its tokens
            // to this resubmitted request, so we know it does not have tokens.
            return (true, 0);
        }

        uint256 uncleDeathTimestamp = getRequestDeathTimestamp[uncleExecHash];
        if (uncleDeathTimestamp > block.timestamp) {
            // This request is a resubmitted version of its uncle which has
            // not "died" yet, so we know it does not have its tokens yet,
            // but will recieve them after the uncleDeathTimestamp.
            return (true, uncleDeathTimestamp);
        }

        // This is a resubmitted request with an uncle that died properly without
        // being executed early, so we know it has it's tokens.
        return (false, 0);
    }

    /// @notice Checks if the request is scheduled to have its tokens unlocked.
    /// @param execHash The request to check.
    /// @return unlocked A boolean indicating if the request has had its tokens unlocked.
    /// @return changeTimestamp A timestamp indicating when the request might have its tokens unlocked.
    /// Will be 0 if there is no unlock is scheduled or it has already unlocked.
    /// It will be a timestamp if an unlock has been scheduled but not completed.
    function areTokensUnlocked(bytes32 execHash) public view returns (bool unlocked, uint256 changeTimestamp) {
        uint256 tokenUnlockTimestamp = getRequestUnlockTimestamp[execHash];

        if (tokenUnlockTimestamp == 0) {
            // There is no unlock scheduled.
            unlocked = false;
            changeTimestamp = 0;
        } else {
            // There has been an unlock scheduled/completed.
            unlocked = block.timestamp >= tokenUnlockTimestamp;
            changeTimestamp = unlocked ? 0 : tokenUnlockTimestamp;
        }
    }
}

// SPDX-License-Identifier: GNU-3
pragma solidity 0.7.6;

/// @notice Provides a flexible and updatable auth pattern which is completely separate from application logic.
/// @author DappHub (https://github.com/dapphub/ds-auth)
abstract contract DSAuth {
    event LogSetAuthority(address indexed authority);
    event LogSetOwner(address indexed owner);

    DSAuthority public authority;
    address public owner;

    constructor() {
        owner = msg.sender;
        emit LogSetOwner(msg.sender);
    }

    function setOwner(address owner_) external auth {
        owner = owner_;
        emit LogSetOwner(owner);
    }

    function setAuthority(DSAuthority authority_) external auth {
        authority = authority_;
        emit LogSetAuthority(address(authority));
    }

    modifier auth {
        require(isAuthorized(msg.sender, msg.sig), "ds-auth-unauthorized");
        _;
    }

    function isAuthorized(address src, bytes4 sig) internal view returns (bool) {
        if (src == address(this)) {
            return true;
        } else if (src == owner) {
            return true;
        } else if (authority == DSAuthority(address(0))) {
            return false;
        } else {
            return authority.canCall(src, address(this), sig);
        }
    }
}

interface DSAuthority {
    function canCall(
        address src,
        address dst,
        bytes4 sig
    ) external view returns (bool);
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.7.6;

/// @notice Utility library to compute a Nova execHash from a nonce, strategy address, calldata and gas price.
library NovaExecHashLib {
    /// @dev Computes a Nova execHash from a nonce, strategy address, calldata and gas price.
    /// @return A Nova execHash: keccak256(nonce, strategy, l1Calldata, gasPrice)
    function compute(
        uint256 nonce,
        address strategy,
        bytes memory l1Calldata,
        uint256 gasPrice
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(nonce, strategy, l1Calldata, gasPrice));
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.7.6;

/// @notice Utility library used to extract the function signature (first 4 bytes) from abi encoded calldata.
library SigLib {
    /// @notice Extracts the function signature (first 4 bytes) from abi encoded calldata.
    /// @param inputCalldata Abi encoded calldata.
    /// @return sig The function signature/selector/sighash.
    function fromCalldata(bytes memory inputCalldata) internal pure returns (bytes4 sig) {
        assembly {
            // Slices the first 4 bytes and loads them into `sig`.
            sig := mload(add(inputCalldata, 0x20))
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

/**
 * @title iOVM_CrossDomainMessenger
 */
interface iOVM_CrossDomainMessenger {

    /**********
     * Events *
     **********/

    event SentMessage(bytes message);
    event RelayedMessage(bytes32 msgHash);
    event FailedRelayedMessage(bytes32 msgHash);


    /*************
     * Variables *
     *************/

    function xDomainMessageSender() external view returns (address);


    /********************
     * Public Functions *
     ********************/

    /**
     * Sends a cross domain message to the target messenger.
     * @param _target Target contract address.
     * @param _message Message to send to the target.
     * @param _gasLimit Gas limit for the provided message.
     */
    function sendMessage(
        address _target,
        bytes calldata _message,
        uint32 _gasLimit
    ) external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () internal {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

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
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
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

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
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
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
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
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
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
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
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
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
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

{
  "optimizer": {
    "enabled": true,
    "runs": 1000000
  },
  "metadata": {
    "bytecodeHash": "none"
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
  "libraries": {}
}