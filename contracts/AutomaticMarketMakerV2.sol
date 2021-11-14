//Be name khoda
//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20 {
	function totalSupply() external view returns (uint256);
	function mint(address to, uint256 amount) external;
	function burn(address from, uint256 amount) external;
	function transfer(address recipient, uint256 amount) external returns (bool);
	function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IPower {
	function power(uint256 _baseN, uint256 _baseD, uint32 _expN, uint32 _expD) external view returns (uint256, uint8);
}

contract AutomaticMarketMakerV2 is AccessControl, ReentrancyGuard {

	bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
	bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

	event Buy(address user, uint256 idoAmount, uint256 collateralAmount, uint256 feeAmount);
	event Sell(address user, uint256 collateralAmount, uint256 idoAmount, uint256 feeAmount);
	event ChangeDisableExchange(bool isDisableExhange);
    event ChangeUserStatusInWhiteList(address user, bool isBanned);
    event withdrawCollateral(address to, uint256 amount);
    event ChangeUserStatusInBlackList(address user, bool isBlocked);
    

	IERC20 public idoAsset;
	IERC20 public collateralAsset;
	IPower public Power;
	uint256 public reserve;
	uint256 public firstSupply;
	uint256 public firstReserve;
	uint256 public reserveShiftAmount;
	uint256 public daoFeeAmount;
	address public daoWallet;
	
	uint32 public cwScale = 10**6;
	uint32 public cw = 0.35 * 10**6; 


	uint256 public daoShare = 5 * 10**15;
	uint256 public daoShareScale = 10**18;

	mapping (address => bool) isBlackListed;
	
	// obtain the ban situation
	bool private disableExchange = false;
	// show users that are allowed to exchange in disableExchange situation
	mapping (address => bool) whiteListAddr;

	modifier onlyOperator {
		require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not an operator");
		_;
	}
	
	modifier onlyFeeCollector {
		require(hasRole(FEE_COLLECTOR_ROLE, msg.sender), "Caller is not a FeeCollector");
		_;
	}
	
	modifier hasExchangePermission {
	    if (disableExchange) {
	        require(whiteListAddr[msg.sender], "Caller doesn't have permission to exchange");
	    }
	    _;
	}
	
	function setDisableExchange(bool _disableExchange) external onlyOperator {
	    disableExchange = _disableExchange;
	    emit ChangeDisableExchange(disableExchange);
	}
	
	function setWhiteListAddr(address user, bool status) external onlyOperator {
	    whiteListAddr[user] = status;
	    emit ChangeUserStatusInWhiteList(user, status);
	}

	function setDaoWallet(address _daoWallet) external onlyOperator {
		daoWallet = _daoWallet;
	}

	function withdrawCollateral(uint256 amount, address to) external onlyOperator {
		collateralAsset.transfer(to, amount);
		emit withdrawCollateral(to, amount);
	}

	function withdrawFee(uint256 amount, address to) public onlyFeeCollector {
		require(amount <= daoFeeAmount, "amount is bigger than daoFeeAmount");
		daoFeeAmount = daoFeeAmount - amount;
		collateralAsset.transfer(to, amount);
		emit withdrawCollateral(to, amount);
	}

	function withdrawTotalFee(address to) external {
		withdrawFee(daoFeeAmount, to);
	}

	function setBlackListStatus(address user, bool status) external onlyOperator {
		isBlackListed[user] = status;
		emit ChangeUserStatusInBlackList(user, true);
	}

	function init(uint256 _firstReserve, uint256 _firstSupply) external onlyOperator {
		reserve = _firstReserve;
		firstReserve = _firstReserve;
		firstSupply = _firstSupply;
		reserveShiftAmount = reserve * (cwScale - cw) / cwScale;
	}

	function setDaoShare(uint256 _daoShare) external onlyOperator {
		daoShare = _daoShare;
	}

	receive() external payable {
		revert();
	}

	constructor(address _collateralAsset, address _idoAsset, address _power) ReentrancyGuard() {
		require(_collateralAsset != address(0) && _idoAsset != address(0) && _power != address(0), "Bad args");

		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(OPERATOR_ROLE, msg.sender);
		_setupRole(FEE_COLLECTOR_ROLE, msg.sender);

		daoWallet = msg.sender;
		collateralAsset = IERC20(_collateralAsset);
		idoAsset = IERC20(_idoAsset);
		Power = IPower(_power);
	}

	function _bancorCalculatePurchaseReturn(
		uint256 _supply,
		uint256 _connectorBalance,
		uint32 _connectorWeight,
		uint256 _depositAmount) internal view returns (uint256){
		// validate input
		require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= cwScale, "_bancorCalculateSaleReturn() Error");

		// special case for 0 deposit amount
		if (_depositAmount == 0) {
			return 0;
		}

		uint256 result;
		uint8 precision;
		uint256 baseN = _depositAmount + _connectorBalance;
		(result, precision) = Power.power(baseN, _connectorBalance, _connectorWeight, cwScale);
		uint256 newTokenSupply = _supply * result >> precision;
		return newTokenSupply - _supply;
	}

	function calculatePurchaseReturn(uint256 collateralAmount) public view returns (uint256, uint256) {

		uint256 feeAmount = collateralAmount * daoShare / daoShareScale;
		collateralAmount = collateralAmount - feeAmount;
		uint256 supply = idoAsset.totalSupply();
		
		if (supply < firstSupply){
			if  (reserve + collateralAmount > firstReserve){
				uint256 exteraDeusAmount = reserve + collateralAmount - firstReserve;
				uint256 idoAmount = firstSupply - supply;

				idoAmount = idoAmount + _bancorCalculatePurchaseReturn(firstSupply, firstReserve - reserveShiftAmount, cw, exteraDeusAmount);
				return (idoAmount, feeAmount);
			}
			else{
				return (supply * collateralAmount / reserve, feeAmount);
			}
		}else{
			return (_bancorCalculatePurchaseReturn(supply, reserve - reserveShiftAmount, cw, collateralAmount), feeAmount);
		}
	}

	function buyFor(address user, uint256 _idoAmount, uint256 _collateralAmount) public nonReentrant() hasExchangePermission {
		require(!isBlackListed[user], "freezed address");
		
		(uint256 idoAmount, uint256 feeAmount) = calculatePurchaseReturn(_collateralAmount);
		require(idoAmount >= _idoAmount, 'price changed');

		reserve = reserve + _collateralAmount - feeAmount;

		collateralAsset.transferFrom(msg.sender, address(this), _collateralAmount);
		idoAsset.mint(user, idoAmount);

		daoFeeAmount = daoFeeAmount + feeAmount;

		emit Buy(user, idoAmount, _collateralAmount, feeAmount);
	}

	function buy(uint256 idoAmount, uint256 collateralAmount) public {
		buyFor(msg.sender, idoAmount, collateralAmount);
	}

	function _bancorCalculateSaleReturn(
		uint256 _supply,
		uint256 _connectorBalance,
		uint32 _connectorWeight,
		uint256 _sellAmount) internal view returns (uint256){

		// validate input
		require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= cwScale && _sellAmount <= _supply, "_bancorCalculateSaleReturn Error");
		// special case for 0 sell amount
		if (_sellAmount == 0) {
			return 0;
		}
		// special case for selling the entire supply
		if (_sellAmount == _supply) {
			return _connectorBalance;
		}

		uint256 result;
		uint8 precision;
		uint256 baseD = _supply - _sellAmount;
		(result, precision) = Power.power(_supply, baseD, cwScale, _connectorWeight);
		uint256 oldBalance = _connectorBalance * result;
		uint256 newBalance = _connectorBalance << precision;
		return (oldBalance - newBalance) / result;
	}

	function calculateSaleReturn(uint256 idoAmount) public view returns (uint256, uint256) {
		uint256 supply = idoAsset.totalSupply();
		uint256 returnAmount;

		if (supply > firstSupply) {
			if (firstSupply > supply - idoAmount) {
				uint256 exteraFutureAmount = firstSupply - (supply - idoAmount);
				uint256 collateralAmount = reserve - firstReserve;
				returnAmount = collateralAmount + (firstReserve * exteraFutureAmount / firstSupply);

			} else {
				returnAmount = _bancorCalculateSaleReturn(supply, reserve - reserveShiftAmount, cw, idoAmount);
			}
		} else {
			returnAmount = reserve * idoAmount / supply;
		}
		uint256 feeAmount = returnAmount * daoShare / daoShareScale;
		return (returnAmount - feeAmount, feeAmount);
	}

	function sellFor(address user, uint256 idoAmount, uint256 _collateralAmount) public nonReentrant() hasExchangePermission {
		require(!isBlackListed[user], "freezed address");
		
		(uint256 collateralAmount, uint256 feeAmount) = calculateSaleReturn(idoAmount);
		require(collateralAmount >= _collateralAmount, 'price changed');

		reserve = reserve - (collateralAmount + feeAmount);
		idoAsset.burn(msg.sender, idoAmount);
		collateralAsset.transfer(msg.sender, collateralAmount);

		daoFeeAmount = daoFeeAmount + feeAmount;

		emit Sell(user, collateralAmount, idoAmount, feeAmount);
	}

	function sell(uint256 idoAmount, uint256 collateralAmount) public {
		sellFor(msg.sender, idoAmount, collateralAmount);
	}
}

//Dar panah khoda