// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Crowdfund} from "../src/Crowdfund.sol";

contract CrowdfundDeployScript is Script {
    Crowdfund public crowdfund;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        crowdfund = new Crowdfund(address(0));
        console.logAddress(address(crowdfund));
        vm.stopBroadcast();
    }
}
