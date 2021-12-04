// Be name khoda
// SPDX-License-Identifier: MIT
// =================================================================================================================
//  _|_|_|    _|_|_|_|  _|    _|    _|_|_|      _|_|_|_|  _|                                                       |
//  _|    _|  _|        _|    _|  _|            _|            _|_|_|      _|_|_|  _|_|_|      _|_|_|    _|_|       |
//  _|    _|  _|_|_|    _|    _|    _|_|        _|_|_|    _|  _|    _|  _|    _|  _|    _|  _|        _|_|_|_|     |
//  _|    _|  _|        _|    _|        _|      _|        _|  _|    _|  _|    _|  _|    _|  _|        _|           |
//  _|_|_|    _|_|_|_|    _|_|    _|_|_|        _|        _|  _|    _|    _|_|_|  _|    _|    _|_|_|    _|_|_|     |
// =================================================================================================================
// ========================= PreIDOToken ========================
// ==============================================================
// DEUS Finance: https://github.com/DeusFinance

// Primary Author(s)
// Vahid Gh: https://github.com/vahid-dev
// MH Shoara: https://github.com/mhshoara
// Peyman: https://github.com/peymanm001

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IPower.sol";

contract PreIDOToken is ReentrancyGuard, ERC20, Ownable {
	using SafeERC20 for IERC20;

	/* ========== STATE VARIABLES ========== */

	address public uniswapV2RouterV02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
	address public factory;
	address public collateralAddress;
	address public powerLibrary;
	uint private constant deadline = 0xf000000000000000000000000000000000000000000000000000000000000000;
	uint public collateralReverse;
	uint public shiftSupply;
	uint public ammID;
	uint public totalFee;
	uint32 public fee;
	uint32 public deusFeeShare;
	uint32 public claimRatio;
	uint public claimStartBlock;
	uint public claimEndBlock;
	uint32 public cw;
	uint32 public scale = 10**6;
	uint public startBlock;

	bool public activeWhiteList = false; // switch between whitelist and blacklist
	mapping(address => bool) blackListAddr; // show users that are not allowed to exchange when activeWhiteList is false
	mapping(address => bool) whiteListAddr; // show users that are allowed to exchange when activeWhiteList is true

	/* ========== EVENTS ========== */

	event Buy(address user, uint idoAmount, uint collateralAmount, uint feeAmount);
	event Sell(address user, uint collateralAmount, uint idoAmount, uint feeAmount);
	event WithdrawCollateral(address to, uint amount);
	event WithdrawFee(address to, uint amount);
	event WhiteListActivated(bool activeWhiteList);
	event WhiteListAddrSet(address user, bool status);
	event BlackListAddrSet(address user, bool status);
	event Claim(address user, uint amount);
	event ClaimPeriodSet(uint _startBlock, uint _endBlock);
	event ClaimRatioSet(uint32 _claimRatio);

	/* ========== CONSTRUCTOR ========== */

	constructor(
		// address _creator_address,   addr[0]
		// address _factory,           addr[1]
		// address _collateralAddress, addr[2]
		// address _powerLibrary,      addr[3]
		address[] memory addrs,
		uint _ammID,
		uint32 _fee,
		uint32 _deusFeeShare,
		uint _startBlock,
		uint32 _cw,
		uint _shiftReserve,
		uint _shiftSupply,
		string memory _name,
		string memory _symbol
	) 
		ReentrancyGuard() 
		ERC20(_name, _symbol)
	{
		require(
			addrs[0] != address(0) &&
			addrs[1] != address(0) &&
			addrs[2] != address(0) &&
			addrs[3] != address(0),
			"PreIDOToken: Zero address detected"
		);
		require(_fee <= scale, "PreIDOToken: invalid _fee");
		factory = addrs[1];
		collateralAddress = addrs[2];
		powerLibrary = addrs[3];
		ammID = _ammID;
		fee = _fee;
		deusFeeShare = _deusFeeShare;
		startBlock = _startBlock;
		cw = _cw;
		collateralReverse = _shiftReserve;
		shiftSupply = _shiftSupply;

		// IERC20(collateralAddress).safeApprove(uniswapV2RouterV02, type(uint).max);
	}

	receive() external payable { revert(); }

	/* ========== MODIFIERS ========== */

	modifier restrictAddr(address user) {
		if (activeWhiteList) {
			require(whiteListAddr[user], "PreIDOToken: Address is restricted");
		} else {
			require(!blackListAddr[user], "PreIDOToken: Address is restricted");
		}
		_;
	}

	modifier isActive() {
		require(
			block.number >= startBlock,
			"PreIDOToken: Current block number is less than start block number"
		);
		_;
	}

	// modifier onlyOwner {
	// 	require(IERC721(factory).ownerOf(ammID) == msg.sender, "PreIDOToken: You are not owner");
	// 	_;
	// }

	modifier isClaimable() {
		require(
			claimStartBlock <= block.number && block.number <= claimEndBlock,
			"PreIDOToken: Claim is closed"
		);
		_;
	}

	/* ========== PUBLIC FUNCTIONS ========== */

	function sellFor(
		address user,
		uint idoAmount,
		uint minCollateralAmount
	)
		external 
		nonReentrant 
		isActive
		restrictAddr(user)
	{
		(uint collateralAmount, uint feeAmount) = calculateSaleReturn(idoAmount);
		require(collateralAmount >= minCollateralAmount, "PreIDOToken: price changed");

		collateralReverse = collateralReverse - (collateralAmount + feeAmount);

		_burn(msg.sender, idoAmount);
		IERC20(collateralAddress).safeTransfer(msg.sender, collateralAmount);

		totalFee = totalFee + feeAmount;

		emit Sell(user, collateralAmount, idoAmount, feeAmount);
	}

	function buyFor(
		address user,
		uint minIdoAmount,
		uint collateralAmount
	) external nonReentrant restrictAddr(user) isActive {
		(uint idoAmount, uint feeAmount) = calculatePurchaseReturn(collateralAmount);
		require(idoAmount >= minIdoAmount, "PreIDOToken: price changed");

		collateralReverse = collateralReverse + collateralAmount - feeAmount;

		IERC20(collateralAddress).safeTransferFrom(msg.sender, address(this), collateralAmount);
		_mint(user, idoAmount);

		totalFee = totalFee + feeAmount;

		emit Buy(user, idoAmount, collateralAmount, feeAmount);
	}

	/* ========== Claim FUNCTIONS ========== */

	function claimFor(
		address user,
		uint amount,
		address toCoin
	) public isClaimable {
		_burn(msg.sender, amount);
		IERC20(toCoin).safeTransfer(user, (amount * claimRatio) / scale);
		emit Claim(user, (amount * claimRatio) / scale);
	}

	/* ========== VIEWS ========== */

	function _bancorCalculateSaleReturn(
		uint _supply,
		uint _connectorBalance,
		uint32 _connectorWeight,
		uint _sellAmount
	) internal view returns (uint) {
		// validate input
		require(
			_supply > 0 &&
			_connectorBalance > 0 &&
			_connectorWeight > 0 &&
			_connectorWeight <= scale &&
			_sellAmount <= _supply,
			"PreIDOToken: _bancorCalculateSaleReturn Error"
		);
		// special case for 0 sell amount
		if (_sellAmount == 0) {
			return 0;
		}
		// special case for selling the entire supply
		if (_sellAmount == _supply) {
			return _connectorBalance;
		}

		uint result;
		uint8 precision;
		uint baseD = _supply - _sellAmount;
		(result, precision) = IPower(powerLibrary).power(_supply, baseD, scale, _connectorWeight);
		uint oldBalance = _connectorBalance * result;
		uint newBalance = _connectorBalance << precision;
		return (oldBalance - newBalance) / result;
	}

	function calculateSaleReturn(uint idoAmount)
		public
		view
		returns (uint, uint)
	{
		uint supply = totalSupply();
		uint returnAmount;

		returnAmount = _bancorCalculateSaleReturn(supply, collateralReverse, cw, idoAmount);

		uint feeAmount = (returnAmount * fee) / scale;
		return (returnAmount - feeAmount, feeAmount);
	}

	function _bancorCalculateSaleAmountIn(
		uint _supply, 
		uint _connectorBalance, 
		uint32 _connectorWeight, 
		uint _collateralAmount
	) internal view returns (uint) {
		// validate input
		require(_supply > 0 && _connectorBalance > 0 && _connectorWeight > 0 && _connectorWeight <= scale && _collateralAmount <= _supply, "PreIDOToken: _bancorCalculateSaleAmountIn Error");
		// special case for 0 sell amount
		if (_collateralAmount == 0) {
			return 0;
		}
		// special case for selling the entire supply
		if (_collateralAmount == _connectorBalance) {
			return _supply;
		}
		uint result;
		uint8 precision;
		uint baseD = _connectorBalance - _collateralAmount;
		(result, precision) = IPower(powerLibrary).power(_connectorBalance , baseD , _connectorWeight, scale);
		uint oldBalance = _supply * result;
		uint newBalance = _supply << precision;
		return (oldBalance - newBalance) / result;
	}

	function calculateSaleAmountIn(uint collateralAmount)
		public
		view
		returns (uint, uint)
	{
		uint newCollateralAmount = (collateralAmount * scale) / (scale - fee);
		uint feeAmount = newCollateralAmount - collateralAmount;
		uint supply = totalSupply();

		uint returnAmount = _bancorCalculateSaleAmountIn(supply, collateralReverse, cw, newCollateralAmount);

		return (returnAmount, feeAmount);
	}

	function _bancorCalculatePurchaseReturn(
		uint _supply,
		uint _connectorBalance,
		uint32 _connectorWeight,
		uint _depositAmount
	) internal view returns (uint) {
		// validate input
		require(
			_supply > 0 &&
			_connectorBalance > 0 &&
			_connectorWeight > 0 &&
			_connectorWeight <= scale,
			"PreIDOToken: _bancorCalculateSaleReturn() Error"
		);

		// special case for 0 deposit amount
		if (_depositAmount == 0) {
			return 0;
		}

		uint result;
		uint8 precision;
		uint baseN = _depositAmount + _connectorBalance;
		(result, precision) = IPower(powerLibrary).power(baseN, _connectorBalance, _connectorWeight, scale);
		uint newTokenSupply = (_supply * result) >> precision;
		return newTokenSupply - _supply;
	}

	function calculatePurchaseReturn(uint collateralAmount)
		public
		view
		returns (uint, uint)
	{
		uint feeAmount = (collateralAmount * fee) / scale;
		collateralAmount = collateralAmount - feeAmount;
		uint supply = totalSupply();

		return (
			_bancorCalculatePurchaseReturn(supply, collateralReverse, cw, collateralAmount),
			feeAmount
		);
		
	}

	function _bancorCalculatePurchaseAmountIn(
		uint _supply,
		uint _connectorBalance,
		uint32 _connectorWeight,
		uint _idoAmount
	) internal view returns (uint) {
		// validate input
		require(
			_supply > 0 &&
			_connectorBalance > 0 &&
			_connectorWeight > 0 &&
			_connectorWeight <= scale,
			"PreIDOToken: _bancorCalculatePurchaseAmountIn() Error"
		);

		// special case for 0 deposit amount
		if (_idoAmount == 0) {
			return 0;
		}

		uint result;
		uint8 precision;
		uint baseN = _idoAmount + _supply;
		(result, precision) = IPower(powerLibrary).power(baseN, _supply, scale, _connectorWeight);
		uint newReserveAmount = (_connectorBalance * result) >> precision;
		return newReserveAmount - _connectorBalance;
	}

	function calculatePurchaseAmountIn(uint idoAmount)
		public
		view
		returns (uint, uint)
	{
		uint supply = totalSupply();
		uint buyAmount = _bancorCalculatePurchaseAmountIn(
			supply,
			collateralReverse,
			cw,
			idoAmount
		);
		uint returnAmount = (buyAmount * scale) / (scale - fee);

		return (returnAmount, returnAmount - buyAmount);
	}

	/* ========== RESTRICTED FUNCTIONS ========== */

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

	function setClaimPeriod(uint _startBlock, uint _endBlock)
		external
		onlyOwner
	{
		claimStartBlock = _startBlock;
		claimEndBlock = _endBlock;
		emit ClaimPeriodSet(_startBlock, _endBlock);
	}

	function setClaimRatio(uint32 _claimRatio) external onlyOwner {
		claimRatio = _claimRatio;
		emit ClaimRatioSet(_claimRatio);
	}

	function withdrawCollateral(uint amount, address to) external onlyOwner {
		IERC20(collateralAddress).safeTransfer(to, amount);
		emit WithdrawCollateral(to, amount);
	}

	function withdrawFee(uint amount, address to) external onlyOwner {
		require(amount <= totalFee, "PreIDOToken: invalid amount");
		totalFee = totalFee - amount;
		IERC20(collateralAddress).safeTransfer(to, amount);
		emit WithdrawFee(to, amount);
	}
}

//Dar panah khoda
