// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

abstract contract BaseScript is Script {
    string internal mnemonic;
    address internal deployer;

    modifier broadcast() {
        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }

    function setUp() public virtual {
        // 从环境变量中获取助记词（需要先将环境变量写入.env 文件）
        mnemonic = vm.envString("SEPOLIA_MNEMONIC");
        require(bytes(mnemonic).length > 0, "mnemonic is empty");

        // 从助记词中获取部署者地址，助记词派生了多个地址，其中有余额的是索引1的地址。
        (deployer, ) = deriveRememberKey(mnemonic, 1);
        console.log("Deployer address: %s", deployer);
    }

    function saveContract(string memory network, string memory name, address contractAddress) public {
        string memory chainId = vm.toString(block.chainid);

        string memory jsonRoot = "key";
        string memory finalJson = vm.serializeAddress(jsonRoot, "address", contractAddress);
        string memory dirPath = string.concat(
            string.concat("deployments/", name),
            string.concat("_", string.concat(network, "_"))
        );
        string memory logFile = string.concat(dirPath, string.concat(chainId, ".json"));
        vm.writeJson(finalJson, logFile);
        console.log("Save contract address to %s", logFile);
    }
}