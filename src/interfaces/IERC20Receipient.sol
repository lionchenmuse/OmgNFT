// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Receipient {
    function tokenReceived(
        address from,
        uint256 amount,
        bytes memory data
    ) external;
}