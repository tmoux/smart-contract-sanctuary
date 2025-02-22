// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.7.5;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/drafts/IERC20PermitUpgradeable.sol";
import "../presets/OwnablePausableUpgradeable.sol";
import "../interfaces/ISwiseStaking.sol";

/**
 * @title SwiseStaking
 * @dev SwiseStaking contract distributes the pool's fee to those who have
 * locked their SWISE token for a predefined time. With a longer lock period,
 * a user gets more rETH2 rewards and increases his voting power. If the user decides to take
 * the deposit out before the lock period ends, his deposit will be penalized proportionally to
 * the amount of time that has been left to be locked. The penalty will be distributed among those
 * who still have their SWISE locked proportionally to their amount and lock duration.
 */
contract SwiseStaking is ISwiseStaking, OwnablePausableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // @dev Maps multiplier to the duration of the lock.
    mapping(uint32 => uint256) public override durations;

    // @dev Total points (deposited SWISE amount * multiplier).
    uint256 public override totalPoints;

    mapping(address => uint32) private startMultipliers;

    // @dev Maps owner address to its position.
    mapping(address => Position) private _positions;

    // @dev Address of the StakeWiseToken contract.
    IERC20Upgradeable private swiseToken;

    // @dev Address of the RewardEthToken contract.
    IERC20Upgradeable private rewardEthToken;

    // @dev Total amount of synced rETH2 rewards.
    uint128 private totalEthReward;

    // @dev Last synced rETH2 reward amount per point.
    uint128 public override ethRewardPerPoint;

    // @dev Last synced SWISE reward amount per point.
    uint128 public override swiseRewardPerPoint;

    // @dev Total amount of rETH2 rewards claimed.
    uint128 private totalEthClaimed;

    /**
     * @dev See {ISwiseStaking-initialize}.
     */
    function initialize(
        address admin,
        address _swiseToken,
        address _rewardEthToken,
        uint32[] calldata multipliers,
        uint256[] calldata _durations
    )
        external override initializer
    {
        uint256 multipliersCount = multipliers.length;
        require(multipliersCount == _durations.length, "SwiseStaking: invalid multipliers");

        __OwnablePausableUpgradeable_init(admin);

        swiseToken = IERC20Upgradeable(_swiseToken);
        rewardEthToken = IERC20Upgradeable(_rewardEthToken);

        for (uint256 i = 0; i < multipliersCount; i++) {
            uint32 multiplier = multipliers[i];
            uint256 duration = _durations[i];
            durations[multiplier] = duration;
            emit MultiplierUpdated(msg.sender, multiplier, duration);
        }
    }

    /**
     * @dev See {ISwiseStaking-positions}.
     */
    function positions(address account)
        override
        external
        view
        returns (
            uint96 amount,
            uint32 multiplier,
            uint64 startTimestamp,
            uint64 endTimestamp,
            uint256 ethReward,
            uint256 swiseReward
        )
    {
        Position memory position = _positions[account];

        // SLOAD for gas optimization
        (
            uint256 prevTotalEthReward,
            uint256 prevEthRewardPerPoint,
            uint256 prevTotalPoints
        ) = (
            totalEthReward,
            ethRewardPerPoint,
            totalPoints
        );

        // calculate new total ETH reward
        uint256 newTotalEthReward = uint256(totalEthClaimed).add(rewardEthToken.balanceOf(address(this)));
        uint256 newEthRewardPerPoint;
        if (prevTotalEthReward == newTotalEthReward || prevTotalPoints == 0) {
            // nothing to update as there are no new rewards or no swise locked
            newEthRewardPerPoint = prevEthRewardPerPoint;
        } else {
            // calculate ETH reward since last checkpoint
            uint256 periodEthReward = newTotalEthReward.sub(prevTotalEthReward);
            newEthRewardPerPoint = prevEthRewardPerPoint.add(periodEthReward.mul(1e18).div(prevTotalPoints));
        }

        (ethReward, swiseReward) = _calculateRewards(
            _calculatePositionPoints(position.amount, position.multiplier),
            position.claimedEthRewardPerPoint,
            newEthRewardPerPoint,
            position.claimedSwiseRewardPerPoint,
            swiseRewardPerPoint
        );
        return (
            position.amount,
            position.multiplier,
            position.startTimestamp,
            position.endTimestamp,
            ethReward,
            swiseReward
        );
    }

    /**
     * @dev See {ISwiseStaking-balanceOf}.
     */
    function balanceOf(address account) override external view returns (uint256) {
        Position memory position = _positions[account];
        return _calculatePositionPoints(position.amount, position.multiplier);
    }

    /**
     * @dev See {ISwiseStaking-setMultiplier}.
     */
    function setMultiplier(uint32 multiplier, uint256 duration) external override onlyAdmin {
        durations[multiplier] = duration;
        emit MultiplierUpdated(msg.sender, multiplier, duration);
    }

    /**
     * @dev See {ISwiseStaking-createPositionWithPermit}.
    */
    function createPositionWithPermit(
        uint96 amount,
        uint32 multiplier,
        uint256 deadline,
        bool maxApprove,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external override
    {
        IERC20PermitUpgradeable(address(swiseToken)).permit(msg.sender, address(this), maxApprove ? uint(-1): amount, deadline, v, r, s);
        _createPosition(amount, multiplier);
    }

    /**
     * @dev See {ISwiseStaking-createPosition}.
     */
    function createPosition(uint96 amount, uint32 multiplier) external override {
        _createPosition(amount, multiplier);
    }

    function _createPosition(uint96 amount, uint32 multiplier) internal whenNotPaused {
        require(amount > 0, "SwiseStaking: invalid amount");
        uint256 duration = durations[multiplier];
        require(duration > 0, "SwiseStaking: multiplier not registered");
        require(_positions[msg.sender].amount == 0, "SwiseStaking: position exists");

        // SLOAD for gas optimization
        uint256 prevTotalPoints = totalPoints;

        // update reward ETH token checkpoint
        uint256 newEthRewardPerPoint = updateEthRewardCheckpoint(totalEthClaimed, prevTotalPoints);

        // create new position
        // solhint-disable-next-line not-rely-on-time
        uint256 timestamp = block.timestamp;
        startMultipliers[msg.sender] = multiplier;
        _positions[msg.sender] = Position({
            amount: amount,
            multiplier: multiplier,
            startTimestamp: timestamp.toUint64(),
            endTimestamp: timestamp.add(duration).toUint64(),
            claimedEthRewardPerPoint: newEthRewardPerPoint.toUint128(),
            claimedSwiseRewardPerPoint: swiseRewardPerPoint
        });

        // update total amounts
        uint256 positionAmount = uint256(amount);
        totalPoints = prevTotalPoints.add(_calculatePositionPoints(positionAmount, multiplier));

        // emit event
        emit PositionCreated(msg.sender, multiplier, positionAmount);

        // lock account's tokens
        swiseToken.safeTransferFrom(msg.sender, address(this), positionAmount);
    }

    /**
     * @dev See {ISwiseStaking-updatePositionWithPermit}.
    */
    function updatePositionWithPermit(
        uint256 addedAmount,
        uint32 proposedMultiplier,
        bool compoundSwiseReward,
        uint256 deadline,
        bool maxApprove,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external override
    {
        IERC20PermitUpgradeable(address(swiseToken)).permit(msg.sender, address(this), maxApprove ? uint(-1): addedAmount, deadline, v, r, s);
        _updatePosition(addedAmount, proposedMultiplier, compoundSwiseReward);
    }

    /**
     * @dev See {ISwiseStaking-updatePosition}.
     */
    function updatePosition(uint256 addedAmount, uint32 proposedMultiplier, bool compoundSwiseReward) external override {
        _updatePosition(addedAmount, proposedMultiplier, compoundSwiseReward);
    }

    function _updatePosition(uint256 addedAmount, uint32 proposedMultiplier, bool compoundSwiseReward) internal whenNotPaused {
        Position storage position = _positions[msg.sender];

        // calculate position previous points
        uint256 prevAmount = uint256(position.amount);
        uint256 prevPositionPoints = _calculatePositionPoints(prevAmount, position.multiplier);
        require(prevPositionPoints > 0, "SwiseStaking: position does not exist");

        // SLOAD for gas optimization
        (uint256 prevTotalPoints, uint256 prevTotalEthClaimed) = (totalPoints, totalEthClaimed);

        // update reward ETH token checkpoint
        uint256 newEthRewardPerPoint = updateEthRewardCheckpoint(prevTotalEthClaimed, prevTotalPoints);

        // calculate new multiplier
        uint256 newMultiplier = _updateMultiplier(position, proposedMultiplier);

        // update rewards
        (uint256 ethReward, uint256 swiseReward) = _updateRewards(
            position,
            prevPositionPoints,
            newEthRewardPerPoint
        );

        // update amount
        uint256 newAmount = _updateAmount(position, prevAmount, addedAmount, swiseReward, compoundSwiseReward);

        // update total points
        totalPoints = prevTotalPoints.sub(prevPositionPoints).add(_calculatePositionPoints(newAmount, newMultiplier));

        // transfer ETH tokens
        if (ethReward > 0) {
            totalEthClaimed = prevTotalEthClaimed.add(ethReward).toUint128();
            rewardEthToken.safeTransfer(msg.sender, ethReward);
        }

        // transfer SWISE tokens
        if (addedAmount > 0 || (!compoundSwiseReward && swiseReward > 0)) {
            _processSwisePayment(compoundSwiseReward ? 0 : swiseReward, addedAmount);
        }

        // emit event
        emit PositionUpdated(msg.sender, position.multiplier, newAmount);
    }

    function _updateAmount(
        Position storage position,
        uint256 prevAmount,
        uint256 addedAmount,
        uint256 swiseReward,
        bool compoundSwiseReward
    )
        internal returns (uint256 newAmount)
    {
        newAmount = prevAmount;
        if (addedAmount > 0) newAmount = newAmount.add(addedAmount);
        if (compoundSwiseReward && swiseReward > 0) newAmount = newAmount.add(swiseReward);

        if (newAmount != prevAmount) {
            require(newAmount < 2**96, "SwiseStaking: invalid added amount");
            position.amount = uint96(newAmount);
        }
    }

    function _processSwisePayment(uint256 swiseReward, uint256 addedSwiseAmount) internal {
        // transfer SWISE tokens
        if (addedSwiseAmount > swiseReward) {
            swiseToken.safeTransferFrom(msg.sender, address(this), addedSwiseAmount.sub(swiseReward));
        } else if (addedSwiseAmount < swiseReward) {
            swiseToken.safeTransfer(msg.sender, swiseReward.sub(addedSwiseAmount));
        }
    }

    function _updateRewards(
        Position storage position,
        uint256 prevPositionPoints,
        uint256 newEthRewardPerPoint
    )
        internal returns (uint256 ethReward, uint256 swiseReward)
    {
        (uint256 prevEthRewardPerPoint, uint256 prevSwiseRewardPerPoint) = (
            position.claimedEthRewardPerPoint,
            position.claimedSwiseRewardPerPoint
        );
        uint256 newSwiseRewardPerPoint = swiseRewardPerPoint;
        if (prevEthRewardPerPoint == newEthRewardPerPoint && prevSwiseRewardPerPoint == newSwiseRewardPerPoint) {
            // no new rewards to collect
            return (0, 0);
        }

        // calculate accumulated rewards
        (ethReward, swiseReward) = _calculateRewards(
            prevPositionPoints,
            prevEthRewardPerPoint,
            newEthRewardPerPoint,
            prevSwiseRewardPerPoint,
            newSwiseRewardPerPoint
        );

        // update claimed checkpoints
        if (ethReward > 0 || swiseReward > 0) {
            (position.claimedEthRewardPerPoint, position.claimedSwiseRewardPerPoint) = (
                newEthRewardPerPoint.toUint128(),
                newSwiseRewardPerPoint.toUint128()
            );
        }
    }

    /**
     * @dev See {ISwiseStaking-withdrawPosition}.
     */
    function withdrawPosition() external override whenNotPaused {
        Position storage position = _positions[msg.sender];

        // calculate position current points
        uint256 positionAmount = uint256(position.amount);
        uint256 positionPoints = _calculatePositionPoints(positionAmount, position.multiplier);
        require(positionPoints > 0, "SwiseStaking: position does not exist");

        // SLOAD for gas optimization
        uint256 prevTotalPoints = totalPoints;
        uint256 prevTotalEthClaimed = totalEthClaimed;

        // update reward ETH token checkpoint
        uint256 newEthRewardPerPoint = updateEthRewardCheckpoint(prevTotalEthClaimed, prevTotalPoints);

        // calculate penalty for withdrawing earlier than supposed
        uint256 swisePenalty = _calculatePenalty(
            position.startTimestamp,
            position.endTimestamp,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp,
            positionAmount
        );

        // calculate accumulated rewards
        uint256 prevSwiseRewardPerPoint = swiseRewardPerPoint;
        (uint256 ethReward, uint256 swiseReward) = _calculateRewards(
            positionPoints,
            position.claimedEthRewardPerPoint,
            newEthRewardPerPoint,
            position.claimedSwiseRewardPerPoint,
            prevSwiseRewardPerPoint
        );

        // update SWISE reward token checkpoint
        uint256 newTotalPoints = prevTotalPoints.sub(positionPoints);
        if (swisePenalty > 0 && newTotalPoints > 0) {
            uint256 periodSwiseRewardPerPoint = swisePenalty.mul(1e18).div(newTotalPoints);
            if (periodSwiseRewardPerPoint > 0) {
                swiseRewardPerPoint = prevSwiseRewardPerPoint.add(periodSwiseRewardPerPoint).toUint128();
            } else {
                // skip penalty if it's smaller than the minimal to distribute
                swisePenalty = 0;
            }
        } else if (newTotalPoints == 0) {
            // the last withdrawn position does not receive penalty
            swisePenalty = 0;
        }

        // clean up position
        delete _positions[msg.sender];
        delete startMultipliers[msg.sender];
        totalPoints = newTotalPoints;

        // emit event
        emit PositionWithdrawn(msg.sender, ethReward, swiseReward, swisePenalty);

        // transfer ETH tokens
        if (ethReward > 0) {
            totalEthClaimed = prevTotalEthClaimed.add(ethReward).toUint128();
            rewardEthToken.safeTransfer(msg.sender, ethReward);
        }

        // transfer SWISE tokens
        positionAmount = positionAmount.sub(swisePenalty).add(swiseReward);
        if (positionAmount > 0) {
            swiseToken.safeTransfer(msg.sender, positionAmount);
        }
    }

    function _calculatePositionPoints(uint256 amount, uint256 multiplier) internal pure returns (uint256) {
        if (multiplier == 100) {
            return amount;
        }
        return amount.mul(multiplier).div(100);
    }

    function _calculatePenalty(
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 currentTimestamp,
        uint256 amount
    )
        internal pure returns (uint256 swisePenalty)
    {
        if (currentTimestamp < endTimestamp) {
            // lock time has not passed yet
            uint256 passedDuration = currentTimestamp.sub(startTimestamp);
            uint256 totalDuration = endTimestamp.sub(startTimestamp);
            swisePenalty = amount.sub(amount.mul(passedDuration).div(totalDuration));
        }
    }

    function _updateMultiplier(Position storage position, uint32 proposedMultiplier) internal returns (uint256) {
        // calculate current multiplier
        uint256 startMultiplier = startMultipliers[msg.sender];
        (uint256 startTimestamp, uint256 endTimestamp) = (position.startTimestamp, position.endTimestamp);
        uint256 currMultiplier = _getCurrentMultiplier(startTimestamp, endTimestamp, startMultiplier);

        // calculate new multiplier
        if (proposedMultiplier == 0) {
            // solhint-disable-next-line not-rely-on-time
            require(block.timestamp < endTimestamp, "SwiseStaking: new multiplier must be added");
            // current multiplier should be used
            position.multiplier = currMultiplier.toUint32();
            return currMultiplier;
        } else {
            // new multiplier has been proposed
            uint256 duration = durations[proposedMultiplier];
            // solhint-disable-next-line not-rely-on-time
            uint256 newEndTimestamp = block.timestamp.add(duration);
            require(duration > 0 && newEndTimestamp > endTimestamp, "SwiseStaking: invalid new multiplier");

            startMultipliers[msg.sender] = proposedMultiplier;
            (
                position.multiplier,
                position.startTimestamp,
                position.endTimestamp
            ) = (
                proposedMultiplier,
                // solhint-disable-next-line not-rely-on-time
                block.timestamp.toUint64(),
                newEndTimestamp.toUint64()
            );
            return proposedMultiplier;
        }
    }

    function _getCurrentMultiplier(
        uint256 startTimestamp,
        uint256 endTimestamp,
        uint256 startMultiplier
    )
        internal view returns (uint256 currMultiplier)
    {
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp < endTimestamp && startMultiplier > 100) {
            // lock time has not passed yet
            // solhint-disable-next-line not-rely-on-time
            uint256 passedDuration = block.timestamp.sub(startTimestamp);
            uint256 totalDuration = endTimestamp.sub(startTimestamp);
            currMultiplier = startMultiplier.sub(startMultiplier.sub(100).mul(passedDuration).div(totalDuration));
        } else {
            // lock time has passed
            currMultiplier = 100;
        }
    }

    function _calculateRewards(
        uint256 positionPoints,
        uint256 prevEthRewardPerPoint,
        uint256 newEthRewardPerPoint,
        uint256 prevSwiseRewardPerPoint,
        uint256 newSwiseRewardPerPoint
    )
        internal pure returns (uint256 ethReward, uint256 swiseReward)
    {
        if (prevEthRewardPerPoint < newEthRewardPerPoint) {
            ethReward = positionPoints.mul(newEthRewardPerPoint.sub(prevEthRewardPerPoint)).div(1e18);
        }

        if (prevSwiseRewardPerPoint < newSwiseRewardPerPoint) {
            swiseReward = positionPoints.mul(newSwiseRewardPerPoint.sub(prevSwiseRewardPerPoint)).div(1e18);
        }
    }

    function updateEthRewardCheckpoint(uint256 prevTotalEthClaimed, uint256 prevTotalPoints) internal returns (uint256) {
        // SLOAD for gas optimization
        (uint256 prevTotalEthReward, uint256 prevEthRewardPerPoint) = (totalEthReward, ethRewardPerPoint);

        // calculate new total ETH reward
        uint256 newTotalEthReward = prevTotalEthClaimed.add(rewardEthToken.balanceOf(address(this)));
        if (prevTotalEthReward == newTotalEthReward || prevTotalPoints == 0) {
            // nothing to update as there are no new rewards or no swise locked
            return prevEthRewardPerPoint;
        }

        // calculate ETH reward since last checkpoint
        uint256 periodEthReward = newTotalEthReward.sub(prevTotalEthReward);
        uint256 newEthRewardPerPoint = prevEthRewardPerPoint.add(periodEthReward.mul(1e18).div(prevTotalPoints));

        // write storage values
        (totalEthReward, ethRewardPerPoint) = (newTotalEthReward.toUint128(), newEthRewardPerPoint.toUint128());

        return newEthRewardPerPoint;
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
library SafeMathUpgradeable {
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
 * @dev Wrappers over Solidity's uintXX/intXX casting operators with added overflow
 * checks.
 *
 * Downcasting from uint256/int256 in Solidity does not revert on overflow. This can
 * easily result in undesired exploitation or bugs, since developers usually
 * assume that overflows raise errors. `SafeCast` restores this intuition by
 * reverting the transaction when such an operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 *
 * Can be combined with {SafeMath} and {SignedSafeMath} to extend it to smaller types, by performing
 * all math on `uint256` and `int256` and then downcasting.
 */
library SafeCastUpgradeable {

    /**
     * @dev Returns the downcasted uint128 from uint256, reverting on
     * overflow (when the input is greater than largest uint128).
     *
     * Counterpart to Solidity's `uint128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value < 2**128, "SafeCast: value doesn\'t fit in 128 bits");
        return uint128(value);
    }

    /**
     * @dev Returns the downcasted uint64 from uint256, reverting on
     * overflow (when the input is greater than largest uint64).
     *
     * Counterpart to Solidity's `uint64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        require(value < 2**64, "SafeCast: value doesn\'t fit in 64 bits");
        return uint64(value);
    }

    /**
     * @dev Returns the downcasted uint32 from uint256, reverting on
     * overflow (when the input is greater than largest uint32).
     *
     * Counterpart to Solidity's `uint32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        require(value < 2**32, "SafeCast: value doesn\'t fit in 32 bits");
        return uint32(value);
    }

    /**
     * @dev Returns the downcasted uint16 from uint256, reverting on
     * overflow (when the input is greater than largest uint16).
     *
     * Counterpart to Solidity's `uint16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        require(value < 2**16, "SafeCast: value doesn\'t fit in 16 bits");
        return uint16(value);
    }

    /**
     * @dev Returns the downcasted uint8 from uint256, reverting on
     * overflow (when the input is greater than largest uint8).
     *
     * Counterpart to Solidity's `uint8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits.
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        require(value < 2**8, "SafeCast: value doesn\'t fit in 8 bits");
        return uint8(value);
    }

    /**
     * @dev Converts a signed int256 into an unsigned uint256.
     *
     * Requirements:
     *
     * - input must be greater than or equal to 0.
     */
    function toUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "SafeCast: value must be positive");
        return uint256(value);
    }

    /**
     * @dev Returns the downcasted int128 from int256, reverting on
     * overflow (when the input is less than smallest int128 or
     * greater than largest int128).
     *
     * Counterpart to Solidity's `int128` operator.
     *
     * Requirements:
     *
     * - input must fit into 128 bits
     *
     * _Available since v3.1._
     */
    function toInt128(int256 value) internal pure returns (int128) {
        require(value >= -2**127 && value < 2**127, "SafeCast: value doesn\'t fit in 128 bits");
        return int128(value);
    }

    /**
     * @dev Returns the downcasted int64 from int256, reverting on
     * overflow (when the input is less than smallest int64 or
     * greater than largest int64).
     *
     * Counterpart to Solidity's `int64` operator.
     *
     * Requirements:
     *
     * - input must fit into 64 bits
     *
     * _Available since v3.1._
     */
    function toInt64(int256 value) internal pure returns (int64) {
        require(value >= -2**63 && value < 2**63, "SafeCast: value doesn\'t fit in 64 bits");
        return int64(value);
    }

    /**
     * @dev Returns the downcasted int32 from int256, reverting on
     * overflow (when the input is less than smallest int32 or
     * greater than largest int32).
     *
     * Counterpart to Solidity's `int32` operator.
     *
     * Requirements:
     *
     * - input must fit into 32 bits
     *
     * _Available since v3.1._
     */
    function toInt32(int256 value) internal pure returns (int32) {
        require(value >= -2**31 && value < 2**31, "SafeCast: value doesn\'t fit in 32 bits");
        return int32(value);
    }

    /**
     * @dev Returns the downcasted int16 from int256, reverting on
     * overflow (when the input is less than smallest int16 or
     * greater than largest int16).
     *
     * Counterpart to Solidity's `int16` operator.
     *
     * Requirements:
     *
     * - input must fit into 16 bits
     *
     * _Available since v3.1._
     */
    function toInt16(int256 value) internal pure returns (int16) {
        require(value >= -2**15 && value < 2**15, "SafeCast: value doesn\'t fit in 16 bits");
        return int16(value);
    }

    /**
     * @dev Returns the downcasted int8 from int256, reverting on
     * overflow (when the input is less than smallest int8 or
     * greater than largest int8).
     *
     * Counterpart to Solidity's `int8` operator.
     *
     * Requirements:
     *
     * - input must fit into 8 bits.
     *
     * _Available since v3.1._
     */
    function toInt8(int256 value) internal pure returns (int8) {
        require(value >= -2**7 && value < 2**7, "SafeCast: value doesn\'t fit in 8 bits");
        return int8(value);
    }

    /**
     * @dev Converts an unsigned uint256 into a signed int256.
     *
     * Requirements:
     *
     * - input must be less than or equal to maxInt256.
     */
    function toInt256(uint256 value) internal pure returns (int256) {
        require(value < 2**255, "SafeCast: value doesn't fit in an int256");
        return int256(value);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IERC20Upgradeable.sol";
import "../../math/SafeMathUpgradeable.sol";
import "../../utils/AddressUpgradeable.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;

    function safeTransfer(IERC20Upgradeable token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20Upgradeable token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20Upgradeable token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
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
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
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

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on `{IERC20-approve}`, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 */
interface IERC20PermitUpgradeable {
    /**
     * @dev Sets `value` as the allowance of `spender` over `owner`'s tokens,
     * given `owner`'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for `permit`, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.7.5;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "../interfaces/IOwnablePausable.sol";

/**
 * @title OwnablePausableUpgradeable
 *
 * @dev Bundles Access Control, Pausable and Upgradeable contracts in one.
 *
 */
abstract contract OwnablePausableUpgradeable is IOwnablePausable, PausableUpgradeable, AccessControlUpgradeable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
    * @dev Modifier for checking whether the caller is an admin.
    */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "OwnablePausable: access denied");
        _;
    }

    /**
    * @dev Modifier for checking whether the caller is a pauser.
    */
    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, msg.sender), "OwnablePausable: access denied");
        _;
    }

    // solhint-disable-next-line func-name-mixedcase
    function __OwnablePausableUpgradeable_init(address _admin) internal initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        __OwnablePausableUpgradeable_init_unchained(_admin);
    }

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `PAUSER_ROLE` to the admin account.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __OwnablePausableUpgradeable_init_unchained(address _admin) internal initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(PAUSER_ROLE, _admin);
    }

    /**
     * @dev See {IOwnablePausable-isAdmin}.
     */
    function isAdmin(address _account) external override view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _account);
    }

    /**
     * @dev See {IOwnablePausable-addAdmin}.
     */
    function addAdmin(address _account) external override {
        grantRole(DEFAULT_ADMIN_ROLE, _account);
    }

    /**
     * @dev See {IOwnablePausable-removeAdmin}.
     */
    function removeAdmin(address _account) external override {
        revokeRole(DEFAULT_ADMIN_ROLE, _account);
    }

    /**
     * @dev See {IOwnablePausable-isPauser}.
     */
    function isPauser(address _account) external override view returns (bool) {
        return hasRole(PAUSER_ROLE, _account);
    }

    /**
     * @dev See {IOwnablePausable-addPauser}.
     */
    function addPauser(address _account) external override {
        grantRole(PAUSER_ROLE, _account);
    }

    /**
     * @dev See {IOwnablePausable-removePauser}.
     */
    function removePauser(address _account) external override {
        revokeRole(PAUSER_ROLE, _account);
    }

    /**
     * @dev See {IOwnablePausable-pause}.
     */
    function pause() external override onlyPauser {
        _pause();
    }

    /**
     * @dev See {IOwnablePausable-unpause}.
     */
    function unpause() external override onlyPauser {
        _unpause();
    }
}

// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.7.5;

/**
 * @dev Interface of the SwiseStaking contract.
 */
interface ISwiseStaking {
    /**
    * @dev Structure for storing a new SWISE staking position. Every user can have only one position.
    * @param amount - amount of SWISE to stake.
    * @param multiplier - multiplier used for increasing user's rewards amount and voting power.
    * @param startTimestamp - timestamp when the lock has started.
    * @param endTimestamp - timestamp when the lock will end.
    * @param claimedEthRewardPerPoint - ethRewardPerPoint since the last claim used for rETH2 rewards calculation.
    * @param claimedSwiseRewardPerPoint - swiseRewardPerPoint since the last claim used for SWISE rewards calculation.
    */
    struct Position {
        uint96 amount;
        uint32 multiplier;
        uint64 startTimestamp;
        uint64 endTimestamp;
        uint128 claimedEthRewardPerPoint;
        uint128 claimedSwiseRewardPerPoint;
    }

    /**
    * @dev Event for tracking new positions.
    * @param owner - address of the position owner.
    * @param multiplier - position multiplier.
    * @param amount - amount deposited.
    */
    event PositionCreated(
        address indexed owner,
        uint32 indexed multiplier,
        uint256 amount
    );

    /**
    * @dev Event for tracking position updates.
    * @param owner - address of the position owner.
    * @param multiplier - new position multiplier.
    * @param newAmount - new position amount.
    */
    event PositionUpdated(
        address indexed owner,
        uint32 indexed multiplier,
        uint256 newAmount
    );

