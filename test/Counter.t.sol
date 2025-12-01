// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Counters} from "../src/utils/Counters.sol";
import {console} from "forge-std/console.sol";

contract CountersTest is Test {
    using Counters for Counters.Counter;

    Counters.Counter public counter;

    function setUp() public view {
        console.log(counter.current());
    }

    function test_next() public {
        counter.next();
        assertEq(counter.current(), 1);
        counter.next();
        assertEq(counter.current(), 2);
        counter.next();
        assertEq(counter.current(), 3);
    }

    // function testFuzz_SetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}
