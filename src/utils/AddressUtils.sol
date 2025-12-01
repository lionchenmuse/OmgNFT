// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library AddressUtils {
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }
}