    /**
    * @dev Event for tracking multiplier updates.
    * @param sender - address of the update sender.
    * @param multiplier - the multiplier.
    * @param duration - the multiplier lock duration.
    */
    event MultiplierUpdated(
        address indexed sender,
        uint32 multiplier,
        uint256 duration
    );

    /**
    * @dev Event for tracking position withdrawals.
    * @param owner - address of the position owner.
    * @param ethReward - ETH reward collected.
    * @param swiseReward - SWISE reward collected.
    * @param swisePenalty - SWISE penalty received for the early withdrawal.
    */
    event PositionWithdrawn(
        address indexed owner,
        uint256 ethReward,
        uint256 swiseReward,
        uint256 swisePenalty
    );

    /**
    * @dev Function for getting the total allocated points.
    */
    function totalPoints() external view returns (uint256);

    /**
    * @dev Function for getting the current rETH2 reward per point.
    */
    function ethRewardPerPoint() external view returns (uint128);

    /**
    * @dev Function for getting the current SWISE reward per point.
    */
    function swiseRewardPerPoint() external view returns (uint128);

    /**
    * @dev Function for getting the duration of the registered multiplier.
    * @param multiplier - the multiplier to get the duration for.
    */
    function durations(uint32 multiplier) external view returns (uint256);

