pragma solidity ^0.8.4;

interface IPower {
    function power(
		uint256 _baseN,
		uint256 _baseD,
		uint32 _expN,
		uint32 _expD
	) external view returns (uint256, uint8);
	function generalLog(uint256 _x) external pure returns (uint256);
	function floorLog2(uint256 _n) external pure returns (uint8);
	function findPositionInMaxExpArray(uint256 _x) external view returns (uint8);
	function generalExp(uint256 _x, uint8 _precision) external pure returns (uint256);
	function optimalLog(uint256 x) external pure returns (uint256);
	function optimalExp(uint256 x) external pure returns (uint256);
}