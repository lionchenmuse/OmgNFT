// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library Counters {
    struct Counter {
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function next(Counter storage counter) internal returns (uint256) {
        unchecked {
            counter._value += 1;
        }
        return counter._value;
    }

}
