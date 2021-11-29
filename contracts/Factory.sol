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


pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./PreIDOToken.sol";

contract Factory is ERC721 {

    /* ========== STATE VARIABLES ========== */


    /* ========== CONSTRUCTOR ========== */

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {

    }

    /* ========== MODIFIERS ========== */


    /* ========== PUBLIC FUNCTIONS ========== */

    function createPreIDOToken(string memory name, string memory symbol) external {

    }

    /* ========== VIEWS ========== */


    /* ========== RESTRICTED FUNCTIONS ========== */


    /* ========== EVENTS ========== */

    event PreIDOTokenCreated(address indexed collateral, address indexed preIDOToken);
}