    /**
    * @dev Function for getting the position of the account.
    * @param account - the address of the account to get the position for.
    */
    function positions(address account)
        external
        view
        returns (
            uint96 amount,
            uint32 multiplier,
            uint64 startTimestamp,
            uint64 endTimestamp,
            uint256 ethReward,
            uint256 swiseReward
        );

    /**
    * @dev Function for getting the current amount of points for the account.
    * @param account - the address of the account to get the points for.
    */
    function balanceOf(address account) external view returns (uint256);

    /**
    * @dev Constructor for initializing the SwiseStaking contract.
    * @param admin - address of the contract admin.
    * @param _swiseToken - address of the StakeWise token.
    * @param _rewardEthToken - address of the RewardEthToken.
    * @param multipliers - array of multipliers to initialize with.
    * @param _durations - array of durations to initialize with.
    */
    function initialize(
        address admin,
        address _swiseToken,
        address _rewardEthToken,
        uint32[] calldata multipliers,
        uint256[] calldata _durations
    ) external;

    /**
    * @dev Function for updating or adding multiplier. Can only be called by account with admin privilege.
    * @param multiplier - the multiplier to update (must be times 100, e.g. 2.5 -> 250).
    * @param duration - the lock duration of the multiplier.
    */
    function setMultiplier(uint32 multiplier, uint256 duration) external;

