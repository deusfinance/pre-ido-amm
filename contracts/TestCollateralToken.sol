pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestCollateralToken is  ERC20 {

    constructor() ERC20("TestCollateralToken" , "TCT"){
    }

    function mint(address to , uint256 amount) public{
        _mint(to,amount);
    }

}