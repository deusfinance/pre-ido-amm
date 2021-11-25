//Be name khoda
//SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IPower {
	function power(uint256 _baseN, uint256 _baseD, uint32 _expN, uint32 _expD) external view returns (uint256, uint8);
}

contract PreIDOToken is ReentrancyGuard , ERC20 {

	address public factory;
	address public collateralAddress;
	address public powerLibrary;

	// TODO: check static sale part
	uint256 public firstSupply;
	uint256 public firstReserve;
	uint256 public reserveShiftAmount;
	uint256 public collateralReverse;
	uint256 public ammID;
	uint256 public deployerTotalFeeAmount;
	uint256 public fee = 5 * 10**15; 
	uint256 public feeScale = 10**18;

	uint32 public cwScale = 10**6;
	uint32 public cw = 0.35 * 10**6;

	uint32 startBlock; // TODO: is data type ok?

	// switch between whitelist and blacklist
	bool public activeWhiteList = false;

	mapping (address => bool) blackListAddr;  // show users that are not allowed to exchange when activeWhiteList is false
	mapping (address => bool) whiteListAddr;  // show users that are allowed to exchange when activeWhiteList is true
	
	
	/* ========== CONSTRUCTOR ========== */

	constructor(address _factory, uint256 _ammID, address _collateralAddress, address _powerLibrary , string _name , string _symbol ) ReentrancyGuard() ERC20(_name , _symbol) {
		require(_collateralAddress != address(0) && _powerLibrary != address(0) && _factory != address(0), "PreIDOAMM: Zero address detected");

		factory = _factory;
		ammID = _ammID;
		collateralAddress = _collateralAddress;
		powerLibrary = _powerLibrary;
	}


	/* ========== MODIFIERS ========== */

	
	modifier restrictAddr(address user) {
		if (activeWhiteList) {
			require(whiteListAddr[user], "PreIDOAMM: Address is restricted");
		} else {
			require(!blackListAddr[user], "PreIDOAMM: Address is restricted");
		}
		_;
	}

	// TODO: where should we use this modifier?
	modifier isActive {
		require(block.number >= startBlock, "PreIDOAMM: Current block number is less than start block number");
		_;
	}

	modifier onlyOwner {
		require(IERC721(factory).ownerOf(ammID) == msg.sender, "PreIDOAMM: You are not owner");
		_;
	}
	/* ========== PUBLIC FUNCTIONS ========== */

	function sellFor(
		address user, 
		uint256 idoAmount, 
		uint256 _collateralAmount
	) public nonReentrant() restrictAddr(user) isActive {

		(uint256 collateralAmount, uint256 feeAmount) = calculateSaleReturn(idoAmount);
		require(collateralAmount >= _collateralAmount, 'price changed');

		collateralReverse = collateralReverse - (collateralAmount + feeAmount);
		_burn(msg.sender, idoAmount);
		IERC20(collateralAddress).transfer(msg.sender, collateralAmount);

		deployerTotalFeeAmount = deployerTotalFeeAmount + feeAmount;

		emit Sell(user, collateralAmount, idoAmount, feeAmount);
	}

	function buyFor(
		address user, 
		uint256 _idoAmount, 
		uint256 _collateralAmount
	) public nonReentrant() restrictAddr(user) isActive {
		(uint256 idoAmount, uint256 feeAmount) = calculatePurchaseReturn(_collateralAmount);
		require(idoAmount >= _idoAmount, 'price changed');

		collateralReverse = collateralReverse + _collateralAmount - feeAmount;

		IERC20(collateralAddress).transferFrom(msg.sender, address(this), _collateralAmount);
		_mint(user, idoAmount);

		deployerTotalFeeAmount = deployerTotalFeeAmount + feeAmount;

		emit Buy(user, idoAmount, _collateralAmount, feeAmount);
	}

	function buy(uint256 idoAmount, uint256 collateralAmount) external {
		buyFor(msg.sender, idoAmount, collateralAmount);
	}

	function sell(uint256 idoAmount, uint256 collateralAmount) external {
		sellFor(msg.sender, idoAmount, collateralAmount);
	}


	/* ========== VIEWS ========== */

	function _bancorCalculateSaleReturn(
		uint256 _supply, 
		uint256 _connectorBalance, 
		uint32 _connectorWeight, 
		uint256 _sellAmount
	) internal view returns (
		uint256
	){

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
		(result, precision) = IPower(powerLibrary).power(_supply, baseD, cwScale, _connectorWeight);
		uint256 oldBalance = _connectorBalance * result;
		uint256 newBalance = _connectorBalance << precision;
		return (oldBalance - newBalance) / result;
	}

	function calculateSaleReturn(
		uint256 idoAmount
	) public view returns (
		uint256, 
		uint256
	){
		uint256 supply = totalSupply();
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

	function calculateSaleAmountIn(
		uint256 goal, 
		uint256 eps
	) public view returns (
		uint256
	){
	    uint256 upper = 1;
	    if (goal >= eps)
	        upper = eps >> 1;
	    uint256 amount = 0;
	    while (amount <= goal) {
	        upper <<= 1;
	        amount = calculateSaleReturn(upper);
	    }
	    uint256 lower = upper >> 1;
	    uint256 mid;
	    while (true) {
	        mid = (lower + upper) >> 1;
	        amount = calculateSaleReturn(mid);
	        if (amount <= goal) {
	            if (goal - amount <= eps)
	                return mid;
	            lower = mid;
	        }
	        else {
	            if (amount - goal <= eps)
	                return mid;
	            upper = mid;
	        }
	   }
    }

	function _bancorCalculatePurchaseReturn(
		uint256 _supply,
		uint256 _connectorBalance,
		uint32 _connectorWeight,
		uint256 _depositAmount
	) internal view returns (
		uint256
	){
		// validate input
		require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= cwScale, "_bancorCalculateSaleReturn() Error");

		// special case for 0 deposit amount
		if (_depositAmount == 0) {
			return 0;
		}

		uint256 result;
		uint8 precision;
		uint256 baseN = _depositAmount + _connectorBalance;
		(result, precision) = IPower(powerLibrary).power(baseN, _connectorBalance, _connectorWeight, cwScale);
		uint256 newTokenSupply = _supply * result >> precision;
		return newTokenSupply - _supply;
	}

	function calculatePurchaseReturn(
		uint256 collateralAmount
	) public view returns (
		uint256, uint256
	){
		uint256 feeAmount = collateralAmount * fee / feeScale;
		collateralAmount = collateralAmount - feeAmount;
		uint256 supply = totalSupply();
		
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

	function calculatePurchaseAmountIn(
		uint256 goal, 
		uint256 eps
	) public view returns (
		uint256
	){
	    uint256 upper = 1;
	    if (goal >= eps)
	        upper = eps >> 1;
	    uint256 amount = 0;
	    while (amount <= goal) {
	        upper <<= 1;
	        amount = calculatePurchaseReturn(upper);
	    }
	    uint256 lower = upper >> 1;
	    uint256 mid;
	    while (true) {
	        mid = (lower + upper) >> 1;
	        amount = calculatePurchaseReturn(mid);
	        if (amount <= goal) {
	            if (goal - amount <= eps)
	                return mid;
	            lower = mid;
	        }
	        else {
	            if (amount - goal <= eps)
	                return mid;
	            upper = mid;
	        }
	   }
    }


	/* ========== RESTRICTED FUNCTIONS ========== */

	function init(uint256 _firstReserve, uint256 _firstSupply, uint32 _cw) external onlyOwner {
		collateralReverse = _firstReserve;
		firstReserve = _firstReserve;
		firstSupply = _firstSupply;
		cw = _cw;
		reserveShiftAmount = collateralReverse * (cwScale - cw) / cwScale;
	}

	function activateWhiteList(bool _activeWhiteList) external onlyOwner {
		activeWhiteList = _activeWhiteList;
		emit WhiteListActivated(activeWhiteList);
	}
	
	function setWhiteListAddr(address user, bool status) external onlyOwner {
		whiteListAddr[user] = status;
		emit WhiteListAddrSet(user, status);
	}

	function setBlackListAddr(address user, bool status) external onlyOwner {
		blackListAddr[user] = status;
		emit BlackListAddrSet(user, status);
	}

	function withdrawCollateral(uint256 amount, address to) external onlyOwner {
		IERC20(collateralAddress).transfer(to, amount);
		emit CollateralTransferred(to, amount);
	}

	function withdrawFee(uint256 amount, address to) external onlyOwner {
		require(amount <= deployerTotalFeeAmount, "amount is bigger than deployerTotalFeeAmount");
		deployerTotalFeeAmount = deployerTotalFeeAmount - amount;
		IERC20(collateralAddress).transfer(to, amount);
		emit FeeTransferred(to, amount);
	}

	function setFee(uint256 _fee) external onlyOwner {
		fee = _fee;
	}

	function setStartBlock(uint32 _startBlock) external onlyOwner {
		startBlock = _startBlock;
	}

	receive() external payable {
		revert();
	}


	/* ========== EVENTS ========== */

	event Buy(address user, uint256 idoAmount, uint256 collateralAmount, uint256 feeAmount);
	event Sell(address user, uint256 collateralAmount, uint256 idoAmount, uint256 feeAmount);
	event CollateralTransferred(address to, uint256 amount);
	event FeeTransferred(address to, uint256 amount);
	event WhiteListActivated(bool activeWhiteList);	
	event WhiteListAddrSet(address user, bool status);
	event BlackListAddrSet(address user, bool status);
}

//Dar panah khoda