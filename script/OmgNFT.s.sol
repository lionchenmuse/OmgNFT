// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {BaseScript} from "./BaseScript.s.sol";
import {OmgNFT} from "../src/OmgNFT.sol";

contract OmgNFTScript is BaseScript {
    OmgNFT public omgNFT;

    function run() public broadcast {
        omgNFT = new OmgNFT("OmgNFT", "OMG");
        console.log("OmgNFT deployed to: ", address(omgNFT));

        saveContract("sepolia", "OmgNFT", address(omgNFT));

        console.logString(omgNFT.name());
        console.logString(omgNFT.symbol());
    }
}