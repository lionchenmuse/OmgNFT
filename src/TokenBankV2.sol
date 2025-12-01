// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TokenBank} from "./TokenBank.sol";
import {IERC20Receipient} from "./interfaces/IERC20Receipient.sol";

contract TokenBankV2 is TokenBank, IERC20Receipient { 
    constructor(address tokenAddress) TokenBank(tokenAddress) {
    }

    function tokenReceived(address from, uint256 amount, bytes memory data) external override {
        _balances[from] += amount;
        _totalBalances += amount;
    }
}