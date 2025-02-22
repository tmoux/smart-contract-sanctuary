// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./LiquidityMining.sol";

/**
 * @notice LiquidityMiningLens
 * This contract is mostly used by front-end to get LM contract information.
 */
contract LiquidityMiningLens {
    LiquidityMining public liquidityMining;

    constructor(LiquidityMining _liquidityMining) {
        liquidityMining = _liquidityMining;
    }

    struct RewardTokenInfo {
        address rewardTokenAddress;
        string rewardTokenSymbol;
        uint8 rewardTokenDecimals;
    }

    struct RewardAvailable {
        RewardTokenInfo rewardToken;
        uint amount;
    }

    /**
     * @notice Get user all available rewards.
     * @dev This function is normally used by staticcall.
     * @param account The user address
     * @return The list of user available rewards
     */
    function getRewardsAvailable(address account) public returns (RewardAvailable[] memory) {
        address[] memory rewardTokens = liquidityMining.getRewardTokenList();
        uint[] memory beforeBalances = new uint[](rewardTokens.length);
        RewardAvailable[] memory rewardAvailables = new RewardAvailable[](rewardTokens.length);

        for (uint i = 0; i < rewardTokens.length; i++) {
            beforeBalances[i] = IERC20Metadata(rewardTokens[i]).balanceOf(account);
        }

        liquidityMining.claimAllRewards(account);

        for (uint i = 0; i < rewardTokens.length; i++) {
            uint newBalance = IERC20Metadata(rewardTokens[i]).balanceOf(account);
            rewardAvailables[i] = RewardAvailable({
                rewardToken: getRewardTokenInfo(rewardTokens[i]),
                amount: newBalance - beforeBalances[i]
            });
        }
        return rewardAvailables;
    }

    /**
     * @notice Get reward token info.
     * @param rewardToken The reward token address
     * @return The reward token info
     */
    function getRewardTokenInfo(address rewardToken) public view returns (RewardTokenInfo memory) {
        if (rewardToken == liquidityMining.ethAddress()) {
            string memory rewardTokenSymbol = "ETH";
            if (block.chainid == 56) {
                rewardTokenSymbol = "BNB"; // bsc
            } else if (block.chainid == 137) {
                rewardTokenSymbol = "MATIC"; // polygon
            } else if (block.chainid == 250) {
                rewardTokenSymbol = "FTM"; // fantom
            }
            return RewardTokenInfo({
                rewardTokenAddress: liquidityMining.ethAddress(),
                rewardTokenSymbol: rewardTokenSymbol,
                rewardTokenDecimals: uint8(18)
            });
        } else {
            return RewardTokenInfo({
                rewardTokenAddress: rewardToken,
                rewardTokenSymbol: IERC20Metadata(rewardToken).symbol(),
                rewardTokenDecimals: IERC20Metadata(rewardToken).decimals()
            });
        }
    }

    struct RewardSpeed {
        uint speed;
        uint start;
        uint end;
    }

    struct RewardSpeedInfo {
        RewardTokenInfo rewardToken;
        RewardSpeed supplySpeed;
        RewardSpeed borrowSpeed;
    }

    struct MarketRewardSpeed {
        address cToken;
        RewardSpeedInfo[] rewardSpeeds;
    }

    /**
     * @notice Get reward speed info by market.
     * @param cToken The market address
     * @return The market reward speed info
     */
    function getMarketRewardSpeeds(address cToken) public view returns (MarketRewardSpeed memory) {
        address[] memory rewardTokens = liquidityMining.getRewardTokenList();
        RewardSpeedInfo[] memory rewardSpeeds = new RewardSpeedInfo[](rewardTokens.length);
        for (uint i = 0; i < rewardTokens.length; i++) {
            (uint supplySpeed, uint supplyStart, uint supplyEnd) = liquidityMining.rewardSupplySpeeds(rewardTokens[i], cToken);
            (uint borrowSpeed, uint borrowStart, uint borrowEnd) = liquidityMining.rewardBorrowSpeeds(rewardTokens[i], cToken);
            rewardSpeeds[i] = RewardSpeedInfo({
                rewardToken: getRewardTokenInfo(rewardTokens[i]),
                supplySpeed: RewardSpeed({
                    speed: supplySpeed,
                    start: supplyStart,
                    end: supplyEnd
                }),
                borrowSpeed: RewardSpeed({
                    speed: borrowSpeed,
                    start: borrowStart,
                    end: borrowEnd
                })
            });
        }
        return MarketRewardSpeed({
            cToken: cToken,
            rewardSpeeds: rewardSpeeds
        });
    }

    /**
     * @notice Get all market reward speed info.
     * @param cTokens The market addresses
     * @return The list of reward speed info
     */
    function getAllMarketRewardSpeeds(address[] memory cTokens) public view returns (MarketRewardSpeed[] memory) {
        MarketRewardSpeed[] memory allRewardSpeeds = new MarketRewardSpeed[](cTokens.length);
        for (uint i = 0; i < cTokens.length; i++) {
            allRewardSpeeds[i] = getMarketRewardSpeeds(cTokens[i]);
        }
        return allRewardSpeeds;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./LiquidityMiningStorage.sol";
import "./interfaces/ComptrollerInterface.sol";
import "./interfaces/CTokenInterface.sol";
import "./interfaces/LiquidityMiningInterface.sol";

contract LiquidityMining is Initializable, UUPSUpgradeable, OwnableUpgradeable, LiquidityMiningStorage, LiquidityMiningInterface {
    using SafeERC20 for IERC20;

    uint internal constant initialIndex = 1e18;
    address public constant ethAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @notice Emitted when a supplier's reward supply index is updated
     */
    event UpdateSupplierRewardIndex(
        address indexed rewardToken,
        address indexed cToken,
        address indexed supplier,
        uint rewards,
        uint supplyIndex
    );

    /**
     * @notice Emitted when a borrower's reward borrower index is updated
     */
    event UpdateBorrowerRewardIndex(
        address indexed rewardToken,
        address indexed cToken,
        address indexed borrower,
        uint rewards,
        uint borrowIndex
    );

    /**
     * @notice Emitted when a market's reward supply speed is updated
     */
    event UpdateSupplyRewardSpeed(
        address indexed rewardToken,
        address indexed cToken,
        uint indexed speed,
        uint start,
        uint end
    );

    /**
     * @notice Emitted when a market's reward borrow speed is updated
     */
    event UpdateBorrowRewardSpeed(
        address indexed rewardToken,
        address indexed cToken,
        uint indexed speed,
        uint start,
        uint end
    );

    /**
     * @notice Emitted when rewards are transferred to a user
     */
    event TransferReward(
        address indexed rewardToken,
        address indexed account,
        uint indexed amount
    );

    /**
     * @notice Emitted when a debtor is updated
     */
    event UpdateDebtor(
        address indexed account,
        bool indexed isDebtor
    );

    /**
     * @notice Initialize the contract with admin and comptroller
     */
    function initialize(address _admin, address _comptroller) initializer public {
        __Ownable_init();

        comptroller = _comptroller;
        transferOwnership(_admin);
    }

    /**
     * @notice Modifier used internally that assures the sender is the comptroller.
     */
    modifier onlyComptroller() {
        require(msg.sender == comptroller, "only comptroller could perform the action");
        _;
    }

    /**
     * @notice Contract might receive ETH as one of the LM rewards.
     */
    receive() external payable {}

    /* Comptroller functions */

    /**
     * @notice Accrue rewards to the market by updating the supply index and calculate rewards accrued by suppliers
     * @param cToken The market whose supply index to update
     * @param suppliers The related suppliers
     */
    function updateSupplyIndex(address cToken, address[] memory suppliers) external override onlyComptroller {
        // Distribute the rewards right away.
        updateSupplyIndexInternal(rewardTokens, cToken, suppliers, true);
    }

    /**
     * @notice Accrue rewards to the market by updating the borrow index and calculate rewards accrued by borrowers
     * @param cToken The market whose borrow index to update
     * @param borrowers The related borrowers
     */
    function updateBorrowIndex(address cToken, address[] memory borrowers) external override onlyComptroller {
        // Distribute the rewards right away.
        updateBorrowIndexInternal(rewardTokens, cToken, borrowers, true);
    }

    /* User functions */

    /**
     * @notice Return the current block number.
     * @return The current block number
     */
    function getBlockNumber() public virtual view returns (uint) {
        return block.number;
    }

    /**
     * @notice Return the reward token list.
     * @return The list of reward token addresses
     */
    function getRewardTokenList() external view returns (address[] memory) {
        return rewardTokens;
    }

    /**
     * @notice Claim all the rewards accrued by holder in all markets
     * @param holder The address to claim rewards for
     */
    function claimAllRewards(address holder) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        address[] memory allMarkets = ComptrollerInterface(comptroller).getAllMarkets();
        return claimRewards(holders, allMarkets, rewardTokens, true, true);
    }

    /**
     * @notice Claim the rewards accrued by the holders
     * @param holders The addresses to claim rewards for
     * @param cTokens The list of markets to claim rewards in
     * @param rewards The list of reward tokens to claim
     * @param borrowers Whether or not to claim rewards earned by borrowing
     * @param suppliers Whether or not to claim rewards earned by supplying
     */
    function claimRewards(address[] memory holders, address[] memory cTokens, address[] memory rewards, bool borrowers, bool suppliers) public {
        for (uint i = 0; i < cTokens.length; i++) {
            address cToken = cTokens[i];
            (bool isListed, , ) = ComptrollerInterface(comptroller).markets(cToken);
            require(isListed, "market must be listed");

            // Same reward generated from multiple markets could aggregate and distribute once later for gas consumption.
            if (borrowers == true) {
                updateBorrowIndexInternal(rewards, cToken, holders, false);
            }
            if (suppliers == true) {
                updateSupplyIndexInternal(rewards, cToken, holders, false);
            }
        }

        // Distribute the rewards.
        for (uint i = 0; i < rewards.length; i++) {
            for (uint j = 0; j < holders.length; j++) {
                address rewardToken = rewards[i];
                address holder = holders[j];
                rewardAccrued[rewardToken][holder] = transferReward(rewardToken, holder, rewardAccrued[rewardToken][holder]);
            }
        }
    }

    /**
     * @notice Update accounts to be debtors or not. Debtors couldn't claim rewards until their bad debts are repaid.
     * @param accounts The list of accounts to be updated
     */
    function updateDebtors(address[] memory accounts) external {
        for (uint i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            (uint err, , uint shortfall) = ComptrollerInterface(comptroller).getAccountLiquidity(account);
            require(err == 0, "failed to get account liquidity from comptroller");

            if (shortfall > 0 && !debtors[account]) {
                debtors[account] = true;
                emit UpdateDebtor(account, true);
            } else if (shortfall == 0 && debtors[account]) {
                debtors[account] = false;
                emit UpdateDebtor(account, false);
            }
        }
    }

    /* Admin functions */

    /**
     * @notice Add new reward token. Revert if the reward token has been added
     * @param rewardToken The new reward token
     */
    function _addRewardToken(address rewardToken) external onlyOwner {
        require(!rewardTokensMap[rewardToken], "reward token has been added");
        rewardTokensMap[rewardToken] = true;
        rewardTokens.push(rewardToken);
    }

    /**
     * @notice Set cTokens reward supply speeds
     * @param rewardToken The reward token
     * @param cTokens The addresses of cTokens
     * @param speeds The list of reward speeds
     * @param starts The list of start block numbers
     * @param ends The list of end block numbers
     */
    function _setRewardSupplySpeeds(address rewardToken, address[] memory cTokens, uint[] memory speeds, uint[] memory starts, uint[] memory ends) external onlyOwner {
        _setRewardSpeeds(rewardToken, cTokens, speeds, starts, ends, true);
    }

    /**
     * @notice Set cTokens reward borrow speeds
     * @param rewardToken The reward token
     * @param cTokens The addresses of cTokens
     * @param speeds The list of reward speeds
     * @param starts The list of start block numbers
     * @param ends The list of end block numbers
     */
    function _setRewardBorrowSpeeds(address rewardToken, address[] memory cTokens, uint[] memory speeds, uint[] memory starts, uint[] memory ends) external onlyOwner {
        _setRewardSpeeds(rewardToken, cTokens, speeds, starts, ends, false);
    }

    /* Internal functions */

    /**
     * @dev _authorizeUpgrade is used by UUPSUpgradeable to determine if it's allowed to upgrade a proxy implementation.
     * @param newImplementation The new implementation
     *
     * Ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Given the reward token list, accrue rewards to the market by updating the supply index and calculate rewards accrued by suppliers
     * @param rewards The list of rewards to update
     * @param cToken The market whose supply index to update
     * @param suppliers The related suppliers
     * @param distribute Distribute the reward or not
     */
    function updateSupplyIndexInternal(address[] memory rewards, address cToken, address[] memory suppliers, bool distribute) internal {
        for (uint i = 0; i < rewards.length; i++) {
            require(rewardTokensMap[rewards[i]], "reward token not support");
            updateGlobalSupplyIndex(rewards[i], cToken);
            for (uint j = 0; j < suppliers.length; j++) {
                updateUserSupplyIndex(rewards[i], cToken, suppliers[j], distribute);
            }
        }
    }

    /**
     * @notice Given the reward token list, accrue rewards to the market by updating the borrow index and calculate rewards accrued by borrowers
     * @param rewards The list of rewards to update
     * @param cToken The market whose borrow index to update
     * @param borrowers The related borrowers
     * @param distribute Distribute the reward or not
     */
    function updateBorrowIndexInternal(address[] memory rewards, address cToken, address[] memory borrowers, bool distribute) internal {
        for (uint i = 0; i < rewards.length; i++) {
            require(rewardTokensMap[rewards[i]], "reward token not support");

            uint marketBorrowIndex = CTokenInterface(cToken).borrowIndex();
            updateGlobalBorrowIndex(rewards[i], cToken, marketBorrowIndex);
            for (uint j = 0; j < borrowers.length; j++) {
                updateUserBorrowIndex(rewards[i], cToken, borrowers[j], marketBorrowIndex, distribute);
            }
        }
    }

    /**
     * @notice Accrue rewards to the market by updating the supply index
     * @param rewardToken The reward token
     * @param cToken The market whose supply index to update
     */
    function updateGlobalSupplyIndex(address rewardToken, address cToken) internal {
        RewardState storage supplyState = rewardSupplyState[rewardToken][cToken];
        RewardSpeed memory supplySpeed = rewardSupplySpeeds[rewardToken][cToken];
        uint blockNumber = getBlockNumber();
        if (blockNumber > supplyState.block) {
            if (supplySpeed.speed == 0 || supplySpeed.start > blockNumber || supplyState.block > supplySpeed.end) {
                // 1. The reward speed is zero,
                // 2. The reward hasn't started yet,
                // 3. The supply state has handled the end of the reward,
                // just update the block number.
                supplyState.block = blockNumber;
            } else {
                // fromBlock is the max of the last update block number and the reward start block number.
                uint fromBlock = max(supplyState.block, supplySpeed.start);
                // toBlock is the min of the current block number and the reward end block number.
                uint toBlock = min(blockNumber, supplySpeed.end);
                // deltaBlocks is the block difference used for calculating the rewards.
                uint deltaBlocks = toBlock - fromBlock;
                uint rewardAccrued = deltaBlocks * supplySpeed.speed;
                uint supplyTokens = CTokenInterface(cToken).totalSupply();
                uint ratio = supplyTokens > 0 ? rewardAccrued * 1e18 / supplyTokens : 0;
                uint index = supplyState.index + ratio;
                rewardSupplyState[rewardToken][cToken] = RewardState({
                    index: index,
                    block: blockNumber
                });
            }
        }
    }

    /**
     * @notice Accrue rewards to the market by updating the borrow index
     * @param rewardToken The reward token
     * @param cToken The market whose borrow index to update
     * @param marketBorrowIndex The market borrow index
     */
    function updateGlobalBorrowIndex(address rewardToken, address cToken, uint marketBorrowIndex) internal {
        RewardState storage borrowState = rewardBorrowState[rewardToken][cToken];
        RewardSpeed memory borrowSpeed = rewardBorrowSpeeds[rewardToken][cToken];
        uint blockNumber = getBlockNumber();
        if (blockNumber > borrowState.block) {
            if (borrowSpeed.speed == 0 || blockNumber < borrowSpeed.start || borrowState.block > borrowSpeed.end) {
                // 1. The reward speed is zero,
                // 2. The reward hasn't started yet,
                // 3. The borrow state has handled the end of the reward,
                // just update the block number.
                borrowState.block = blockNumber;
            } else {
                // fromBlock is the max of the last update block number and the reward start block number.
                uint fromBlock = max(borrowState.block, borrowSpeed.start);
                // toBlock is the min of the current block number and the reward end block number.
                uint toBlock = min(blockNumber, borrowSpeed.end);
                // deltaBlocks is the block difference used for calculating the rewards.
                uint deltaBlocks = toBlock - fromBlock;
                uint rewardAccrued = deltaBlocks * borrowSpeed.speed;
                uint borrowAmount = CTokenInterface(cToken).totalBorrows() * 1e18 / marketBorrowIndex;
                uint ratio = borrowAmount > 0 ? rewardAccrued * 1e18 / borrowAmount : 0;
                uint index = borrowState.index + ratio;
                rewardBorrowState[rewardToken][cToken] = RewardState({
                    index: index,
                    block: blockNumber
                });
            }
        }
    }

    /**
     * @notice Calculate rewards accrued by a supplier and possibly transfer it to them
     * @param rewardToken The reward token
     * @param cToken The market in which the supplier is interacting
     * @param supplier The address of the supplier to distribute rewards to
     * @param distribute Distribute the reward or not
     */
    function updateUserSupplyIndex(address rewardToken, address cToken, address supplier, bool distribute) internal {
        RewardState memory supplyState = rewardSupplyState[rewardToken][cToken];
        uint supplyIndex = supplyState.index;
        uint supplierIndex = rewardSupplierIndex[rewardToken][cToken][supplier];
        rewardSupplierIndex[rewardToken][cToken][supplier] = supplyIndex;

        if (supplierIndex == 0 && supplyIndex > 0) {
            supplierIndex = initialIndex;
        }

        uint deltaIndex = supplyIndex - supplierIndex;
        uint supplierTokens = CTokenInterface(cToken).balanceOf(supplier);
        uint supplierDelta = supplierTokens * deltaIndex / 1e18;
        uint accruedAmount = rewardAccrued[rewardToken][supplier] + supplierDelta;
        if (distribute) {
            rewardAccrued[rewardToken][supplier] = transferReward(rewardToken, supplier, accruedAmount);
        } else {
            rewardAccrued[rewardToken][supplier] = accruedAmount;
        }
        emit UpdateSupplierRewardIndex(rewardToken, cToken, supplier, supplierDelta, supplyIndex);
    }

    /**
     * @notice Calculate rewards accrued by a borrower and possibly transfer it to them
     * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
     * @param rewardToken The reward token
     * @param cToken The market in which the borrower is interacting
     * @param borrower The address of the borrower to distribute rewards to
     * @param marketBorrowIndex The market borrow index
     * @param distribute Distribute the reward or not
     */
    function updateUserBorrowIndex(address rewardToken, address cToken, address borrower, uint marketBorrowIndex, bool distribute) internal {
        RewardState memory borrowState = rewardBorrowState[rewardToken][cToken];
        uint borrowIndex = borrowState.index;
        uint borrowerIndex = rewardBorrowerIndex[rewardToken][cToken][borrower];
        rewardBorrowerIndex[rewardToken][cToken][borrower] = borrowIndex;

        if (borrowerIndex > 0) {
            uint deltaIndex = borrowIndex - borrowerIndex;
            uint borrowerAmount = CTokenInterface(cToken).borrowBalanceStored(borrower) * 1e18 / marketBorrowIndex;
            uint borrowerDelta = borrowerAmount * deltaIndex / 1e18;
            uint accruedAmount = rewardAccrued[rewardToken][borrower] + borrowerDelta;
            if (distribute) {
                rewardAccrued[rewardToken][borrower] = transferReward(rewardToken, borrower, accruedAmount);
            } else {
                rewardAccrued[rewardToken][borrower] = accruedAmount;
            }
            emit UpdateBorrowerRewardIndex(rewardToken, cToken, borrower, borrowerDelta, borrowIndex);
        }
    }

    /**
     * @notice Transfer rewards to the user
     * @param rewardToken The reward token
     * @param user The address of the user to transfer rewards to
     * @param amount The amount of rewards to (possibly) transfer
     * @return The amount of rewards which was NOT transferred to the user
     */
    function transferReward(address rewardToken, address user, uint amount) internal returns (uint) {
        uint remain = rewardToken == ethAddress ? address(this).balance : IERC20(rewardToken).balanceOf(address(this));
        if (amount > 0 && amount <= remain && !debtors[user]) {
            if (rewardToken == ethAddress) {
                payable(user).transfer(amount);
            } else {
                IERC20(rewardToken).safeTransfer(user, amount);
            }
            emit TransferReward(rewardToken, user, amount);
            return 0;
        }
        return amount;
    }

    /**
     * @notice Set reward speeds
     * @param rewardToken The reward token
     * @param cTokens The addresses of cTokens
     * @param speeds The list of reward speeds
     * @param starts The list of start block numbers
     * @param ends The list of end block numbers
     * @param supply It's supply speed or borrow speed
     */
    function _setRewardSpeeds(address rewardToken, address[] memory cTokens, uint[] memory speeds, uint[] memory starts, uint[] memory ends, bool supply) internal {
        uint blockNumber = getBlockNumber();
        uint numMarkets = cTokens.length;
        require(numMarkets != 0 && numMarkets == speeds.length && numMarkets == starts.length && numMarkets == ends.length, "invalid input");
        require(rewardTokensMap[rewardToken], "reward token was not added");

        for (uint i = 0; i < numMarkets; i++) {
            address cToken = cTokens[i];
            uint speed = speeds[i];
            uint start = starts[i];
            uint end = ends[i];
            if (supply) {
                if (isSupplyRewardStateInit(rewardToken, cToken)) {
                    // Update the supply index.
                    updateGlobalSupplyIndex(rewardToken, cToken);
                } else {
                    // Initialize the supply index.
                    rewardSupplyState[rewardToken][cToken] = RewardState({
                        index: initialIndex,
                        block: blockNumber
                    });
                }

                validateRewardContent(rewardSupplySpeeds[rewardToken][cToken], start, end);
                rewardSupplySpeeds[rewardToken][cToken] = RewardSpeed({
                    speed: speed,
                    start: start,
                    end: end
                });
                emit UpdateSupplyRewardSpeed(rewardToken, cToken, speed, start, end);
            } else {
                if (isBorrowRewardStateInit(rewardToken, cToken)) {
                    // Update the borrow index.
                    uint marketBorrowIndex = CTokenInterface(cToken).borrowIndex();
                    updateGlobalBorrowIndex(rewardToken, cToken, marketBorrowIndex);
                } else {
                    // Initialize the borrow index.
                    rewardBorrowState[rewardToken][cToken] = RewardState({
                        index: initialIndex,
                        block: blockNumber
                    });
                }

                validateRewardContent(rewardBorrowSpeeds[rewardToken][cToken], start, end);
                rewardBorrowSpeeds[rewardToken][cToken] = RewardSpeed({
                    speed: speed,
                    start: start,
                    end: end
                });
                emit UpdateBorrowRewardSpeed(rewardToken, cToken, speed, start, end);
            }
        }
    }

    /**
     * @notice Internal function to tell if the supply reward state is initialized or not.
     * @param rewardToken The reward token
     * @param cToken The market
     * @return It's initialized or not
     */
    function isSupplyRewardStateInit(address rewardToken, address cToken) internal view returns (bool) {
        return rewardSupplyState[rewardToken][cToken].index != 0 && rewardSupplyState[rewardToken][cToken].block != 0;
    }

    /**
     * @notice Internal function to tell if the borrow reward state is initialized or not.
     * @param rewardToken The reward token
     * @param cToken The market
     * @return It's initialized or not
     */
    function isBorrowRewardStateInit(address rewardToken, address cToken) internal view returns (bool) {
        return rewardBorrowState[rewardToken][cToken].index != 0 && rewardBorrowState[rewardToken][cToken].block != 0;
    }

    /**
     * @notice Internal function to check the new start block number and the end block number.
     * @dev This function will revert if any validation failed.
     * @param currentSpeed The current reward speed
     * @param newStart The new start block number
     * @param newEnd The new end block number
     */
    function validateRewardContent(RewardSpeed memory currentSpeed, uint newStart, uint newEnd) internal view {
        uint blockNumber = getBlockNumber();
        require(newEnd >= blockNumber, "the end block number must be greater than the current block number");
        require(newEnd >= newStart, "the end block number must be greater than the start block number");
        if (blockNumber < currentSpeed.end && blockNumber > currentSpeed.start && currentSpeed.start != 0) {
            require(currentSpeed.start == newStart, "cannot change the start block number after the reward starts");
        }
    }

    /**
     * @notice Internal function to get the min value of two.
     * @param a The first value
     * @param b The second value
     * @return The min one
     */
    function min(uint a, uint b) internal pure returns (uint) {
        if (a < b) {
            return a;
        }
        return b;
    }

    /**
     * @notice Internal function to get the max value of two.
     * @param a The first value
     * @param b The second value
     * @return The max one
     */
    function max(uint a, uint b) internal pure returns (uint) {
        if (a > b) {
            return a;
        }
        return b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

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
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
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

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";
/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {

    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ERC1967/ERC1967UpgradeUpgradeable.sol";
import "./Initializable.sol";

/**
 * @dev Base contract for building openzeppelin-upgrades compatible implementations for the {ERC1967Proxy}. It includes
 * publicly available upgrade functions that are called by the plugin and by the secure upgrade mechanism to verify
 * continuation of the upgradability.
 *
 * The {_authorizeUpgrade} function MUST be overridden to include access restriction to the upgrade mechanism.
 *
 * _Available since v4.1._
 */
abstract contract UUPSUpgradeable is Initializable, ERC1967UpgradeUpgradeable {
    function __UUPSUpgradeable_init() internal initializer {
        __ERC1967Upgrade_init_unchained();
        __UUPSUpgradeable_init_unchained();
    }

    function __UUPSUpgradeable_init_unchained() internal initializer {
    }
    function upgradeTo(address newImplementation) external virtual {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallSecure(newImplementation, bytes(""), false);
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) external payable virtual {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallSecure(newImplementation, data, true);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract LiquidityMiningStorage {
    /// @notice The comptroller that wants to distribute rewards.
    address public comptroller;

    /// @notice The support reward tokens.
    address[] public rewardTokens;

    /// @notice The support reward tokens.
    mapping(address => bool) public rewardTokensMap;

    struct RewardSpeed {
        uint speed;
        uint start;
        uint end;
    }

    /// @notice The reward speeds of each reward token for every supply market
    mapping(address => mapping(address => RewardSpeed)) public rewardSupplySpeeds;

    /// @notice The reward speeds of each reward token for every borrow market
    mapping(address => mapping(address => RewardSpeed)) public rewardBorrowSpeeds;

    struct RewardState {
        uint index;
        uint block;
    }

    /// @notice The market reward supply state for each market
    mapping(address => mapping(address => RewardState)) public rewardSupplyState;

    /// @notice The market reward borrow state for each market
    mapping(address => mapping(address => RewardState)) public rewardBorrowState;

    /// @notice The supply index for each market for each supplier as of the last time they accrued rewards
    mapping(address => mapping(address => mapping(address => uint))) public rewardSupplierIndex;

    /// @notice The borrow index for each market for each borrower as of the last time they accrued rewards
    mapping(address => mapping(address => mapping(address => uint))) public rewardBorrowerIndex;

    /// @notice The reward accrued but not yet transferred to each user
    mapping(address => mapping(address => uint)) public rewardAccrued;

    /// @notice The debtors who can't claim rewards until their bad debts are repaid.
    mapping(address => bool) public debtors;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ComptrollerInterface {
    function getAllMarkets() external view returns (address[] memory);
    function markets(address) external view returns (bool, uint, uint);
    function getAccountLiquidity(address) external view returns (uint, uint, uint);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface CTokenInterface {
    function balanceOf(address owner) external view returns (uint);
    function borrowBalanceStored(address account) external view returns (uint);
    function borrowIndex() external view returns (uint);
    function totalSupply() external view returns (uint);
    function totalBorrows() external view returns (uint);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @dev LiquidityMiningInterface is for comptroller
interface LiquidityMiningInterface {
    function updateSupplyIndex(address cToken, address[] memory accounts) external;
    function updateBorrowIndex(address cToken, address[] memory accounts) external;
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "../beacon/IBeaconUpgradeable.sol";
import "../../utils/AddressUpgradeable.sol";
import "../../utils/StorageSlotUpgradeable.sol";
import "../utils/Initializable.sol";

/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 *
 * _Available since v4.1._
 *
 * @custom:oz-upgrades-unsafe-allow delegatecall
 */
abstract contract ERC1967UpgradeUpgradeable is Initializable {
    function __ERC1967Upgrade_init() internal initializer {
        __ERC1967Upgrade_init_unchained();
    }

    function __ERC1967Upgrade_init_unchained() internal initializer {
    }
    // This is the keccak-256 hash of "eip1967.proxy.rollback" subtracted by 1
    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        require(AddressUpgradeable.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Perform implementation upgrade
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Perform implementation upgrade with additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCall(address newImplementation, bytes memory data, bool forceCall) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(newImplementation, data);
        }
    }

    /**
     * @dev Perform implementation upgrade with security checks for UUPS proxies, and additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCallSecure(address newImplementation, bytes memory data, bool forceCall) internal {
        address oldImplementation = _getImplementation();

        // Initial upgrade and setup call
        _setImplementation(newImplementation);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(newImplementation, data);
        }

        // Perform rollback test if not already in progress
        StorageSlotUpgradeable.BooleanSlot storage rollbackTesting = StorageSlotUpgradeable.getBooleanSlot(_ROLLBACK_SLOT);
        if (!rollbackTesting.value) {
            // Trigger rollback using upgradeTo from the new implementation
            rollbackTesting.value = true;
            _functionDelegateCall(
                newImplementation,
                abi.encodeWithSignature(
                    "upgradeTo(address)",
                    oldImplementation
                )
            );
            rollbackTesting.value = false;
            // Check rollback was effective
            require(oldImplementation == _getImplementation(), "ERC1967Upgrade: upgrade breaks further upgrades");
            // Finally reset to the new implementation and log the upgrade
            _setImplementation(newImplementation);
            emit Upgraded(newImplementation);
        }
    }

    /**
     * @dev Perform beacon upgrade with additional setup call. Note: This upgrades the address of the beacon, it does
     * not upgrade the implementation contained in the beacon (see {UpgradeableBeacon-_setImplementation} for that).
     *
     * Emits a {BeaconUpgraded} event.
     */
    function _upgradeBeaconToAndCall(address newBeacon, bytes memory data, bool forceCall) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(IBeaconUpgradeable(newBeacon).implementation(), data);
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: new admin is the zero address");
        StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function _changeAdmin(address newAdmin) internal {
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1)) and is validated in the constructor.
     */
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Emitted when the beacon is upgraded.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Returns the current beacon.
     */
    function _getBeacon() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        require(
            AddressUpgradeable.isContract(newBeacon),
            "ERC1967: new beacon is not a contract"
        );
        require(
            AddressUpgradeable.isContract(IBeaconUpgradeable(newBeacon).implementation()),
            "ERC1967: beacon implementation is not a contract"
        );
        StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    /*
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function _functionDelegateCall(address target, bytes memory data) private returns (bytes memory) {
        require(AddressUpgradeable.isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, "Address: low-level delegate call failed");
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
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeaconUpgradeable {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {BeaconProxy} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * _Available since v4.1 for `address`, `bool`, `bytes32`, and `uint256`._
 */
library StorageSlotUpgradeable {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly {
            r.slot := slot
        }
    }
}

{
  "optimizer": {
    "enabled": true,
    "runs": 200
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