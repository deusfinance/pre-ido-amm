pragma solidity ^0.8.10;

interface Factory {
    event PreIDOTokenCreated(address indexed collateral, address indexed preIDOToken);

    function createPreIDOToken(string memory name, string memory symbol) external;

    
}