    /**
    * @dev Function for creating new position.
    * @param amount - amount of SWISE to lock.
    * @param multiplier - the desired rewards and voting multiplier.
    */
    function createPosition(uint96 amount, uint32 multiplier) external;

    /**
    * @dev Function for creating new position with permit.
    * @param amount - amount of SWISE to lock.
    * @param multiplier - the desired rewards and voting multiplier.
    * @param deadline - deadline when the signature expires.
    * @param maxApprove - whether to approve max transfer amount.
    * @param v - secp256k1 signature part.
    * @param r - secp256k1 signature part.
    * @param s - secp256k1 signature part.
    */
    function createPositionWithPermit(
        uint96 amount,
        uint32 multiplier,
        uint256 deadline,
        bool maxApprove,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
    * @dev Function for updating current position with permit call.
    * @param addedAmount - new amount added to the current position.
    * @param proposedMultiplier - new multiplier to use.
    */
    function updatePosition(uint256 addedAmount, uint32 proposedMultiplier, bool compoundSwiseReward) external;

    /**
    * @dev Function for updating current position with permit call.
    * @param addedAmount - new amount added to the current position.
    * @param proposedMultiplier - new multiplier to use.
    * @param deadline - deadline when the signature expires.
    * @param maxApprove - whether to approve max transfer amount.
    * @param v - secp256k1 signature part.
    * @param r - secp256k1 signature part.
    * @param s - secp256k1 signature part.
    */
    function updatePositionWithPermit(
        uint256 addedAmount,
        uint32 proposedMultiplier,
        bool compoundSwiseReward,
        uint256 deadline,
        bool maxApprove,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
    * @dev Function for withdrawing position.
    * When withdrawing before lock has expired, the penalty will be applied.
    */
    function withdrawPosition() external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

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

pragma solidity >=0.6.0 <0.8.0;

import "../utils/EnumerableSetUpgradeable.sol";
import "../utils/AddressUpgradeable.sol";
import "../utils/ContextUpgradeable.sol";
import "../proxy/Initializable.sol";

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControlUpgradeable is Initializable, ContextUpgradeable {
    function __AccessControl_init() internal initializer {
        __Context_init_unchained();
        __AccessControl_init_unchained();
    }

    function __AccessControl_init_unchained() internal initializer {
    }
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using AddressUpgradeable for address;

    struct RoleData {
        EnumerableSetUpgradeable.AddressSet members;
        bytes32 adminRole;
    }

    mapping (bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members.contains(account);
    }

    /**
     * @dev Returns the number of accounts that have `role`. Can be used
     * together with {getRoleMember} to enumerate all bearers of a role.
     */
    function getRoleMemberCount(bytes32 role) public view returns (uint256) {
        return _roles[role].members.length();
    }

    /**
     * @dev Returns one of the accounts that have `role`. `index` must be a
     * value between 0 and {getRoleMemberCount}, non-inclusive.
     *
     * Role bearers are not sorted in any particular way, and their ordering may
     * change at any point.
     *
     * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
     * you perform all queries on the same block. See the following
     * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
     * for more information.
     */
    function getRoleMember(bytes32 role, uint256 index) public view returns (address) {
        return _roles[role].members.at(index);
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to grant");

        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to revoke");

        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public virtual {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        emit RoleAdminChanged(role, _roles[role].adminRole, adminRole);
        _roles[role].adminRole = adminRole;
    }

    function _grantRole(bytes32 role, address account) private {
        if (_roles[role].members.add(account)) {
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (_roles[role].members.remove(account)) {
            emit RoleRevoked(role, account, _msgSender());
        }
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./ContextUpgradeable.sol";
import "../proxy/Initializable.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    function __Pausable_init() internal initializer {
        __Context_init_unchained();
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal initializer {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.7.5;

/**
 * @dev Interface of the OwnablePausableUpgradeable and OwnablePausable contracts.
 */
interface IOwnablePausable {
    /**
    * @dev Function for checking whether an account has an admin role.
    * @param _account - account to check.
    */
    function isAdmin(address _account) external view returns (bool);

    /**
    * @dev Function for assigning an admin role to the account.
    * Can only be called by an account with an admin role.
    * @param _account - account to assign an admin role to.
    */
    function addAdmin(address _account) external;

    /**
    * @dev Function for removing an admin role from the account.
    * Can only be called by an account with an admin role.
    * @param _account - account to remove an admin role from.
    */
    function removeAdmin(address _account) external;

    /**
    * @dev Function for checking whether an account has a pauser role.
    * @param _account - account to check.
    */
    function isPauser(address _account) external view returns (bool);

    /**
    * @dev Function for adding a pauser role to the account.
    * Can only be called by an account with an admin role.
    * @param _account - account to assign a pauser role to.
    */
    function addPauser(address _account) external;

    /**
    * @dev Function for removing a pauser role from the account.
    * Can only be called by an account with an admin role.
    * @param _account - account to remove a pauser role from.
    */
    function removePauser(address _account) external;

    /**
    * @dev Function for pausing the contract.
    */
    function pause() external;

    /**
    * @dev Function for unpausing the contract.
    */
    function unpause() external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSetUpgradeable {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;
import "../proxy/Initializable.sol";

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
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
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
pragma solidity >=0.4.24 <0.8.0;

import "../utils/AddressUpgradeable.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {UpgradeableProxy-constructor}.
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
        require(_initializing || _isConstructor() || !_initialized, "Initializable: contract is already initialized");

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

    /// @dev Returns true if and only if the function is running in the constructor
    function _isConstructor() private view returns (bool) {
        return !AddressUpgradeable.isContract(address(this));
    }
}

{
  "optimizer": {
    "enabled": true,
    "runs": 1000000
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