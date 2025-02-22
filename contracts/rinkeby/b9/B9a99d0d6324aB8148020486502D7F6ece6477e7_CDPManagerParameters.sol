// SPDX-License-Identifier: bsl-1.1

pragma solidity 0.7.6;

import "../VaultParameters.sol";

contract CDPManagerParameters is Auth{

    // ICR 抵押品可以借出的等值usdg的比例（0 decimals）
    mapping(address => uint) public initialCollateralRatio;

    // LR 清算触发比例（0 decimals）
    mapping(address => uint) public liquidationRatio;

    // 清算折扣（3 decimals）
    mapping(address => uint) public liquidationDiscount;

    // 贬值周期/折旧期, eg:usdt=3300 eth=1100，单位：block
    mapping(address => uint) public devaluationPeriod;

    constructor(address _vaultParameters) Auth(_vaultParameters) {
        // done.
    }

    /**
        业务函数
    */
    function setCollateral(
        address asset,
        uint stabilityFeeValue,
        uint liquidationFeeValue,
        uint initialCollateralRatioValue,
        uint liquidationRatioValue,
        uint liquidationDiscountValue,
        uint devaluationPeriodValue,
        uint usdgLimit,
        uint[] calldata oracles
    ) external onlyManager {
        vaultParameters.setCollateral(asset, stabilityFeeValue, liquidationFeeValue, usdgLimit, oracles);
        setInitialCollateralRatio(asset, initialCollateralRatioValue);
        setLiquidationRatio(asset, liquidationRatioValue);
        setLiquidationDiscount(asset, liquidationDiscountValue);
        setDevaluationPeriod(asset, devaluationPeriodValue);
    }

    /**
        工具函数
    */
    function setInitialCollateralRatio(address asset, uint newValue) public onlyManager {
        require(newValue != 0 && newValue <= 100, "Atom Protocol: INCORRECT_COLLATERALIZATION_VALUE");
        initialCollateralRatio[asset] = newValue;
    }

    function setLiquidationRatio(address asset, uint newValue) public onlyManager {
        require(newValue != 0 && newValue >= initialCollateralRatio[asset], "Atom Protocol: INCORRECT_COLLATERALIZATION_VALUE");
        liquidationRatio[asset] = newValue;
    }

    function setLiquidationDiscount(address asset, uint newValue) public onlyManager {
        require(newValue < 1e5, "Atom Protocol: INCORRECT_DISCOUNT_VALUE");
        liquidationDiscount[asset] = newValue;
    }

    function setDevaluationPeriod(address asset, uint newValue) public onlyManager {
        require(newValue != 0, "Atom Protocol: INCORRECT_DEVALUATION_VALUE");
        devaluationPeriod[asset] = newValue;
    }
}

// SPDX-License-Identifier: bsl-1.1

pragma solidity 0.7.6;

/**
    @title Auth
    @dev 合约权限管理
 */
contract Auth{

    VaultParameters public vaultParameters;

    constructor(address _vaultParametersAddress){
        vaultParameters = VaultParameters(_vaultParametersAddress);
    }

    modifier onlyManager() {
       require(vaultParameters.isManager(msg.sender), "ATOM Protocol: AUTH_FAILED");
        _;
    }

    modifier hasVaultAccess() {
       require(vaultParameters.canModifyVault(msg.sender), "ATOM Protocol: AUTH_FAILED");
        _;
    }

    modifier onlyVault() {
       require(msg.sender == vaultParameters.vault(), "ATOM Protocol: AUTH_FAILED");
        _;
    }
}

/**
   @title VaultParameters
   @dev Vault参数
*/
contract VaultParameters is Auth {

   /**
      重要成员变量
    */
   address payable public vault;

   address public foundation;

   /**
     系统权限相关变量
   */
   mapping(address => bool) public isManager;

   mapping(address => bool) public canModifyVault;

   /**
     业务流程相关变量
   */
   // Stability Fee（借出USDG一年的债务费用百分比，保留3位小数，例：5000=5%）
   mapping(address => uint) public stabilityFee;

   // Liquidation Fee（清算费用百分比，保留0位小数，例：8=8%）
   mapping(address => uint) public liquidationFee;

   // token最大可以借出USDG的限额
   mapping(address => uint) public tokenDebtLimit;

   // Oracle type & Asset address 是否enanle
   mapping(uint => mapping(address => bool)) public isOracleTypeEnabled;

   /**
      构造函数
   */
   constructor(address payable _vault, address _foundation) Auth(address(this)) {
      require(_vault != address(0), "Atom Protocol: ZERO_ADDRESS");
      require(_foundation != address(0), "Atom Protocol: ZERO_ADDRESS");

      isManager[msg.sender] = true;
      vault = _vault;
      foundation = _foundation;
   }

   /**
      业务函数
   */
   function setCollateral(
      address asset,
      uint stabilityFeeValue,
      uint liquidationFeeValue,
      uint tokenDebtLimitValue,
      uint[] calldata oracles
   ) external onlyManager {
      setStabilityFee(asset, stabilityFeeValue);
      setLiquidationFee(asset, liquidationFeeValue);
      setTokenDebtLimit(asset, tokenDebtLimitValue);
      for (uint i=0; i < oracles.length; i++) {
         setOracleType(oracles[i], asset, true);
      }
   }

   function setFoundation(address newFoundation) external onlyManager {
      require(newFoundation != address(0), "Atom Protocol: ZERO_ADDRESS");
      foundation = newFoundation;
   }   

   function setManager(address who, bool isPermit) external onlyManager {
      isManager[who] = isPermit;
   }

   function setVaultAccess(address who, bool isPermit) external onlyManager {
      canModifyVault[who] = isPermit;
   }

   function setStabilityFee(address asset, uint fee) public onlyManager {
      stabilityFee[asset] = fee;
   }

   function setLiquidationFee(address asset, uint fee) public onlyManager {
      require(fee <= 100, "Atom Protocol: VALUE_OUT_OF_RANGE");
      liquidationFee[asset] = fee;
   }

   function setTokenDebtLimit(address asset, uint limit) public onlyManager {
      tokenDebtLimit[asset] = limit;
   }

   function setOracleType(uint _type, address asset, bool enable) public onlyManager {
      isOracleTypeEnabled[_type][asset] = enable;
   }
}

{
  "optimizer": {
    "enabled": false,
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