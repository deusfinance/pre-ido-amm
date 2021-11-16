//Be name khoda
//SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
	// TODO: change require messages
	// TODO: refactor code style
	// TODO: add reverse view functions (Hasan)

	bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
	bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

	address  public idoAddress;  // TODO: change to address
	address  public collateralAddress;  // TODO: change to address
	address  public powerAddress;  // TODO: change to address
	uint256 public collateralReverse;
	
	// TODO: check static sale part
	uint256 public firstSupply;
	uint256 public firstReserve;
	uint256 public reserveShiftAmount;

	uint256 public deployerTotalFeeAmount;
	uint256 public fee = 5 * 10**15; 
	uint256 public feeScale = 10**18;

	uint32 public cwScale = 10**6;
	uint32 public cw = 0.35 * 10**6;

	// switch between whitelist and blacklist
	bool public activeWhiteList = false;  // TODO: change name

	uint startBlock; // TODO: is data type ok?

	mapping (address => bool) blackListAddr;  // TODO: change name
	mapping (address => bool) whiteListAddr;  // TODO: change name // show users that are allowed to exchange when WhiteList is active
	

	modifier onlyOperator {
		require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not an operator");
		_;
	}
	
	modifier onlyFeeCollector {
		require(hasRole(FEE_COLLECTOR_ROLE, msg.sender), "Caller is not a FeeCollector");
		_;
	}

	// TODO: change name	
	modifier restrictAddr(address user) {
		if (activeWhiteList) {
			require(whiteListAddr[user], "Address is restricted");
		} else {
			require(!blackListAddr[user], "Address is restricted");
		}
		_;
	}

	// TODO: where should we use this modifier?
	modifier checkStartBlock {
		require(block.number >= startBlock, "Current block number is less than start block number");
		_;
	}

	function setStartBlock(uint _startBlock) {
		startBlock = _startBlock;
	}
	
	function activateWhiteList(bool _activeWhiteList) external onlyOperator {  // TODO: change name
		activeWhiteList = _activeWhiteList;
		emit WhiteListActivated(activeWhiteList);
	}
	
	function setWhiteListAddr(address user, bool status) external onlyOperator {  // TODO: change name
		whiteListAddr[user] = status;
		emit WhiteListAddrSet(user, status);
	}

	function setBlackListAddr(address user, bool status) external onlyOperator {  // TODO: change name
		blackListAddr[user] = status;
		emit BlackListAddrSet(user, status);
	}

	function withdrawCollateral(uint256 amount, address to) external onlyOperator {
		IERC20(collateralAddress).transfer(to, amount);
		emit CollateralTransferred(to, amount);
	}

	function withdrawFee(uint256 amount, address to) external onlyFeeCollector {
		require(amount <= deployerTotalFeeAmount, "amount is bigger than deployerTotalFeeAmount");
		deployerTotalFeeAmount = deployerTotalFeeAmount - amount;
		IERC20(collateralAddress).transfer(to, amount);
		emit FeeTransferred(to, amount);
	}

	function setFee(uint256 _fee) external onlyOperator {
		fee = _fee;
	}

	receive() external payable {
		revert();
	}

	constructor(address _collateralAddress, address _idoAddress, address _powerAddress) ReentrancyGuard() {
		require(_collateralAddress != address(0) && _idoAddress != address(0) && _powerAddress != address(0), "Bad args");

		// TODO: what are new roles? role management.
		_setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
		_setupRole(OPERATOR_ROLE, msg.sender);
		_setupRole(FEE_COLLECTOR_ROLE, msg.sender);

		collateralAddress = _collateralAddress;
		idoAddress = _idoAddress;
		powerAddress = _powerAddress;
	}

	function init(uint256 _firstReserve, uint256 _firstSupply, uint32 _cw) external onlyOperator {
		collateralReverse = _firstReserve;
		firstReserve = _firstReserve;
		firstSupply = _firstSupply;
		cw = _cw;
		reserveShiftAmount = collateralReverse * (cwScale - cw) / cwScale;
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
		(result, precision) = IPower(powerAddress).power(baseN, _connectorBalance, _connectorWeight, cwScale);
		uint256 newTokenSupply = _supply * result >> precision;
		return newTokenSupply - _supply;
	}

	function calculatePurchaseReturn(uint256 collateralAmount) public view returns (uint256, uint256) {

		uint256 feeAmount = collateralAmount * fee / feeScale;
		collateralAmount = collateralAmount - feeAmount;
		uint256 supply = IERC20(idoAddress).totalSupply();
		
		if (supply < firstSupply){
			if  (collateralReverse + collateralAmount > firstReserve){
				uint256 exteraDeusAmount = collateralReverse + collateralAmount - firstReserve;
				uint256 idoAmount = firstSupply - supply;

				idoAmount = idoAmount + _bancorCalculatePurchaseReturn(firstSupply, firstReserve - reserveShiftAmount, cw, exteraDeusAmount);
				return (idoAmount, feeAmount);
			}
			else{
				return (supply * collateralAmount / collateralReverse, feeAmount);
			}
		}else{
			return (_bancorCalculatePurchaseReturn(supply, collateralReverse - reserveShiftAmount, cw, collateralAmount), feeAmount);
		}
	}

	function buyFor(address user, uint256 _idoAmount, uint256 _collateralAmount) public nonReentrant() restrictAddr(user) checkStartBlock(){
		(uint256 idoAmount, uint256 feeAmount) = calculatePurchaseReturn(_collateralAmount);
		require(idoAmount >= _idoAmount, 'price changed');

		collateralReverse = collateralReverse + _collateralAmount - feeAmount;

		IERC20(collateralAddress).transferFrom(msg.sender, address(this), _collateralAmount);
		IERC20(idoAddress).mint(user, idoAmount);

		deployerTotalFeeAmount = deployerTotalFeeAmount + feeAmount;

		emit Buy(user, idoAmount, _collateralAmount, feeAmount);
	}

	function buy(uint256 idoAmount, uint256 collateralAmount) external {
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
		(result, precision) = IPower(powerAddress).power(_supply, baseD, cwScale, _connectorWeight);
		uint256 oldBalance = _connectorBalance * result;
		uint256 newBalance = _connectorBalance << precision;
		return (oldBalance - newBalance) / result;
	}

	function calculateSaleReturn(uint256 idoAmount) public view returns (uint256, uint256) {
		uint256 supply = IERC20(idoAddress).totalSupply();
		uint256 returnAmount;

		if (supply > firstSupply) {
			if (firstSupply > supply - idoAmount) {
				uint256 extraFutureAmount = firstSupply - (supply - idoAmount);
				uint256 collateralAmount = collateralReverse - firstReserve;
				returnAmount = collateralAmount + (firstReserve * extraFutureAmount / firstSupply);

			} else {
				returnAmount = _bancorCalculateSaleReturn(supply, collateralReverse - reserveShiftAmount, cw, idoAmount);
			}
		} else {
			returnAmount = collateralReverse * idoAmount / supply;
		}
		uint256 feeAmount = returnAmount * fee / feeScale;
		return (returnAmount - feeAmount, feeAmount);
	}

	function sellFor(address user, uint256 idoAmount, uint256 _collateralAmount) public nonReentrant() restrictAddr(user) checkStartBlock(){

		(uint256 collateralAmount, uint256 feeAmount) = calculateSaleReturn(idoAmount);
		require(collateralAmount >= _collateralAmount, 'price changed');

		collateralReverse = collateralReverse - (collateralAmount + feeAmount);
		IERC20(idoAddress).burn(msg.sender, idoAmount);
		IERC20(collateralAddress).transfer(msg.sender, collateralAmount);

		deployerTotalFeeAmount = deployerTotalFeeAmount + feeAmount;

		emit Sell(user, collateralAmount, idoAmount, feeAmount);
	}

	function sell(uint256 idoAmount, uint256 collateralAmount) external {
		sellFor(msg.sender, idoAmount, collateralAmount);
	}

	event Buy(address user, uint256 idoAmount, uint256 collateralAmount, uint256 feeAmount);
	event Sell(address user, uint256 collateralAmount, uint256 idoAmount, uint256 feeAmount);
	event CollateralTransferred(address to, uint256 amount);
	event FeeTransferred(address to, uint256 amount);
	event WhiteListActivated(bool activeWhiteList);  // TODO: change name
	event WhiteListAddrSet(address user, bool status);  // TODO: change name
	event BlackListAddrSet(address user, bool status);  // TODO: change name

}

//Dar panah khoda