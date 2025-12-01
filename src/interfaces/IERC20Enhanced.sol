// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Enhanced is IERC20 {
    event TransferWithCallback(
        address indexed from,
        address indexed to,
        uint256 amount,
        bool callbackSuccess
    );

    function transferWithCallback(
        address from,
        address to,
        uint256 amount,
        bytes memory data
    ) external returns (bool);
}

