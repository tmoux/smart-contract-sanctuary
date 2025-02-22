// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity 0.7.1;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IVoucherKernel.sol";
import "./interfaces/IERC20WithPermit.sol";
import "./interfaces/IFundLimitsOracle.sol";
import "./interfaces/IBosonRouter.sol";
import "./interfaces/ICashier.sol";
import "./ERC1155ERC721.sol";
import "./UsingHelpers.sol";

/**
 * @title Contract for interacting with Boson Protocol from the user's perspective.
 */
contract BosonRouter is
    IBosonRouter,
    UsingHelpers,
    Pausable,
    ReentrancyGuard,
    Ownable
{
    using Address for address payable;
    using SafeMath for uint256;

    mapping(address => uint256) public correlationIds; // whenever a seller or a buyer interacts with the smart contract, a personal txID is emitted from an event.

    using SafeMath for uint256;

    address public cashierAddress;
    address public voucherKernel;
    address public tokensContractAddress;
    address public fundLimitsOracle;

    event LogOrderCreated(
        uint256 indexed _tokenIdSupply,
        address _seller,
        uint256 _quantity,
        uint8 _paymentType,
        uint256 _correlationId
    );

    event LogTokenContractSet(address _newTokenContract, address _triggeredBy);

    /**
     * @notice Acts as a modifier, but it's cheaper. Checking if a non-zero address is provided, otherwise reverts.
     */
    function notZeroAddress(address tokenAddress) private pure {
        require(tokenAddress != address(0), "0_A"); //zero address
    }

    /**
     * @notice Acts as a modifier, but it's cheaper. The only caller must be tokensContractAddress, otherwise reverts.
     */
    function onlyTokensContract() private view {
        require(msg.sender == tokensContractAddress, "UN_TK"); // Unauthorized token address
    }

    /**
     * @notice Acts as a modifier, but it's cheaper. Replacement of onlyOwner modifier. If the caller is not the owner of the contract, reverts.
     */
    function onlyRouterOwner() internal view {
        require(owner() == _msgSender(), "NOTO"); //not owner
    }

    /**
     * @notice Acts as a modifier, but it's cheaper. Checks whether provided value corresponds to the limits in the FundLimitsOracle.
     * @param value the specified value is per voucher set level. E.g. deposit * qty should not be greater or equal to the limit in the FundLimitsOracle (ETH).
     */
    function notAboveETHLimit(uint256 value) internal view {
        require(
            value <= IFundLimitsOracle(fundLimitsOracle).getETHLimit(),
            "AB_L" // above limit
        );
    }

    /**
     * @notice Acts as a modifier, but it's cheaper. Checks whether provided value corresponds to the limits in the FundLimitsOracle.
     * @param _tokenAddress the token address which, we are getting the limits for.
     * @param value the specified value is per voucher set level. E.g. deposit * qty should not be greater or equal to the limit in the FundLimitsOracle (ETH).
     */
    function notAboveTokenLimit(address _tokenAddress, uint256 value)
        internal
        view
    {
        require(
            value <=
                IFundLimitsOracle(fundLimitsOracle).getTokenLimit(
                    _tokenAddress
                ),
            "AB_L" //above limit
        );
    }

    constructor(
        address _voucherKernel,
        address _tokensContractAddress,
        address _fundLimitsOracle,
        address _cashierAddress
    ) {
        notZeroAddress(_voucherKernel);
        notZeroAddress(_tokensContractAddress);
        notZeroAddress(_fundLimitsOracle);
        notZeroAddress(_cashierAddress);

        voucherKernel = _voucherKernel;
        tokensContractAddress = _tokensContractAddress;
        fundLimitsOracle = _fundLimitsOracle;
        cashierAddress = _cashierAddress;
    }

    /**
     * @notice Pause the Cashier && the Voucher Kernel contracts in case of emergency.
     * All functions related to creating new batch, requestVoucher or withdraw will be paused, hence cannot be executed.
     * There is special function for withdrawing funds if contract is paused.
     */
    function pause() external override {
        onlyRouterOwner();
        _pause();
        IVoucherKernel(voucherKernel).pause();
        ICashier(cashierAddress).pause();
    }

    /**
     * @notice Unpause the Cashier && the Voucher Kernel contracts.
     * All functions related to creating new batch, requestVoucher or withdraw will be unpaused.
     */
    function unpause() external override {
        onlyRouterOwner();
        require(ICashier(cashierAddress).canUnpause(), "UP_NA"); //unpaused not allowed

        _unpause();
        IVoucherKernel(voucherKernel).unpause();
        ICashier(cashierAddress).unpause();
    }

    /**
     * @notice Issuer/Seller offers promises as supply tokens and needs to escrow the deposit
        @param metadata metadata which is required for creation of a voucher
        Metadata array is used as in some scenarios we need several more params, as we need to recover 
        owner address in order to permit the contract to transfer funds on his behalf. 
        Since the params get too many, we end up in situation that the stack is too deep.
        
        uint256 _validFrom = metadata[0];
        uint256 _validTo = metadata[1];
        uint256 _price = metadata[2];
        uint256 _depositSe = metadata[3];
        uint256 _depositBu = metadata[4];
        uint256 _quantity = metadata[5];
     */
    function requestCreateOrderETHETH(uint256[] calldata metadata)
        external
        payable
        override
        whenNotPaused
    {
        notAboveETHLimit(metadata[2].mul(metadata[5]));
        notAboveETHLimit(metadata[3].mul(metadata[5]));
        notAboveETHLimit(metadata[4].mul(metadata[5]));
        require(metadata[3].mul(metadata[5]) == msg.value, "IN_FU"); //invalid funds
        //hex"54" FISSION.code(FISSION.Category.Finance, FISSION.Status.InsufficientFunds)

        uint256 tokenIdSupply =
            IVoucherKernel(voucherKernel).createTokenSupplyID(
                msg.sender,
                metadata[0],
                metadata[1],
                metadata[2],
                metadata[3],
                metadata[4],
                metadata[5]
            );

        IVoucherKernel(voucherKernel).createPaymentMethod(
            tokenIdSupply,
            ETHETH,
            address(0),
            address(0)
        );

        //record funds in escrow ...
        uint256 amount = ICashier(cashierAddress).getEscrowAmount(msg.sender);
        ICashier(cashierAddress).updateEscrowAmount(
            msg.sender,
            amount.add(msg.value)
        );

        payable(cashierAddress).sendValue(msg.value);

        emit LogOrderCreated(
            tokenIdSupply,
            msg.sender,
            metadata[5],
            ETHETH,
            correlationIds[msg.sender]++
        );
    }

    function requestCreateOrderTKNTKNWithPermit(
        address _tokenPriceAddress,
        address _tokenDepositAddress,
        uint256 _tokensSent,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256[] calldata metadata
    ) external override whenNotPaused {
        notZeroAddress(_tokenPriceAddress);
        notZeroAddress(_tokenDepositAddress);
        notAboveTokenLimit(_tokenPriceAddress, metadata[2].mul(metadata[5]));
        notAboveTokenLimit(_tokenDepositAddress, metadata[3].mul(metadata[5]));
        notAboveTokenLimit(_tokenDepositAddress, metadata[4].mul(metadata[5]));

        require(metadata[3].mul(metadata[5]) == _tokensSent, "IN_FU"); //invalid funds
        //hex"54" FISSION.code(FISSION.Category.Finance, FISSION.Status.InsufficientFunds)

        IERC20WithPermit(_tokenDepositAddress).permit(
            msg.sender,
            address(this),
            _tokensSent,
            deadline,
            v,
            r,
            s
        );

        uint256 tokenIdSupply =
            IVoucherKernel(voucherKernel).createTokenSupplyID(
                msg.sender,
                metadata[0],
                metadata[1],
                metadata[2],
                metadata[3],
                metadata[4],
                metadata[5]
            );

        IVoucherKernel(voucherKernel).createPaymentMethod(
            tokenIdSupply,
            TKNTKN,
            _tokenPriceAddress,
            _tokenDepositAddress
        );

        IERC20WithPermit(_tokenDepositAddress).transferFrom(
            msg.sender,
            address(cashierAddress),
            _tokensSent
        );

        //record funds in escrowTokens ...
        uint256 amount =
            ICashier(cashierAddress).getEscrowTokensAmount(
                _tokenDepositAddress,
                msg.sender
            );
        ICashier(cashierAddress).updateEscrowTokensAmount(
            _tokenDepositAddress,
            msg.sender,
            amount.add(_tokensSent)
        );

        emit LogOrderCreated(
            tokenIdSupply,
            msg.sender,
            metadata[5],
            TKNTKN,
            correlationIds[msg.sender]++
        );
    }

    function requestCreateOrderETHTKNWithPermit(
        address _tokenDepositAddress,
        uint256 _tokensSent,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256[] calldata metadata
    ) external override whenNotPaused {
        notZeroAddress(_tokenDepositAddress);
        notAboveETHLimit(metadata[2].mul(metadata[5]));
        notAboveTokenLimit(_tokenDepositAddress, metadata[3].mul(metadata[5]));
        notAboveTokenLimit(_tokenDepositAddress, metadata[4].mul(metadata[5]));

        require(metadata[3].mul(metadata[5]) == _tokensSent, "IN_FU"); //invalid funds
        //hex"54" FISSION.code(FISSION.Category.Finance, FISSION.Status.InsufficientFunds)

        IERC20WithPermit(_tokenDepositAddress).permit(
            msg.sender,
            address(this),
            _tokensSent,
            deadline,
            v,
            r,
            s
        );

        uint256 tokenIdSupply =
            IVoucherKernel(voucherKernel).createTokenSupplyID(
                msg.sender,
                metadata[0],
                metadata[1],
                metadata[2],
                metadata[3],
                metadata[4],
                metadata[5]
            );

        IVoucherKernel(voucherKernel).createPaymentMethod(
            tokenIdSupply,
            ETHTKN,
            address(0),
            _tokenDepositAddress
        );

        IERC20WithPermit(_tokenDepositAddress).transferFrom(
            msg.sender,
            address(cashierAddress),
            _tokensSent
        );

        //record funds in escrowTokens ...
        uint256 amount =
            ICashier(cashierAddress).getEscrowTokensAmount(
                _tokenDepositAddress,
                msg.sender
            );
        ICashier(cashierAddress).updateEscrowTokensAmount(
            _tokenDepositAddress,
            msg.sender,
            amount.add(_tokensSent)
        );

        emit LogOrderCreated(
            tokenIdSupply,
            msg.sender,
            metadata[5],
            ETHTKN,
            correlationIds[msg.sender]++
        );
    }

    function requestCreateOrderTKNETH(
        address _tokenPriceAddress,
        uint256[] calldata metadata
    ) external payable override whenNotPaused {
        notZeroAddress(_tokenPriceAddress);
        notAboveTokenLimit(_tokenPriceAddress, metadata[2].mul(metadata[5]));
        notAboveETHLimit(metadata[3].mul(metadata[5]));
        notAboveETHLimit(metadata[4].mul(metadata[5]));

        require(metadata[3].mul(metadata[5]) == msg.value, "IN_FU"); //invalid funds
        //hex"54" FISSION.code(FISSION.Category.Finance, FISSION.Status.InsufficientFunds)

        uint256 tokenIdSupply =
            IVoucherKernel(voucherKernel).createTokenSupplyID(
                msg.sender,
                metadata[0],
                metadata[1],
                metadata[2],
                metadata[3],
                metadata[4],
                metadata[5]
            );
        IVoucherKernel(voucherKernel).createPaymentMethod(
            tokenIdSupply,
            TKNETH,
            _tokenPriceAddress,
            address(0)
        );

        uint256 amount = ICashier(cashierAddress).getEscrowAmount(msg.sender);
        ICashier(cashierAddress).updateEscrowAmount(
            msg.sender,
            amount.add(msg.value)
        );

        payable(cashierAddress).sendValue(msg.value);

        emit LogOrderCreated(
            tokenIdSupply,
            msg.sender,
            metadata[5],
            TKNETH,
            correlationIds[msg.sender]++
        );
    }

    /**
     * @notice Consumer requests/buys a voucher by filling an order and receiving a Voucher Token in return
     * @param _tokenIdSupply    ID of the supply token
     * @param _issuer           Address of the issuer of the supply token
     */
    function requestVoucherETHETH(uint256 _tokenIdSupply, address _issuer)
        external
        payable
        override
        nonReentrant
        whenNotPaused
    {
        uint256 weiReceived = msg.value;

        //checks
        (uint256 price, , uint256 depositBu) =
            IVoucherKernel(voucherKernel).getOrderCosts(_tokenIdSupply);
        require(price.add(depositBu) == weiReceived, "IN_FU"); //invalid funds
        //hex"54" FISSION.code(FISSION.Category.Finance, FISSION.Status.InsufficientFunds)

        IVoucherKernel(voucherKernel).fillOrder(
            _tokenIdSupply,
            _issuer,
            msg.sender,
            correlationIds[msg.sender]++
        );

        //record funds in escrow ...
        uint256 amount = ICashier(cashierAddress).getEscrowAmount(msg.sender);
        ICashier(cashierAddress).updateEscrowAmount(
            msg.sender,
            amount.add(weiReceived)
        );

        payable(cashierAddress).sendValue(msg.value);
    }

    function requestVoucherTKNTKNWithPermit(
        uint256 _tokenIdSupply,
        address _issuer,
        uint256 _tokensSent,
        uint256 deadline,
        uint8 vPrice,
        bytes32 rPrice,
        bytes32 sPrice, // tokenPrice
        uint8 vDeposit,
        bytes32 rDeposit,
        bytes32 sDeposit // tokenDeposits
    ) external override nonReentrant whenNotPaused {

        (uint256 price, uint256 depositBu) =
            IVoucherKernel(voucherKernel).getBuyerOrderCosts(_tokenIdSupply);
        require(_tokensSent.sub(depositBu) == price, "IN_FU"); //invalid funds

        address tokenPriceAddress =
            IVoucherKernel(voucherKernel).getVoucherPriceToken(_tokenIdSupply);
        address tokenDepositAddress =
            IVoucherKernel(voucherKernel).getVoucherDepositToken(
                _tokenIdSupply
            );

        IERC20WithPermit(tokenPriceAddress).permit(
            msg.sender,
            address(this),
            price,
            deadline,
            vPrice,
            rPrice,
            sPrice
        );
        IERC20WithPermit(tokenDepositAddress).permit(
            msg.sender,
            address(this),
            depositBu,
            deadline,
            vDeposit,
            rDeposit,
            sDeposit
        );

        IVoucherKernel(voucherKernel).fillOrder(
            _tokenIdSupply,
            _issuer,
            msg.sender,
            correlationIds[msg.sender]++
        );

        IERC20WithPermit(tokenPriceAddress).transferFrom(
            msg.sender,
            address(cashierAddress),
            price
        );
        IERC20WithPermit(tokenDepositAddress).transferFrom(
            msg.sender,
            address(cashierAddress),
            depositBu
        );

        //record funds in escrowTokens for the Price token...
        uint256 amount =
            ICashier(cashierAddress).getEscrowTokensAmount(
                tokenPriceAddress,
                msg.sender
            );
        ICashier(cashierAddress).updateEscrowTokensAmount(
            tokenPriceAddress,
            msg.sender,
            amount.add(price)
        );

        //record funds in escrowTokens for the Deposit token...
        amount = ICashier(cashierAddress).getEscrowTokensAmount(
            tokenDepositAddress,
            msg.sender
        );
        ICashier(cashierAddress).updateEscrowTokensAmount(
            tokenDepositAddress,
            msg.sender,
            amount.add(depositBu)
        );
    }

    function requestVoucherTKNTKNSameWithPermit(
        uint256 _tokenIdSupply,
        address _issuer,
        uint256 _tokensSent,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override nonReentrant whenNotPaused {

        (uint256 price, uint256 depositBu) =
            IVoucherKernel(voucherKernel).getBuyerOrderCosts(_tokenIdSupply);
        require(_tokensSent.sub(depositBu) == price, "IN_FU"); //invalid funds

        address tokenPriceAddress =
            IVoucherKernel(voucherKernel).getVoucherPriceToken(_tokenIdSupply);
        address tokenDepositAddress =
            IVoucherKernel(voucherKernel).getVoucherDepositToken(
                _tokenIdSupply
            );

        require(tokenPriceAddress == tokenDepositAddress, "IN_C"); //invalid caller

        // If tokenPriceAddress && tokenPriceAddress are the same
        // practically it's not of importance to each we are sending the funds
        IERC20WithPermit(tokenPriceAddress).permit(
            msg.sender,
            address(this),
            _tokensSent,
            deadline,
            v,
            r,
            s
        );

        IVoucherKernel(voucherKernel).fillOrder(
            _tokenIdSupply,
            _issuer,
            msg.sender,
            correlationIds[msg.sender]++
        );

        IERC20WithPermit(tokenPriceAddress).transferFrom(
            msg.sender,
            address(cashierAddress),
            _tokensSent
        );

        //record funds in escrowTokens ...
        uint256 amount =
            ICashier(cashierAddress).getEscrowTokensAmount(
                tokenPriceAddress,
                msg.sender
            );
        ICashier(cashierAddress).updateEscrowTokensAmount(
            tokenPriceAddress,
            msg.sender,
            amount.add(_tokensSent)
        );
    }

    function requestVoucherETHTKNWithPermit(
        uint256 _tokenIdSupply,
        address _issuer,
        uint256 _tokensDeposit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable override nonReentrant whenNotPaused {

        (uint256 price, uint256 depositBu) =
            IVoucherKernel(voucherKernel).getBuyerOrderCosts(_tokenIdSupply);
        require(price == msg.value, "IN_P"); //invalid price
        //hex"54" FISSION.code(FISSION.Category.Finance, FISSION.Status.InsufficientFunds)
        require(depositBu == _tokensDeposit, "IN_D"); // invalid deposit
        //hex"54" FISSION.code(FISSION.Category.Finance, FISSION.Status.InsufficientFunds)

        address tokenDepositAddress =
            IVoucherKernel(voucherKernel).getVoucherDepositToken(
                _tokenIdSupply
            );
        IERC20WithPermit(tokenDepositAddress).permit(
            msg.sender,
            address(this),
            _tokensDeposit,
            deadline,
            v,
            r,
            s
        );

        IVoucherKernel(voucherKernel).fillOrder(
            _tokenIdSupply,
            _issuer,
            msg.sender,
            correlationIds[msg.sender]++
        );

        IERC20WithPermit(tokenDepositAddress).transferFrom(
            msg.sender,
            address(cashierAddress),
            _tokensDeposit
        );

        //record funds in escrow ...
        uint256 amount = ICashier(cashierAddress).getEscrowAmount(msg.sender);
        ICashier(cashierAddress).updateEscrowAmount(
            msg.sender,
            amount.add(msg.value)
        );

        //record funds in escrowTokens ...
        amount = ICashier(cashierAddress).getEscrowTokensAmount(
            tokenDepositAddress,
            msg.sender
        );
        ICashier(cashierAddress).updateEscrowTokensAmount(
            tokenDepositAddress,
            msg.sender,
            amount.add(_tokensDeposit)
        );

        payable(cashierAddress).sendValue(msg.value);
    }

    function requestVoucherTKNETHWithPermit(
        uint256 _tokenIdSupply,
        address _issuer,
        uint256 _tokensPrice,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable override nonReentrant whenNotPaused {

        (uint256 price, uint256 depositBu) =
            IVoucherKernel(voucherKernel).getBuyerOrderCosts(_tokenIdSupply);
        require(price == _tokensPrice, "IN_P"); //invalid price
        //hex"54" FISSION.code(FISSION.Category.Finance, FISSION.Status.InsufficientFunds)
        require(depositBu == msg.value, "IN_DE"); // invalid deposit
        //hex"54" FISSION.code(FISSION.Category.Finance, FISSION.Status.InsufficientFunds)

        address tokenPriceAddress =
            IVoucherKernel(voucherKernel).getVoucherPriceToken(_tokenIdSupply);
        IERC20WithPermit(tokenPriceAddress).permit(
            msg.sender,
            address(this),
            price,
            deadline,
            v,
            r,
            s
        );

        IVoucherKernel(voucherKernel).fillOrder(
            _tokenIdSupply,
            _issuer,
            msg.sender,
            correlationIds[msg.sender]++
        );

        IERC20WithPermit(tokenPriceAddress).transferFrom(
            msg.sender,
            address(cashierAddress),
            price
        );

        //record funds in escrow ...
        uint256 amount = ICashier(cashierAddress).getEscrowAmount(msg.sender);
        ICashier(cashierAddress).updateEscrowAmount(
            msg.sender,
            amount.add(msg.value)
        );

        //record funds in escrowTokens ...
        amount = ICashier(cashierAddress).getEscrowTokensAmount(
            tokenPriceAddress,
            msg.sender
        );
        ICashier(cashierAddress).updateEscrowTokensAmount(
            tokenPriceAddress,
            msg.sender,
            amount.add(price)
        );

        payable(cashierAddress).sendValue(msg.value);
    }

    /**
     * @notice Seller burns the remaining supply in case it's no longer in exchange and withdrawal of the locked deposits for them are being sent back.
     * @param _tokenIdSupply an ID of a supply token (ERC-1155) which will be burned and deposits will be returned for
     */
    function requestCancelOrFaultVoucherSet(uint256 _tokenIdSupply)
        external
        override
        nonReentrant
        whenNotPaused
    {
        uint256 _burnedSupplyQty =
            IVoucherKernel(voucherKernel).cancelOrFaultVoucherSet(
                _tokenIdSupply,
                msg.sender
            );
        ICashier(cashierAddress).withdrawDepositsSe(
            _tokenIdSupply,
            _burnedSupplyQty,
            msg.sender
        );

        correlationIds[msg.sender]++;
    }

    /**
     * @notice Redemption of the vouchers promise
     * @param _tokenIdVoucher   ID of the voucher
     */
    function redeem(uint256 _tokenIdVoucher) external override {
        IVoucherKernel(voucherKernel).redeem(_tokenIdVoucher, msg.sender);
    }

    /**
     * @notice Refunding a voucher
     * @param _tokenIdVoucher   ID of the voucher
     */
    function refund(uint256 _tokenIdVoucher) external override {
        IVoucherKernel(voucherKernel).refund(_tokenIdVoucher, msg.sender);
    }

    /**
     * @notice Issue a complain for a voucher
     * @param _tokenIdVoucher   ID of the voucher
     */
    function complain(uint256 _tokenIdVoucher) external override {
        IVoucherKernel(voucherKernel).complain(_tokenIdVoucher, msg.sender);
    }

    /**
     * @notice Cancel/Fault transaction by the Seller, admitting to a fault or backing out of the deal
     * @param _tokenIdVoucher   ID of the voucher
     */
    function cancelOrFault(uint256 _tokenIdVoucher) external override {
        IVoucherKernel(voucherKernel).cancelOrFault(
            _tokenIdVoucher,
            msg.sender
        );
    }

    /**
     * @notice Hook which will be triggered when a _tokenIdVoucher will be transferred. Escrow funds should be allocated to the new owner.
     * @param _from prev owner of the _tokenIdVoucher
     * @param _to next owner of the _tokenIdVoucher
     * @param _tokenIdVoucher _tokenIdVoucher that has been transferred
     */
    function _onERC721Transfer(
        address _from,
        address _to,
        uint256 _tokenIdVoucher
    ) external override {
        onlyTokensContract();
        uint256 tokenSupplyId =
            IVoucherKernel(voucherKernel).getIdSupplyFromVoucher(
                _tokenIdVoucher
            );
        uint8 paymentType =
            IVoucherKernel(voucherKernel).getVoucherPaymentMethod(
                tokenSupplyId
            );

        uint256 amount;
        address tokenAddress;

        (uint256 price, uint256 depositBu) =
            IVoucherKernel(voucherKernel).getBuyerOrderCosts(tokenSupplyId);

        if (paymentType == ETHETH) {
            uint256 totalAmount = price.add(depositBu);

            amount = ICashier(cashierAddress).getEscrowAmount(_from);
            ICashier(cashierAddress).updateEscrowAmount(
                _from,
                amount.sub(totalAmount)
            );

            amount = ICashier(cashierAddress).getEscrowAmount(_to);
            ICashier(cashierAddress).updateEscrowAmount(
                _to,
                amount.add(totalAmount)
            );
        }

        if (paymentType == ETHTKN) {
            amount = ICashier(cashierAddress).getEscrowAmount(_from);
            ICashier(cashierAddress).updateEscrowAmount(
                _from,
                amount.sub(price)
            );

            amount = ICashier(cashierAddress).getEscrowAmount(_to);
            ICashier(cashierAddress).updateEscrowAmount(_to, amount.add(price));

            tokenAddress = IVoucherKernel(voucherKernel).getVoucherDepositToken(
                tokenSupplyId
            );

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenAddress,
                _from
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenAddress,
                _from,
                amount.sub(depositBu)
            );

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenAddress,
                _to
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenAddress,
                _to,
                amount.add(depositBu)
            );
        }

        if (paymentType == TKNETH) {
            tokenAddress = IVoucherKernel(voucherKernel).getVoucherPriceToken(
                tokenSupplyId
            );

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenAddress,
                _from
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenAddress,
                _from,
                amount.sub(price)
            );

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenAddress,
                _to
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenAddress,
                _to,
                amount.add(price)
            );

            amount = ICashier(cashierAddress).getEscrowAmount(_from);
            ICashier(cashierAddress).updateEscrowAmount(
                _from,
                amount.sub(depositBu)
            );

            amount = ICashier(cashierAddress).getEscrowAmount(_to);
            ICashier(cashierAddress).updateEscrowAmount(
                _to,
                amount.add(depositBu)
            );
        }

        if (paymentType == TKNTKN) {
            tokenAddress = IVoucherKernel(voucherKernel).getVoucherPriceToken(
                tokenSupplyId
            );

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenAddress,
                _from
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenAddress,
                _from,
                amount.sub(price)
            );

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenAddress,
                _to
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenAddress,
                _to,
                amount.add(price)
            );

            tokenAddress = IVoucherKernel(voucherKernel).getVoucherDepositToken(
                tokenSupplyId
            );

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenAddress,
                _from
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenAddress,
                _from,
                amount.sub(depositBu)
            );

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenAddress,
                _to
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenAddress,
                _to,
                amount.add(depositBu)
            );
        }

        correlationIds[_to]++;
    }

    /**
     * @notice Pre-validation when a transfer from the the Tokens contract is triggered. Only the whole supply is allowed for transfer, otherwise reverts.
     * @param _from owner of the _tokenSupplyId
     * @param _tokenSupplyId _tokenSupplyId which will be validated
     * @param _value qty which is desired to be transferred
     */
    function _beforeERC1155Transfer(
        address _from,
        uint256 _tokenSupplyId,
        uint256 _value
    ) external view override {
        onlyTokensContract();
        uint256 _tokenSupplyQty =
            IVoucherKernel(voucherKernel).getRemQtyForSupply(
                _tokenSupplyId,
                _from
            );
        require(_tokenSupplyQty == _value, "IN_QTY"); //invalid qty
    }

    /**
     * @notice After the transfer happens the _tokenSupplyId should be updated in the promise. Escrow funds for the seller's deposits (If in ETH) should be allocated to the new owner as well.
     * @param _from prev owner of the _tokenSupplyId
     * @param _to nex owner of the _tokenSupplyId
     * @param _tokenSupplyId _tokenSupplyId for transfer
     * @param _value qty which has been transferred
     */
    function _onERC1155Transfer(
        address _from,
        address _to,
        uint256 _tokenSupplyId,
        uint256 _value
    ) external override {
        onlyTokensContract();
        uint8 paymentType =
            IVoucherKernel(voucherKernel).getVoucherPaymentMethod(
                _tokenSupplyId
            );

        uint256 depositSe;
        uint256 totalAmount;
        uint256 amount;

        if (paymentType == ETHETH || paymentType == TKNETH) {
            depositSe = IVoucherKernel(voucherKernel).getSellerDeposit(
                _tokenSupplyId
            );
            totalAmount = depositSe.mul(_value);

            amount = ICashier(cashierAddress).getEscrowAmount(_from);
            ICashier(cashierAddress).updateEscrowAmount(
                _from,
                amount.sub(totalAmount)
            );

            amount = ICashier(cashierAddress).getEscrowAmount(_to);
            ICashier(cashierAddress).updateEscrowAmount(
                _to,
                amount.add(totalAmount)
            );
        }

        if (paymentType == ETHTKN || paymentType == TKNTKN) {
            address tokenDepositAddress =
                IVoucherKernel(voucherKernel).getVoucherDepositToken(
                    _tokenSupplyId
                );

            depositSe = IVoucherKernel(voucherKernel).getSellerDeposit(
                _tokenSupplyId
            );
            totalAmount = depositSe.mul(_value);

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenDepositAddress,
                _from
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenDepositAddress,
                _from,
                amount.sub(totalAmount)
            );

            amount = ICashier(cashierAddress).getEscrowTokensAmount(
                tokenDepositAddress,
                _to
            );
            ICashier(cashierAddress).updateEscrowTokensAmount(
                tokenDepositAddress,
                _to,
                amount.add(totalAmount)
            );
        }

        IVoucherKernel(voucherKernel).setSupplyHolderOnTransfer(
            _tokenSupplyId,
            _to
        );

        correlationIds[_to]++;
    }

    // // // // // // // //
    // UTILS
    // // // // // // // //

    /**
     * @notice Set the address of the ERC1155ERC721 contract
     * @param _tokensContractAddress   The address of the ERC1155ERC721 contract
     */
    function setTokenContractAddress(address _tokensContractAddress)
        external
        override
    {
        onlyRouterOwner();
        notZeroAddress(_tokensContractAddress);
        tokensContractAddress = _tokensContractAddress;
        emit LogTokenContractSet(_tokensContractAddress, msg.sender);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

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

    constructor () {
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

pragma solidity ^0.7.0;

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

pragma solidity ^0.7.0;

import "../utils/Context.sol";
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
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
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
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "./Context.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
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
    constructor () {
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
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

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

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

interface IVoucherKernel {
    /**
     * @notice Pause the process of interaction with voucherID's (ERC-721), in case of emergency.
     * Only Cashier contract is in control of this function.
     */
    function pause() external;

    /**
     * @notice Unpause the process of interaction with voucherID's (ERC-721).
     * Only Cashier contract is in control of this function.
     */
    function unpause() external;

    /**
     * @notice Creating a new promise for goods or services.
     * Can be reused, e.g. for making different batches of these (but not in prototype).
     * @param _seller      seller of the promise
     * @param _validFrom   Start of valid period
     * @param _validTo     End of valid period
     * @param _price       Price (payment amount)
     * @param _depositSe   Seller's deposit
     * @param _depositBu   Buyer's deposit
     */
    function createTokenSupplyID(
        address _seller,
        uint256 _validFrom,
        uint256 _validTo,
        uint256 _price,
        uint256 _depositSe,
        uint256 _depositBu,
        uint256 _quantity
    ) external returns (uint256);

    /**
     * @notice Creates a Payment method struct recording the details on how the seller requires to receive Price and Deposits for a certain Voucher Set.
     * @param _tokenIdSupply     _tokenIdSupply of the voucher set this is related to
     * @param _paymentMethod  might be ETHETH, ETHTKN, TKNETH or TKNTKN
     * @param _tokenPrice   token address which will hold the funds for the price of the voucher
     * @param _tokenDeposits   token address which will hold the funds for the deposits of the voucher
     */
    function createPaymentMethod(
        uint256 _tokenIdSupply,
        uint8 _paymentMethod,
        address _tokenPrice,
        address _tokenDeposits
    ) external;

    /**
     * @notice Mark voucher token that the payment was released
     * @param _tokenIdVoucher   ID of the voucher token
     */
    function setPaymentReleased(uint256 _tokenIdVoucher) external;

    /**
     * @notice Mark voucher token that the deposits were released
     * @param _tokenIdVoucher   ID of the voucher token
     */
    function setDepositsReleased(uint256 _tokenIdVoucher) external;

    /**
     * @notice Extract a standard non-fungible tokens ERC-721 from a supply stored in ERC-1155
     * @dev Token ID is derived following the same principles for both ERC-1155 and ERC-721
     * @param _issuer          The address of the token issuer
     * @param _tokenIdSupply   ID of the token type
     * @param _qty   qty that should be burned
     */
    function burnSupplyOnPause(
        address _issuer,
        uint256 _tokenIdSupply,
        uint256 _qty
    ) external;

    /**
     * @notice Redemption of the vouchers promise
     * @param _tokenIdVoucher   ID of the voucher
     * @param _msgSender owner of the voucher
     */
    function redeem(uint256 _tokenIdVoucher, address _msgSender) external;

    /**
     * @notice Refunding a voucher
     * @param _tokenIdVoucher   ID of the voucher
     * @param _msgSender owner of the voucher
     */
    function refund(uint256 _tokenIdVoucher, address _msgSender) external;

    /**
     * @notice Issue a complain for a voucher
     * @param _tokenIdVoucher   ID of the voucher
     * @param _msgSender owner of the voucher
     */
    function complain(uint256 _tokenIdVoucher, address _msgSender) external;

    /**
     * @notice Cancel/Fault transaction by the Seller, admitting to a fault or backing out of the deal
     * @param _tokenIdVoucher   ID of the voucher
     * @param _msgSender owner of the voucher set (seller)
     */
    function cancelOrFault(uint256 _tokenIdVoucher, address _msgSender)
        external;

    /**
     * @notice Cancel/Fault transaction by the Seller, cancelling the remaining uncommitted voucher set so that seller prevents buyers from committing to vouchers for items no longer in exchange.
     * @param _tokenIdSupply   ID of the voucher
     * @param _issuer   owner of the voucher
     */
    function cancelOrFaultVoucherSet(uint256 _tokenIdSupply, address _issuer)
        external
        returns (uint256);

    /**
     * @notice Fill Voucher Order, iff funds paid, then extract & mint NFT to the voucher holder
     * @param _tokenIdSupply   ID of the supply token (ERC-1155)
     * @param _issuer          Address of the token's issuer
     * @param _holder          Address of the recipient of the voucher (ERC-721)
     * @param _correlationId           ID of the current interaction with the smart contract for a specific user
     */
    function fillOrder(
        uint256 _tokenIdSupply,
        address _issuer,
        address _holder,
        uint256 _correlationId
    ) external;

    /**
     * @notice Mark voucher token as expired
     * @param _tokenIdVoucher   ID of the voucher token
     */
    function triggerExpiration(uint256 _tokenIdVoucher) external;

    /**
     * @notice Mark voucher token to the final status
     * @param _tokenIdVoucher   ID of the voucher token
     */
    function triggerFinalizeVoucher(uint256 _tokenIdVoucher) external;

    /**
     * @notice Set the address of the new holder of a _tokenIdSupply on transfer
     * @param _tokenIdSupply   _tokenIdSupply which will be transferred
     * @param _newSeller   new holder of the supply
     */
    function setSupplyHolderOnTransfer(
        uint256 _tokenIdSupply,
        address _newSeller
    ) external;

    /**
     * @notice Set the general cancelOrFault period, should be used sparingly as it has significant consequences. Here done simply for demo purposes.
     * @param _cancelFaultPeriod   the new value for cancelOrFault period (in number of seconds)
     */
    function setCancelFaultPeriod(uint256 _cancelFaultPeriod) external;

    /**
     * @notice Set the address of the Cashier contract
     * @param _cashierAddress   The address of the Cashier contract
     */
    function setCashierAddress(address _cashierAddress) external;

    /**
     * @notice Set the general complain period, should be used sparingly as it has significant consequences. Here done simply for demo purposes.
     * @param _complainPeriod   the new value for complain period (in number of seconds)
     */
    function setComplainPeriod(uint256 _complainPeriod) external;

    /**
     * @notice Get the promise ID at specific index
     * @param _idx  Index in the array of promise keys
     * @return      Promise ID
     */
    function getPromiseKey(uint256 _idx) external view returns (bytes32);

    /**
     * @notice Get the address of the token where the price for the supply is held
     * @param _tokenIdSupply   ID of the voucher token
     * @return                  Address of the token
     */
    function getVoucherPriceToken(uint256 _tokenIdSupply)
        external
        view
        returns (address);

    /**
     * @notice Get the address of the token where the deposits for the supply are held
     * @param _tokenIdSupply   ID of the voucher token
     * @return                  Address of the token
     */
    function getVoucherDepositToken(uint256 _tokenIdSupply)
        external
        view
        returns (address);

    /**
     * @notice Get Buyer costs required to make an order for a supply token
     * @param _tokenIdSupply   ID of the supply token
     * @return                  returns a tuple (Payment amount, Buyer's deposit)
     */
    function getBuyerOrderCosts(uint256 _tokenIdSupply)
        external
        view
        returns (uint256, uint256);

    /**
     * @notice Get Seller deposit
     * @param _tokenIdSupply   ID of the supply token
     * @return                  returns sellers deposit
     */
    function getSellerDeposit(uint256 _tokenIdSupply)
        external
        view
        returns (uint256);

    /**
     * @notice Get the promise ID from a voucher token
     * @param _tokenIdVoucher   ID of the voucher token
     * @return                  ID of the promise
     */
    function getIdSupplyFromVoucher(uint256 _tokenIdVoucher)
        external
        pure
        returns (uint256);

    /**
     * @notice Get the promise ID from a voucher token
     * @param _tokenIdVoucher   ID of the voucher token
     * @return                  ID of the promise
     */
    function getPromiseIdFromVoucherId(uint256 _tokenIdVoucher)
        external
        view
        returns (bytes32);

    /**
     * @notice Get all necessary funds for a supply token
     * @param _tokenIdSupply   ID of the supply token
     * @return                  returns a tuple (Payment amount, Seller's deposit, Buyer's deposit)
     */
    function getOrderCosts(uint256 _tokenIdSupply)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    /**
     * @notice Get the remaining quantity left in supply of tokens (e.g ERC-721 left in ERC-1155) of an account
     * @param _tokenSupplyId  Token supply ID
     * @param _owner    holder of the Token Supply
     * @return          remaining quantity
     */
    function getRemQtyForSupply(uint256 _tokenSupplyId, address _owner)
        external
        view
        returns (uint256);

    /**
     * @notice Get the payment method for a particular _tokenIdSupply
     * @param _tokenIdSupply   ID of the voucher supply token
     * @return                  payment method
     */
    function getVoucherPaymentMethod(uint256 _tokenIdSupply)
        external
        view
        returns (uint8);

    /**
     * @notice Get the current status of a voucher
     * @param _tokenIdVoucher   ID of the voucher token
     * @return                  Status of the voucher (via enum)
     */
    function getVoucherStatus(uint256 _tokenIdVoucher)
        external
        view
        returns (
            uint8,
            bool,
            bool
        );

    /**
     * @notice Get the holder of a supply
     * @param _tokenIdSupply        ID of a promise which is mapped to the corresponding Promise
     * @return                  Address of the holder
     */
    function getSupplyHolder(uint256 _tokenIdSupply)
        external
        view
        returns (address);

    /**
     * @notice Get the holder of a voucher
     * @param _tokenIdVoucher   ID of the voucher token
     * @return                  Address of the holder
     */
    function getVoucherHolder(uint256 _tokenIdVoucher)
        external
        view
        returns (address);

    /**
     * @notice Checks whether a voucher is in valid period for redemption (between start date and end date)
     * @param _tokenIdVoucher ID of the voucher token
     */
    function isInValidityPeriod(uint256 _tokenIdVoucher)
        external
        view
        returns (bool);

    /**
     * @notice Checks whether a voucher is in valid state to be transferred. If either payments or deposits are released, voucher could not be transferred
     * @param _tokenIdVoucher ID of the voucher token
     */
    function isVoucherTransferable(uint256 _tokenIdVoucher)
        external
        view
        returns (bool);
}

// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity 0.7.1;

interface IERC20WithPermit {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // solhint-disable-next-line func-name-mixedcase
    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

interface IFundLimitsOracle {
    /**
     * @notice Set new limit for a token. It's used while seller tries to create a voucher. The limit is determined by a voucher set. Voucher price * quantity, seller deposit * quantity, buyer deposit * qty must be below the limit.
     * @param _tokenAddress Address of the token which will be updated.
     * @param _newLimit New limit which will be set. It must comply to the decimals of the token, so the limit is set in the correct decimals.
     */
    function setTokenLimit(address _tokenAddress, uint256 _newLimit) external;

    /**
     * @notice Get the maximum allowed token limit for the specified Token.
     * @param _tokenAddress Address of the token which will be update.
     */
    function getTokenLimit(address _tokenAddress)
        external
        view
        returns (uint256);

    /**
     * @notice Set new limit for ETH. It's used while seller tries to create a voucher. The limit is determined by a voucher set. Voucher price * quantity, seller deposit * quantity, buyer deposit * qty must be below the limit.
     * @param _newLimit New limit which will be set.
     */
    function setETHLimit(uint256 _newLimit) external;

    /**
     * @notice Get the maximum allowed ETH limit to set as price of voucher, buyer deposit or seller deposit.
     */
    function getETHLimit() external view returns (uint256);
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

interface IBosonRouter {
    function pause() external;

    function unpause() external;

    /**
     * @notice Issuer/Seller offers promises as supply tokens and needs to escrow the deposit
        @param metadata metadata which is required for creation of a voucher
        Metadata array is used as in some scenarios we need several more params, as we need to recover 
        owner address in order to permit the contract to transfer funds in his behalf. 
        Since the params get too many, we end up in situation that the stack is too deep.
        
        uint256 _validFrom = metadata[0];
        uint256 _validTo = metadata[1];
        uint256 _price = metadata[2];
        uint256 _depositSe = metadata[3];
        uint256 _depositBu = metadata[4];
        uint256 _quantity = metadata[5];
     */
    function requestCreateOrderETHETH(uint256[] calldata metadata)
        external
        payable;

    function requestCreateOrderTKNTKNWithPermit(
        address _tokenPriceAddress,
        address _tokenDepositAddress,
        uint256 _tokensSent,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256[] calldata metadata
    ) external;

    function requestCreateOrderETHTKNWithPermit(
        address _tokenDepositAddress,
        uint256 _tokensSent,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256[] calldata metadata
    ) external;

    function requestCreateOrderTKNETH(
        address _tokenPriceAddress,
        uint256[] calldata metadata
    ) external payable;

    /**
     * @notice Consumer requests/buys a voucher by filling an order and receiving a Voucher Token in return
     * @param _tokenIdSupply    ID of the supply token
     * @param _issuer           Address of the issuer of the supply token
     */
    function requestVoucherETHETH(uint256 _tokenIdSupply, address _issuer)
        external
        payable;

    function requestVoucherTKNTKNWithPermit(
        uint256 _tokenIdSupply,
        address _issuer,
        uint256 _tokensSent,
        uint256 deadline,
        uint8 vPrice,
        bytes32 rPrice,
        bytes32 sPrice, // tokenPrice
        uint8 vDeposit,
        bytes32 rDeposit,
        bytes32 sDeposit // tokenDeposits
    ) external;

    function requestVoucherTKNTKNSameWithPermit(
        uint256 _tokenIdSupply,
        address _issuer,
        uint256 _tokensSent,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function requestVoucherETHTKNWithPermit(
        uint256 _tokenIdSupply,
        address _issuer,
        uint256 _tokensDeposit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;

    function requestVoucherTKNETHWithPermit(
        uint256 _tokenIdSupply,
        address _issuer,
        uint256 _tokensPrice,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable;

    /**
     * @notice Seller burns the remaining supply and withdrawal of the locked deposits for them are being sent back.
     * @param _tokenIdSupply an ID of a supply token (ERC-1155) which will be burned and deposits will be returned for
     */
    function requestCancelOrFaultVoucherSet(uint256 _tokenIdSupply) external;

    /**
     * @notice Redemption of the vouchers promise
     * @param _tokenIdVoucher   ID of the voucher
     */
    function redeem(uint256 _tokenIdVoucher) external;

    /**
     * @notice Refunding a voucher
     * @param _tokenIdVoucher   ID of the voucher
     */
    function refund(uint256 _tokenIdVoucher) external;

    /**
     * @notice Issue a complain for a voucher
     * @param _tokenIdVoucher   ID of the voucher
     */
    function complain(uint256 _tokenIdVoucher) external;

    /**
     * @notice Cancel/Fault transaction by the Seller, admitting to a fault or backing out of the deal
     * @param _tokenIdVoucher   ID of the voucher
     */
    function cancelOrFault(uint256 _tokenIdVoucher) external;

    /**
     * @notice Hook which will be triggered when a _tokenIdVoucher will be transferred. Escrow funds should be allocated to the new owner.
     * @param _from prev owner of the _tokenIdVoucher
     * @param _to next owner of the _tokenIdVoucher
     * @param _tokenIdVoucher _tokenIdVoucher that has been transferred
     */
    function _onERC721Transfer(
        address _from,
        address _to,
        uint256 _tokenIdVoucher
    ) external;

    /**
     * @notice Pre-validation when a transfer from the the Tokens contract is triggered. Only the whole supply is allowed for transfer, otherwise reverts.
     * @param _from owner of the _tokenSupplyId
     * @param _tokenSupplyId _tokenSupplyId which will be validated
     * @param _value qty which is desired to be transferred
     */
    function _beforeERC1155Transfer(
        address _from,
        uint256 _tokenSupplyId,
        uint256 _value
    ) external view;

    /**
     * @notice After the transfer happens the _tokenSupplyId should be updated in the promise. Escrow funds for the deposits (If in ETH) should be allocated to the new owner as well.
     * @param _from prev owner of the _tokenSupplyId
     * @param _to next owner of the _tokenSupplyId
     * @param _tokenSupplyId _tokenSupplyId for transfer
     * @param _value qty which has been transferred
     */
    function _onERC1155Transfer(
        address _from,
        address _to,
        uint256 _tokenSupplyId,
        uint256 _value
    ) external;

    /**
     * @notice Set the address of the ERC1155ERC721 contract
     * @param _tokensContractAddress   The address of the ERC1155ERC721 contract
     */
    function setTokenContractAddress(address _tokensContractAddress) external;
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

interface ICashier {
    /**
     * @notice Pause the Cashier && the Voucher Kernel contracts in case of emergency.
     * All functions related to creating new batch, requestVoucher or withdraw will be paused, hence cannot be executed.
     * There is special function for withdrawing funds if contract is paused.
     */
    function pause() external;

    /**
     * @notice Unpause the Cashier && the Voucher Kernel contracts.
     * All functions related to creating new batch, requestVoucher or withdraw will be unpaused.
     */
    function unpause() external;

    function canUnpause() external view returns (bool);

    /**
     * @notice Trigger withdrawals of what funds are releasable
     * The caller of this function triggers transfers to all involved entities (pool, issuer, token holder), also paying for gas.
     * @dev This function would be optimized a lot, here verbose for readability.
     * @param _tokenIdVoucher  ID of a voucher token (ERC-721) to try withdraw funds from
     */
    function withdraw(uint256 _tokenIdVoucher) external;

    /**
     * @notice External function for withdrawing deposits. Caller must be the seller of the goods, otherwise reverts.
     * @notice Seller triggers withdrawals of remaining deposits for a given supply, in case the voucher set is no longer in exchange.
     * @param _tokenIdSupply an ID of a supply token (ERC-1155) which will be burned and deposits will be returned for
     * @param _burnedQty burned quantity that the deposits should be withdrawn for
     * @param _msgSender owner of the voucher set
     */
    function withdrawDepositsSe(
        uint256 _tokenIdSupply,
        uint256 _burnedQty,
        address payable _msgSender
    ) external;

    /**
     * @notice Get the amount in escrow of an address
     * @param _account  The address of an account to query
     * @return          The balance in escrow
     */
    function getEscrowAmount(address _account) external view returns (uint256);

    /**
     * @notice Update the amount in escrow of an address with the new value, based on VoucherSet/Voucher interaction
     * @param _account  The address of an account to query
     * @param _newAmount  New amount to be set
     */
    function updateEscrowAmount(address _account, uint256 _newAmount) external;

    /**
     * @notice Update the amount in escrowTokens of an address with the new value, based on VoucherSet/Voucher interaction
     * @param _token  The address of a token to query
     * @param _account  The address of an account to query
     * @param _newAmount  New amount to be set
     */
    function updateEscrowTokensAmount(
        address _token,
        address _account,
        uint256 _newAmount
    ) external;

    /**
     * @notice Get the amount in escrow of an address
     * @param _token  The address of a token to query
     * @param _account  The address of an account to query
     * @return          The balance in escrow
     */
    function getEscrowTokensAmount(address _token, address _account)
        external
        view
        returns (uint256);

    /**
     * @notice Set the address of the BR contract
     * @param _bosonRouterAddress   The address of the Cashier contract
     */
    function setBosonRouterAddress(address _bosonRouterAddress) external;
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/IERC1155.sol";
import "./interfaces/IERC1155TokenReceiver.sol";
import "./interfaces/IERC721.sol";
import "./interfaces/IERC721TokenReceiver.sol";
import "./interfaces/IERC1155ERC721.sol";
import "./interfaces/IBosonRouter.sol";
import "./interfaces/IVoucherKernel.sol";

//preparing for ERC-1066, ERC-1444, EIP-838

/**
 * @title Multi-token contract, implementing ERC-1155 and ERC-721 hybrid
 *  Inspired by: https://github.com/pixowl/sandbox-smart-contracts
 */
contract ERC1155ERC721 is IERC1155, IERC721, IERC1155ERC721 {
    using SafeMath for uint256;
    using Address for address;

    //min security
    address public owner; //contract owner
    address public voucherKernelAddress; //address of the VoucherKernel contract
    address public bosonRouterAddress; //address of the BosonRouter contract

    //standard reqs
    //ERC-1155
    mapping(uint256 => mapping(address => uint256)) private balances; //balance of token ids of an account

    //ERC-721
    mapping(address => uint256) private balance721;
    mapping(uint256 => address) private owners721;
    mapping(uint256 => address) private operator721;

    //shared storage: ERC-1155 & ERC-721
    mapping(address => mapping(address => bool)) private operatorApprovals; //approval of accounts of an operator
    //metadata is shared, too (but ERC-1155 and ERC-721 have different metadata extension reqs)
    string internal metadataBase;
    string internal metadata1155Route;
    string internal metadata721Route;

    //ERC-1155 metadata event: URIs are defined in RFC 3986. The URI MUST point to a JSON file that conforms to the ERC-1155 Metadata URI JSON Schema.
    //not used ATM
    //event URI(string _value, uint256 indexed _id);

    event LogVoucherKernelSet(address _newVoucherKernel, address _triggeredBy);

    event LogBosonRouterSet(address _newBosonRouter, address _triggeredBy);

    modifier onlyOwner() {
        require(msg.sender == owner, "UNAUTHORIZED_O"); //hex"10" FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)
        _;
    }

    modifier onlyFromVoucherKernel() {
        require(
            voucherKernelAddress != address(0),
            "UNSPECIFIED_VOUCHERKERNEL"
        ); //hex"20" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)
        require(msg.sender == voucherKernelAddress, "UNAUTHORIZED_VK"); //hex"10" FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)
        _;
    }

    modifier notZeroAddress(address _address) {
        require(_address != address(0), "ZERO_ADDRESS");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @notice Transfers amount of _tokenId from-to addresses with safety call.
     * If _to is a smart contract, will call onERC1155Received
     * @dev ERC-1155
     * @param _from    Source address
     * @param _to      Destination address
     * @param _tokenId ID of the token
     * @param _value   Transfer amount
     * @param _data    Additional data forwarded to onERC1155Received if _to is a contract
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _value,
        bytes calldata _data
    ) external override {
        require(_to != address(0), "UNSPECIFIED_ADDRESS"); //hex"20" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)
        require(
            _from == msg.sender || operatorApprovals[_from][msg.sender] == true,
            "UNAUTHORIZED_ST"
        ); //hex"10"FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)

        IBosonRouter(bosonRouterAddress)._beforeERC1155Transfer(
            _from,
            _tokenId,
            _value
        );

        // SafeMath throws with insufficient funds or if _id is not valid (balance will be 0)
        balances[_tokenId][_from] = balances[_tokenId][_from].sub(_value);
        balances[_tokenId][_to] = _value.add(balances[_tokenId][_to]);

        IBosonRouter(bosonRouterAddress)._onERC1155Transfer(
            _from,
            _to,
            _tokenId,
            _value
        );

        emit TransferSingle(msg.sender, _from, _to, _tokenId, _value);

        //make sure the tx was accepted - in case of a revert below, the event above is reverted, too
        _doSafeTransferAcceptanceCheck(
            msg.sender,
            _from,
            _to,
            _tokenId,
            _value,
            _data
        );
    }

    /**
     * @notice Safely transfers the ownership of a given token ID to another address
     * If the target address is a contract, it must implement `onERC721Received`,
     * which is called upon a safe transfer, and return the magic value
     * `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`; otherwise,
     * the transfer is reverted.
     * Requires the msg.sender to be the owner, approved, or operator
     * @dev ERC-721
     * @param _from current owner of the token
     * @param _to address to receive the ownership of the given token ID
     * @param _tokenId uint256 ID of the token to be transferred
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    /**
     * @notice Safely transfers the ownership of a given token ID to another address
     * If the target address is a contract, it must implement `onERC721Received`
     * Requires the msg.sender to be the owner, approved, or operator
     * @dev ERC-721
     * @param _from current owner of the token
     * @param _to address to receive the ownership of the given token ID
     * @param _tokenId uint256 ID of the token to be transferred
     * @param _data bytes data to send along with a safe transfer check
     */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory _data
    ) public override {
        transferFrom(_from, _to, _tokenId);

        if (_to.isContract()) {
            require(
                ERC721TokenReceiver(_to).onERC721Received(
                    _from,
                    _to,
                    _tokenId,
                    _data
                ) == ERC721TokenReceiver(_to).onERC721Received.selector,
                "UNSUPPORTED_ERC721_RECEIVED"
            ); //hex"10" FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)
        }
    }

    /**
     * @notice Transfers the ownership of a given token ID to another address.
     * Usage of this method is discouraged, use `safeTransferFrom` whenever possible.
     * Requires the msg.sender to be the owner, approved, or operator.
     * @dev ERC-721
     * @param _from current owner of the token
     * @param _to address to receive the ownership of the given token ID
     * @param _tokenId uint256 ID of the token to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public override {
        require(
            operator721[_tokenId] == msg.sender ||
                ownerOf(_tokenId) == msg.sender,
            "NOT_OWNER_NOR_APPROVED"
        ); //hex"10" FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)

        _transferFrom(_from, _to, _tokenId);
    }

    /**
     * @notice Internal function to transfer ownership of a given token ID to another address.
     * As opposed to transferFrom, this imposes no restrictions on msg.sender.
     * @dev ERC-721
     * @param _from current owner of the token
     * @param _to address to receive the ownership of the given token ID
     * @param _tokenId uint256 ID of the token to be transferred
     */
    function _transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) internal {
        require(ownerOf(_tokenId) == _from, "UNAUTHORIZED_T"); //hex"10" FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)
        require(_to != address(0), "UNSPECIFIED_ADDRESS"); //hex"20" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)

        operator721[_tokenId] = address(0);

        balance721[_from]--;
        balance721[_to]++;

        owners721[_tokenId] = _to;

        require(IVoucherKernel(voucherKernelAddress).isVoucherTransferable(_tokenId), "FUNDS_RELEASED");

        IBosonRouter(bosonRouterAddress)._onERC721Transfer(
            _from,
            _to,
            _tokenId
        );

        emit Transfer(_from, _to, _tokenId);
    }

    /**
     * @notice Approves another address to transfer the given token ID
     * The zero address indicates there is no approved address.
     * There can only be one approved address per token at a given time.
     * Can only be called by the token owner or an approved operator.
     * @dev ERC-721
     * @param _to address to be approved for the given token ID
     * @param _tokenId uint256 ID of the token to be approved
     */
    function approve(address _to, uint256 _tokenId) public override {
        address tokenOwner = ownerOf(_tokenId);
        require(_to != tokenOwner, "REDUNDANT_CALL"); //hex"18" FISSION.code(FISSION.Category.Permission, FISSION.Status.NotApplicatableToCurrentState)

        require(
            msg.sender == tokenOwner ||
                operatorApprovals[tokenOwner][msg.sender], // isApprovedForAll(owner, msg.sender),
            "UNAUTHORIZED_A"
        ); //hex"10" FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)
        //"ERC721: approve caller is not owner nor approved for all"

        operator721[_tokenId] = _to;
        emit Approval(tokenOwner, _to, _tokenId);
    }

    /**
     * @notice Gets the approved address for a token ID, or zero if no address set
     * Reverts if the token ID does not exist.
     * @dev ERC-721
     * @param _tokenId uint256 ID of the token to query the approval of
     * @return address currently approved for the given token ID
     */
    function getApproved(uint256 _tokenId)
        public
        view
        override
        returns (address)
    {
        require(
            owners721[_tokenId] != address(0),
            "ERC721: approved query for nonexistent token"
        );

        return operator721[_tokenId];
    }

    /**
        @notice Transfers amount of _tokenId from-to addresses with safety call.
        If _to is a smart contract, will call onERC1155BatchReceived
        @dev ERC-1155
        @param _from    Source address
        @param _to      Destination address
        @param _tokenIds array of token IDs
        @param _values   array of transfer amounts
        @param _data    Additional data forwarded to onERC1155BatchReceived if _to is a contract
    */
    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _tokenIds,
        uint256[] calldata _values,
        bytes calldata _data
    ) external override {
        require(_to != address(0), "UNSPECIFIED_ADDRESS"); //hex"20" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)
        require(_tokenIds.length == _values.length, "MISMATCHED_ARRAY_LENGTHS"); //hex"28" FISSION.code(FISSION.Category.Find, FISSION.Status.Duplicate_Conflict_Collision)
        require(
            _from == msg.sender || operatorApprovals[_from][msg.sender] == true,
            "UNAUTHORIZED_SB"
        ); //hex"10" FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)

        for (uint256 i = 0; i < _tokenIds.length; ++i) {
            uint256 tokenId = _tokenIds[i];
            uint256 value = _values[i];

            IBosonRouter(bosonRouterAddress)._beforeERC1155Transfer(
                _from,
                tokenId,
                value
            );

            // SafeMath throws with insufficient funds or if _id is not valid (balance will be 0)
            balances[tokenId][_from] = balances[tokenId][_from].sub(value);
            balances[tokenId][_to] = value.add(balances[tokenId][_to]);

            IBosonRouter(bosonRouterAddress)._onERC1155Transfer(
                _from,
                _to,
                tokenId,
                value
            );
        }

        emit TransferBatch(msg.sender, _from, _to, _tokenIds, _values);

        //make sure the tx was accepted - in case of a revert below, the event above is reverted, too
        _doSafeBatchTransferAcceptanceCheck(
            msg.sender,
            _from,
            _to,
            _tokenIds,
            _values,
            _data
        );
    }

    /**
     * @notice Check successful transfer if recipient is a contract
     * @dev ERC-1155
     * @param _operator The operator of the transfer
     * @param _from     Address of sender
     * @param _to       Address of recipient
     * @param _tokenId  ID of the token
     * @param _value    Value transferred
     * @param _data     Optional data
     */
    function _doSafeTransferAcceptanceCheck(
        address _operator,
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _value,
        bytes memory _data
    ) internal {
        if (_to.isContract()) {
            require(
                ERC1155TokenReceiver(_to).onERC1155Received(
                    _operator,
                    _from,
                    _tokenId,
                    _value,
                    _data
                ) == ERC1155TokenReceiver(_to).onERC1155Received.selector,
                "NOT_SUPPORTED"
            ); //hex"10" FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)
        }
    }

    /**
     * @notice Check successful transfer if recipient is a contract
     * @dev ERC-1155
     * @param _operator The operator of the transfer
     * @param _from     Address of sender
     * @param _to       Address of recipient
     * @param _tokenIds Array of IDs of tokens
     * @param _values   Array of values transferred
     * @param _data     Optional data
     */
    function _doSafeBatchTransferAcceptanceCheck(
        address _operator,
        address _from,
        address _to,
        uint256[] memory _tokenIds,
        uint256[] memory _values,
        bytes memory _data
    ) internal {
        if (_to.isContract()) {
            require(
                ERC1155TokenReceiver(_to).onERC1155BatchReceived(
                    _operator,
                    _from,
                    _tokenIds,
                    _values,
                    _data
                ) == ERC1155TokenReceiver(_to).onERC1155BatchReceived.selector,
                "NOT_SUPPORTED"
            ); //hex"10" FISSION.code(FISSION.Category.Permission, FISSION.Status.Disallowed_Stop)
        }
    }

    /**
        @notice Get the balance of tokens of an account
        @dev ERC-1155
        @param _account The address of the token holder
        @param _tokenId ID of the token
        @return         balance
     */
    function balanceOf(address _account, uint256 _tokenId)
        external
        view
        override
        returns (uint256)
    {
        return balances[_tokenId][_account];
    }

    /// @notice Count all NFTs assigned to an owner
    /// @dev ERC-721
    /// @param _owner An address for whom to query the balance
    /// @return The number of NFTs owned by `_owner`, possibly zero
    function balanceOf(address _owner) public view override returns (uint256) {
        require(_owner != address(0), "UNSPECIFIED_ADDRESS"); //hex"20" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)

        return balance721[_owner];
    }

    /**
     * @notice Gets the owner of the specified token ID.
     * @dev ERC-721
     * @param _tokenId uint256 ID of the token to query the owner of
     * @return address currently marked as the owner of the given token ID
     */
    function ownerOf(uint256 _tokenId) public view override returns (address) {
        address tokenOwner = owners721[_tokenId];
        require(tokenOwner != address(0), "UNDEFINED_OWNER"); //hex"20" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)

        return tokenOwner;
    }

    /**
        @notice Get the balance of account-token pairs.
        @dev ERC-1155
        @param _accounts The addresses of the token holders
        @param _tokenIds IDs of the tokens
        @return         balances
     */
    function balanceOfBatch(
        address[] calldata _accounts,
        uint256[] calldata _tokenIds
    ) external view override returns (uint256[] memory) {
        require(
            _accounts.length == _tokenIds.length,
            "MISMATCHED_ARRAY_LENGTHS"
        ); //hex"28" FISSION.code(FISSION.Category.Find, FISSION.Status.Duplicate_Conflict_Collision)
        uint256[] memory batchBalances = new uint256[](_accounts.length);

        for (uint256 i = 0; i < _accounts.length; ++i) {
            batchBalances[i] = balances[_tokenIds[i]][_accounts[i]];
        }

        return batchBalances;
    }

    /**
     * @notice Approves or unapproves the operator.
     * will revert if the caller attempts to approve itself as it is redundant
     * @dev ERC-1155 & ERC-721
     * @param _operator to (un)approve
     * @param _approve flag to set or unset
     */
    function setApprovalForAll(address _operator, bool _approve)
        external
        override(IERC1155, IERC721)
    {
        require(msg.sender != _operator, "REDUNDANT_CALL"); //hex"18" FISSION.code(FISSION.Category.Permission, FISSION.Status.NotApplicatableToCurrentState)
        operatorApprovals[msg.sender][_operator] = _approve;
        emit ApprovalForAll(msg.sender, _operator, _approve);
    }

    /**
        @notice Gets approval status of an operator for a given account.
        @dev ERC-1155 & ERC-721
        @param _account   token holder
        @param _operator  operator to check
        @return           True if the operator is approved, false if not
    */
    function isApprovedForAll(address _account, address _operator)
        public
        view
        override(IERC1155, IERC721)
        returns (bool)
    {
        return operatorApprovals[_account][_operator];
    }

    /**
     * @notice Returns true if this contract implements the interface defined by _interfaceId_.
     * This function call must use less than 30 000 gas. ATM not enforced.
     */
    function supportsInterface(bytes4 _interfaceId)
        external
        pure
        override
        returns (bool)
    {
        return
            //check matching against ERC-165 identifiers
            _interfaceId == 0x01ffc9a7 || //ERC-165
            _interfaceId == 0xd9b67a26 || //ERC-1155
            _interfaceId == 0x80ac58cd || //ERC-721
            _interfaceId == 0x5b5e139f || //ERC-721 metadata extension
            _interfaceId == 0x0e89341c; //ERC-1155 metadata extension
    }

    // // // // // // // //
    // STANDARD - UTILS
    // // // // // // // //
    /**
     * @notice Mint an amount of a desired token
     * Currently no restrictions as to who is allowed to mint - so, it is public.
     * @dev ERC-1155
     * @param _to       owner of the minted token
     * @param _tokenId  ID of the token to be minted
     * @param _value    Amount of the token to be minted
     * @param _data     Additional data forwarded to onERC1155BatchReceived if _to is a contract
     */
    function mint(
        address _to,
        uint256 _tokenId,
        uint256 _value,
        bytes memory _data
    ) public override onlyFromVoucherKernel {
        _mint(_to, _tokenId, _value, _data);
    }

    /**
     * @notice Internal function to mint an amount of a desired token
     * @dev ERC-1155
     * @param _to       owner of the minted token
     * @param _tokenId  ID of the token to be minted
     * @param _value    Amount of the token to be minted
     * @param _data     Additional data forwarded to onERC1155BatchReceived if _to is a contract
     */
    function _mint(
        address _to,
        uint256 _tokenId,
        uint256 _value,
        bytes memory _data
    ) internal {
        require(_to != address(0), "UNSPECIFIED_ADDRESS"); //FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)

        balances[_tokenId][_to] = balances[_tokenId][_to].add(_value);
        emit TransferSingle(msg.sender, address(0), _to, _tokenId, _value);

        _doSafeTransferAcceptanceCheck(
            msg.sender,
            address(0),
            _to,
            _tokenId,
            _value,
            _data
        );
    }

    /**
     * @notice Function to mint tokens.
     * @dev ERC-721
     * @param to The address that will receive the minted tokens.
     * @param tokenId The token id to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(address to, uint256 tokenId)
        public
        override
        onlyFromVoucherKernel
        returns (bool)
    {
        _mint(to, tokenId);
        return true;
    }

    /**
     * @notice Internal function to mint a new token.
     * Reverts if the given token ID already exists.
     * @dev ERC-721
     * @param _to The address that will own the minted token
     * @param _tokenId uint256 ID of the token to be minted
     */
    function _mint(address _to, uint256 _tokenId) internal {
        require(_to != address(0), "UNSPECIFIED_ADDRESS"); //hex"20" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)
        require(
            owners721[_tokenId] == address(0),
            "ERC721: token already minted"
        );

        owners721[_tokenId] = _to;
        balance721[_to]++;

        emit Transfer(address(0), _to, _tokenId);
    }

    /**
     * @notice Batch minting of tokens
     * Currently no restrictions as to who is allowed to mint - so, it is public.
     * @dev ERC-1155
     * @param _to The address that will own the minted token
     * @param _tokenIds IDs of the tokens to be minted
     * @param _values Amounts of the tokens to be minted
     * @param _data Additional data forwarded to onERC1155BatchReceived if _to is a contract
     */
    function mintBatch(
        address _to,
        uint256[] memory _tokenIds,
        uint256[] memory _values,
        bytes memory _data
    ) public onlyFromVoucherKernel {
        //require approved minter

        _mintBatch(_to, _tokenIds, _values, _data);
    }

    /**
     * @notice Internal function for batch minting of tokens\
     * @dev ERC-1155
     * @param _to The address that will own the minted token
     * @param _tokenIds IDs of the tokens to be minted
     * @param _values Amounts of the tokens to be minted
     * @param _data Additional data forwarded to onERC1155BatchReceived if _to is a contract
     */
    function _mintBatch(
        address _to,
        uint256[] memory _tokenIds,
        uint256[] memory _values,
        bytes memory _data
    ) internal {
        require(_to != address(0), "UNSPECIFIED_ADDRESS"); //hex"20" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)
        require(_tokenIds.length == _values.length, "MISMATCHED_ARRAY_LENGTHS"); //hex"28" FISSION.code(FISSION.Category.Find, FISSION.Status.Duplicate_Conflict_Collision)

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            balances[_tokenIds[i]][_to] = _values[i].add(
                balances[_tokenIds[i]][_to]
            );
        }

        emit TransferBatch(msg.sender, address(0), _to, _tokenIds, _values);

        _doSafeBatchTransferAcceptanceCheck(
            msg.sender,
            address(0),
            _to,
            _tokenIds,
            _values,
            _data
        );
    }

    /**
     * @notice Burn an amount of tokens with the given ID
     * @dev ERC-1155
     * @param _account  Account which owns the token
     * @param _tokenId  ID of the token
     * @param _value    Amount of the token
     */
    function burn(
        address _account,
        uint256 _tokenId,
        uint256 _value
    ) public override onlyFromVoucherKernel {
        _burn(_account, _tokenId, _value);
    }

    /**
     * @notice Burn an amount of tokens with the given ID
     * @dev ERC-1155
     * @param _account  Account which owns the token
     * @param _tokenId  ID of the token
     * @param _value    Amount of the token
     */
    function _burn(
        address _account,
        uint256 _tokenId,
        uint256 _value
    ) internal {
        require(_account != address(0), "UNSPECIFIED_ADDRESS"); //"UNSPECIFIED_ADDRESS" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)

        balances[_tokenId][_account] = balances[_tokenId][_account].sub(_value);
        emit TransferSingle(msg.sender, _account, address(0), _tokenId, _value);
    }

    /* Burning ERC-721 is not allowed, as a voucher (being an ERC-721 token) has a final state and shouldn't be destructed. */

    /**
     * @notice Batch burn an amounts of tokens
     * @dev ERC-1155
     * @param _account Account which owns the token
     * @param _tokenIds IDs of the tokens
     * @param _values Amounts of the tokens
     */
    function burnBatch(
        address _account,
        uint256[] memory _tokenIds,
        uint256[] memory _values
    ) public onlyFromVoucherKernel {
        _burnBatch(_account, _tokenIds, _values);
    }

    /**
     * @notice Internal function to batch burn an amounts of tokens
     * @dev ERC-1155
     * @param _account Account which owns the token
     * @param _tokenIds IDs of the tokens
     * @param _values Amounts of the tokens
     */
    function _burnBatch(
        address _account,
        uint256[] memory _tokenIds,
        uint256[] memory _values
    ) internal {
        require(_account != address(0), "UNSPECIFIED_ADDRESS"); //hex"20" FISSION.code(FISSION.Category.Find, FISSION.Status.NotFound_Unequal_OutOfRange)
        require(_tokenIds.length == _values.length, "MISMATCHED_ARRAY_LENGTHS"); //hex"28" FISSION.code(FISSION.Category.Find, FISSION.Status.Duplicate_Conflict_Collision)

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            balances[_tokenIds[i]][_account] = balances[_tokenIds[i]][_account]
                .sub(_values[i]);
        }

        emit TransferBatch(
            msg.sender,
            _account,
            address(0),
            _tokenIds,
            _values
        );
    }

    // // // // // // // //
    // METADATA EXTENSIONS
    // // // // // // // //

    /**
     * @notice Setting the URL prefix for tokens metadata
     * @param _newBase   New prefix to be used
     */
    function _setMetadataBase(string memory _newBase) public onlyOwner {
        metadataBase = _newBase;
    }

    /**
     * @notice Setting the URL route for ERC1155 tokens metadata
     * @param _newRoute   New route to be used
     */
    function _set1155Route(string memory _newRoute) public onlyOwner {
        metadata1155Route = _newRoute;
    }

    /**
     * @notice Setting the URL route for ERC721 tokens metadata
     * @param _newRoute   New route to be used
     */
    function _set721Route(string memory _newRoute) public onlyOwner {
        metadata721Route = _newRoute;
    }

    /**
     * @notice A distinct Uniform Resource Identifier (URI) for a given token.
     * @dev ERC-1155
     * URIs are defined in RFC 3986. The URI MUST point to a JSON file that conforms to the "ERC-1155 Metadata URI JSON Schema".
     * @param _tokenId  The ID of the token
     * @return          Full URI string for metadata of the _tokenId
     */
    function uri(uint256 _tokenId) external view returns (string memory) {
        return
            string(
                abi.encodePacked(metadataBase, metadata1155Route, _uint2str(_tokenId))
            );
    }

    /**
     * @notice A descriptive name for a collection of NFTs in this contract
     * @dev ERC-721
     */
    function name() external pure returns (string memory _name) {
        return "Boson Smart Voucher";
    }

    /**
     * @notice An abbreviated name for NFTs in this contract
     * @dev ERC-721
     */
    function symbol() external pure returns (string memory _symbol) {
        return "BSV";
    }

    /**
     * @notice A distinct Uniform Resource Identifier (URI) for a given asset.
     * @dev ERC-721
     * Throws if `_tokenId` is not a valid NFT. URIs are defined in RFC 3986. The URI may point to a JSON file that conforms to the "ERC721 Metadata JSON Schema".
     * @param _tokenId  ID of the token
     */
    function tokenURI(uint256 _tokenId) external view returns (string memory) {
        require(owners721[_tokenId] != address(0), "INVALID_ID");
        return
            string(
                abi.encodePacked(metadataBase, metadata721Route, _uint2str(_tokenId))
            );
    }

    // // // // // // // //
    // UTILS
    // // // // // // // //

    /**
     * @notice Set the address of the VoucherKernel contract
     * @param _voucherKernelAddress   The address of the Voucher Kernel contract
     */
    function setVoucherKernelAddress(address _voucherKernelAddress)
        external
        onlyOwner
        notZeroAddress(_voucherKernelAddress)
    {
        voucherKernelAddress = _voucherKernelAddress;

        emit LogVoucherKernelSet(_voucherKernelAddress, msg.sender);
    }

    /**
     * @notice Set the address of the Boson Router contract
     * @param _bosonRouterAddress   The Boson Router  contract
     */
    function setBosonRouterAddress(address _bosonRouterAddress)
        external
        onlyOwner
        notZeroAddress(_bosonRouterAddress)
    {
        bosonRouterAddress = _bosonRouterAddress;
        emit LogBosonRouterSet(_bosonRouterAddress, msg.sender);
    }

    /**
     * @notice Convert UINT to string
     *  Thank you, Oraclize (aka Provable)!
     *      https://github.com/provable-things/ethereum-api/blob/master/provableAPI_0.5.sol
     * @param _i    uint parameter
     */
    function _uint2str(uint256 _i)
        internal
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;
        while (_i != 0) {
            bstr[k--] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

/**
 * @title Utility contract to enable access to common structures
 */
contract UsingHelpers {
    uint8 internal constant ONE = 1;
    uint8 internal constant IDX_COMMIT = 7;
    uint8 internal constant IDX_REDEEM = 6;
    uint8 internal constant IDX_REFUND = 5;
    uint8 internal constant IDX_EXPIRE = 4;
    uint8 internal constant IDX_COMPLAIN = 3;
    uint8 internal constant IDX_CANCEL_FAULT = 2;
    uint8 internal constant IDX_FINAL = 1;

    /*  Status of the voucher in 8 bits:
        [7:COMMITTED] [6:REDEEMED] [5:REFUNDED] [4:EXPIRED] [3:COMPLAINED] [2:CANCELORFAULT] [1:FINAL] [1:/]
    */

    // Those are the payment methods we are using throughout the system.
    // Depending on how to user choose to interact with it's funds we store the method, so we could distribute its tokens afterwise
    uint8 internal constant ETHETH = 1;
    uint8 internal constant ETHTKN = 2;
    uint8 internal constant TKNETH = 3;
    uint8 internal constant TKNTKN = 4;

    struct VoucherDetails {
        uint256 tokenIdSupply;
        uint256 tokenIdVoucher;
        address issuer;
        address holder;
        uint256 price;
        uint256 depositSe;
        uint256 depositBu;
        uint256 price2pool;
        uint256 deposit2pool;
        uint256 price2issuer;
        uint256 deposit2issuer;
        uint256 price2holder;
        uint256 deposit2holder;
        uint8 paymentMethod;
        VoucherStatus currStatus;
    }

    struct VoucherStatus {
        uint8 status;
        bool isPaymentReleased;
        bool isDepositsReleased;
        uint256 complainPeriodStart;
        uint256 cancelFaultPeriodStart;
    }

    /**
     * @notice Based on its lifecycle, voucher can have many different statuses. Checks whether a voucher is in Committed state.
     * @param _status current status of a voucher.
     */
    function isStateCommitted(uint8 _status) internal pure returns (bool) {
        return _status == setChange(0, IDX_COMMIT);
    }

    /**
     * @notice Based on its lifecycle, voucher can have many different statuses. Checks whether a voucher is in RedemptionSigned state.
     * @param _status current status of a voucher.
     */
    function isStateRedemptionSigned(uint8 _status)
        internal
        pure
        returns (bool)
    {
        return _status == setChange(setChange(0, IDX_COMMIT), IDX_REDEEM);
    }

    /**
     * @notice Based on its lifecycle, voucher can have many different statuses. Checks whether a voucher is in Refunded state.
     * @param _status current status of a voucher.
     */
    function isStateRefunded(uint8 _status) internal pure returns (bool) {
        return _status == setChange(setChange(0, IDX_COMMIT), IDX_REFUND);
    }

    /**
     * @notice Based on its lifecycle, voucher can have many different statuses. Checks whether a voucher is in Expired state.
     * @param _status current status of a voucher.
     */
    function isStateExpired(uint8 _status) internal pure returns (bool) {
        return _status == setChange(setChange(0, IDX_COMMIT), IDX_EXPIRE);
    }

    /**
     * @notice Based on its lifecycle, voucher can have many different statuses. Checks the current status a voucher is at.
     * @param _status current status of a voucher.
     * @param _idx status to compare.
     */
    function isStatus(uint8 _status, uint8 _idx) internal pure returns (bool) {
        return (_status >> _idx) & ONE == 1;
    }

    /**
     * @notice Set voucher status.
     * @param _status previous status.
     * @param _changeIdx next status.
     */
    function setChange(uint8 _status, uint8 _changeIdx)
        internal
        pure
        returns (uint8)
    {
        return _status | (ONE << _changeIdx);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

/**
    @title ERC-1155 Multi Token Standard
    @dev See https://eips.ethereum.org/EIPS/eip-1155
    Note: The ERC-165 identifier for this interface is 0xd9b67a26.
 */
/* is IERC165 */
interface IERC1155 {
    /**
        @dev Either `TransferSingle` or `TransferBatch` MUST emit when tokens are transferred, including zero value transfers as well as minting or burning (see "Safe Transfer Rules" section of the standard).
        The `_operator` argument MUST be the address of an account/contract that is approved to make the transfer (SHOULD be msg.sender).
        The `_from` argument MUST be the address of the holder whose balance is decreased.
        The `_to` argument MUST be the address of the recipient whose balance is increased.
        The `_id` argument MUST be the token type being transferred.
        The `_value` argument MUST be the number of tokens the holder balance is decreased by and match what the recipient balance is increased by.
        When minting/creating tokens, the `_from` argument MUST be set to `0x0` (i.e. zero address).
        When burning/destroying tokens, the `_to` argument MUST be set to `0x0` (i.e. zero address).        
    */
    event TransferSingle(
        address indexed _operator,
        address indexed _from,
        address indexed _to,
        uint256 _id,
        uint256 _value
    );

    /**
        @dev Either `TransferSingle` or `TransferBatch` MUST emit when tokens are transferred, including zero value transfers as well as minting or burning (see "Safe Transfer Rules" section of the standard).      
        The `_operator` argument MUST be the address of an account/contract that is approved to make the transfer (SHOULD be msg.sender).
        The `_from` argument MUST be the address of the holder whose balance is decreased.
        The `_to` argument MUST be the address of the recipient whose balance is increased.
        The `_ids` argument MUST be the list of tokens being transferred.
        The `_values` argument MUST be the list of number of tokens (matching the list and order of tokens specified in _ids) the holder balance is decreased by and match what the recipient balance is increased by.
        When minting/creating tokens, the `_from` argument MUST be set to `0x0` (i.e. zero address).
        When burning/destroying tokens, the `_to` argument MUST be set to `0x0` (i.e. zero address).                
    */
    event TransferBatch(
        address indexed _operator,
        address indexed _from,
        address indexed _to,
        uint256[] _ids,
        uint256[] _values
    );

    /**
        @dev MUST emit when the URI is updated for a token ID.
        URIs are defined in RFC 3986.
        The URI MUST point to a JSON file that conforms to the "ERC-1155 Metadata URI JSON Schema".
    */
    event URI(string _value, uint256 indexed _id);

    /**
        @notice Transfers `_value` amount of an `_id` from the `_from` address to the `_to` address specified (with safety call).
        @dev Caller must be approved to manage the tokens being transferred out of the `_from` account (see "Approval" section of the standard).
        MUST revert if `_to` is the zero address.
        MUST revert if balance of holder for token `_id` is lower than the `_value` sent.
        MUST revert on any other error.
        MUST emit the `TransferSingle` event to reflect the balance change (see "Safe Transfer Rules" section of the standard).
        After the above conditions are met, this function MUST check if `_to` is a smart contract (e.g. code size > 0). If so, it MUST call `onERC1155Received` on `_to` and act appropriately (see "Safe Transfer Rules" section of the standard).        
        @param _from    Source address
        @param _to      Target address
        @param _id      ID of the token type
        @param _value   Transfer amount
        @param _data    Additional data with no specified format, MUST be sent unaltered in call to `onERC1155Received` on `_to`
    */
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external;

    /**
        @notice Transfers `_values` amount(s) of `_ids` from the `_from` address to the `_to` address specified (with safety call).
        @dev Caller must be approved to manage the tokens being transferred out of the `_from` account (see "Approval" section of the standard).
        MUST revert if `_to` is the zero address.
        MUST revert if length of `_ids` is not the same as length of `_values`.
        MUST revert if any of the balance(s) of the holder(s) for token(s) in `_ids` is lower than the respective amount(s) in `_values` sent to the recipient.
        MUST revert on any other error.        
        MUST emit `TransferSingle` or `TransferBatch` event(s) such that all the balance changes are reflected (see "Safe Transfer Rules" section of the standard).
        Balance changes and events MUST follow the ordering of the arrays (_ids[0]/_values[0] before _ids[1]/_values[1], etc).
        After the above conditions for the transfer(s) in the batch are met, this function MUST check if `_to` is a smart contract (e.g. code size > 0). If so, it MUST call the relevant `ERC1155TokenReceiver` hook(s) on `_to` and act appropriately (see "Safe Transfer Rules" section of the standard).                      
        @param _from    Source address
        @param _to      Target address
        @param _ids     IDs of each token type (order and length must match _values array)
        @param _values  Transfer amounts per token type (order and length must match _ids array)
        @param _data    Additional data with no specified format, MUST be sent unaltered in call to the `ERC1155TokenReceiver` hook(s) on `_to`
    */
    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external;

    /**
        @notice Get the balance of an account's tokens.
        @param _owner  The address of the token holder
        @param _id     ID of the token
        @return        The _owner's balance of the token type requested
     */
    function balanceOf(address _owner, uint256 _id)
        external
        view
        returns (uint256);

    /**
        @notice Get the balance of multiple account/token pairs
        @param _owners The addresses of the token holders
        @param _ids    ID of the tokens
        @return        The _owner's balance of the token types requested (i.e. balance for each (owner, id) pair)
     */
    function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids)
        external
        view
        returns (uint256[] memory);

    /**
        @notice Enable or disable approval for a third party ("operator") to manage all of the caller's tokens.
        @dev MUST emit the ApprovalForAll event on success.
        @param _operator  Address to add to the set of authorized operators
        @param _approved  True if the operator is approved, false to revoke approval
    */
    function setApprovalForAll(address _operator, bool _approved) external;

    /**
        @notice Queries the approval status of an operator for a given owner.
        @param _owner     The owner of the tokens
        @param _operator  Address of authorized operator
        @return           True if the operator is approved, false if not
    */
    function isApprovedForAll(address _owner, address _operator)
        external
        view
        returns (bool);
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

/**
    Note: The ERC-165 identifier for this interface is 0x4e2312e0.
*/
interface ERC1155TokenReceiver {
    /**
        @notice Handle the receipt of a single ERC1155 token type.
        @dev An ERC1155-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeTransferFrom` after the balance has been updated.        
        This function MUST return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` (i.e. 0xf23a6e61) if it accepts the transfer.
        This function MUST revert if it rejects the transfer.
        Return of any other value than the prescribed keccak256 generated value MUST result in the transaction being reverted by the caller.
        @param _operator  The address which initiated the transfer (i.e. msg.sender)
        @param _from      The address which previously owned the token
        @param _id        The ID of the token being transferred
        @param _value     The amount of tokens being transferred
        @param _data      Additional data with no specified format
        @return           `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
    */
    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external returns (bytes4);

    /**
        @notice Handle the receipt of multiple ERC1155 token types.
        @dev An ERC1155-compliant smart contract MUST call this function on the token recipient contract, at the end of a `safeBatchTransferFrom` after the balances have been updated.        
        This function MUST return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` (i.e. 0xbc197c81) if it accepts the transfer(s).
        This function MUST revert if it rejects the transfer(s).
        Return of any other value than the prescribed keccak256 generated value MUST result in the transaction being reverted by the caller.
        @param _operator  The address which initiated the batch transfer (i.e. msg.sender)
        @param _from      The address which previously owned the token
        @param _ids       An array containing ids of each token being transferred (order and length must match _values array)
        @param _values    An array containing amounts of each token being transferred (order and length must match _ids array)
        @param _data      Additional data with no specified format
        @return           `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
    */
    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external returns (bytes4);
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

import "./IERC165.sol";

/// @title ERC-721 Non-Fungible Token Standard
/// @dev Deviated from standard: external | payable >> public
/// @dev See https://eips.ethereum.org/EIPS/eip-721
///  Note: the ERC-165 identifier for this interface is 0x80ac58cd.
abstract contract IERC721 is IERC165 {
    /// @dev This emits when ownership of any NFT changes by any mechanism.
    ///  This event emits when NFTs are created (`from` == 0) and destroyed
    ///  (`to` == 0). Exception: during contract creation, any number of NFTs
    ///  may be created and assigned without emitting Transfer. At the time of
    ///  any transfer, the approved address for that NFT (if any) is reset to none.
    event Transfer(
        address indexed _from,
        address indexed _to,
        uint256 indexed _tokenId
    );

    /// @dev This emits when the approved address for an NFT is changed or
    ///  reaffirmed. The zero address indicates there is no approved address.
    ///  When a Transfer event emits, this also indicates that the approved
    ///  address for that NFT (if any) is reset to none.
    event Approval(
        address indexed _owner,
        address indexed _approved,
        uint256 indexed _tokenId
    );

    /// @notice Count all NFTs assigned to an owner
    /// @dev NFTs assigned to the zero address are considered invalid, and this
    ///  function throws for queries about the zero address.
    /// @param _owner An address for whom to query the balance
    /// @return The number of NFTs owned by `_owner`, possibly zero
    function balanceOf(address _owner) public view virtual returns (uint256);

    /// @notice Find the owner of an NFT
    /// @dev NFTs assigned to zero address are considered invalid, and queries
    ///  about them do throw.
    /// @param _tokenId The identifier for an NFT
    /// @return The address of the owner of the NFT
    function ownerOf(uint256 _tokenId) public view virtual returns (address);

    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `_tokenId` is not a valid NFT. When transfer is complete, this function
    ///  checks if `_to` is a smart contract (code size > 0). If so, it calls
    ///  `onERC721Received` on `_to` and throws if the return value is not
    ///  `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    /// @param data Additional data with no specified format, sent in call to `_to`
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId,
        bytes memory data
    ) public virtual;

    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @dev This works identically to the other function with an extra data parameter,
    ///  except this function just sets data to "".
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public virtual;

    /// @notice Transfer ownership of an NFT -- THE CALLER IS RESPONSIBLE
    ///  TO CONFIRM THAT `_to` IS CAPABLE OF RECEIVING NFTS OR ELSE
    ///  THEY MAY BE PERMANENTLY LOST
    /// @dev Throws unless `msg.sender` is the current owner, an authorized
    ///  operator, or the approved address for this NFT. Throws if `_from` is
    ///  not the current owner. Throws if `_to` is the zero address. Throws if
    ///  `_tokenId` is not a valid NFT.
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) public virtual;

    /// @notice Change or reaffirm the approved address for an NFT
    /// @dev The zero address indicates there is no approved address.
    ///  Throws unless `msg.sender` is the current NFT owner, or an authorized
    ///  operator of the current owner.
    /// @param _approved The new approved NFT controller
    /// @param _tokenId The NFT to approve
    function approve(address _approved, uint256 _tokenId) public virtual;

    /// @notice Enable or disable approval for a third party ("operator") to manage
    ///  all of `msg.sender`'s assets
    /// @dev Emits the ApprovalForAll event. The contract MUST allow
    ///  multiple operators per owner.
    /// @param _operator Address to add to the set of authorized operators
    /// @param _approved True if the operator is approved, false to revoke approval
    function setApprovalForAll(address _operator, bool _approved)
        external
        virtual;

    /// @notice Get the approved address for a single NFT
    /// @dev Throws if `_tokenId` is not a valid NFT.
    /// @param _tokenId The NFT to find the approved address for
    /// @return The approved address for this NFT, or the zero address if there is none
    function getApproved(uint256 _tokenId)
        public
        view
        virtual
        returns (address);

    /// @notice Query if an address is an authorized operator for another address
    /// @param _owner The address that owns the NFTs
    /// @param _operator The address that acts on behalf of the owner
    /// @return True if `_operator` is an approved operator for `_owner`, false otherwise
    function isApprovedForAll(address _owner, address _operator)
        public
        view
        virtual
        returns (bool);
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

/// @dev Note: the ERC-165 identifier for this interface is 0x150b7a02.
interface ERC721TokenReceiver {
    /// @notice Handle the receipt of an NFT
    /// @dev The ERC721 smart contract calls this function on the recipient
    ///  after a `transfer`. This function MAY throw to revert and reject the
    ///  transfer. Return of other than the magic value MUST result in the
    ///  transaction being reverted.
    ///  Note: the contract address is always the message sender.
    /// @param _operator The address which called `safeTransferFrom` function
    /// @param _from The address which previously owned the token
    /// @param _tokenId The NFT identifier which is being transferred
    /// @param _data Additional data with no specified format
    /// @return `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    ///  unless throwing
    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external returns (bytes4);
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

interface IERC1155ERC721 {
    /**
     * @notice Mint an amount of a desired token
     * Currently no restrictions as to who is allowed to mint - so, it is external.
     * @dev ERC-1155
     * @param _to       owner of the minted token
     * @param _tokenId  ID of the token to be minted
     * @param _value    Amount of the token to be minted
     * @param _data     Additional data forwarded to onERC1155BatchReceived if _to is a contract
     */
    function mint(
        address _to,
        uint256 _tokenId,
        uint256 _value,
        bytes calldata _data
    ) external;

    /**
     * @notice Burn an amount of tokens with the given ID
     * @dev ERC-1155
     * @param _account  Account which owns the token
     * @param _tokenId  ID of the token
     * @param _value    Amount of the token
     */
    function burn(
        address _account,
        uint256 _tokenId,
        uint256 _value
    ) external;

    /**
     * @notice Function to mint tokens.
     * @dev ERC-721
     * @param to The address that will receive the minted tokens.
     * @param tokenId The token id to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(address to, uint256 tokenId) external returns (bool);

    /**
        @dev MUST emit when approval for a second party/operator address to manage all tokens for an owner address is enabled or disabled (absence of an event assumes disabled).        
    */
    event ApprovalForAll(
        address indexed _owner,
        address indexed _operator,
        bool _approved
    );
}

// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity 0.7.1;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * [EIP](https://eips.ethereum.org/EIPS/eip-165).
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others (`ERC165Checker`).
 *
 * For an implementation, see `ERC165`.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * [EIP section](https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified)
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

{
  "optimizer": {
    "enabled": true,
    "runs": 10
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