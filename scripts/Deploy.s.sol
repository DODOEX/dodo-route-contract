// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../contracts/SmartRoute/DODOGasProxy.sol";
import "../contracts/DODOApprove.sol";
import "../contracts/DODOApproveProxy.sol";

contract DeployScript is Script {
    function run() external {
        // Get deployer private key from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Deploy DODOApprove
        DODOApprove dodoApprove = new DODOApprove();
        
        // Deploy DODOApproveProxy
        DODOApproveProxy dodoApproveProxy = new DODOApproveProxy(
            address(dodoApprove)
        );

        // Initialize DODOApprove with owner and proxy
        dodoApprove.init(deployer, address(dodoApproveProxy));

        // Set bot address for DODOGasProxy
        address bot = 0x1Dc662D3D7De14a57CD369e3a9E774f8F80d4214;

        // Deploy DODOGasProxy
        DODOGasProxy gasProxy = new DODOGasProxy(
            bot,
            address(dodoApproveProxy)
        );

        // Initialize DODOApproveProxy with owner and initial proxies
        address[] memory initialProxies = new address[](1);
        initialProxies[0] = address(gasProxy);
        dodoApproveProxy.init(deployer, initialProxies);
        

        console.log("DODOApprove deployed to:", address(dodoApprove));
        console.log("DODOApproveProxy deployed to:", address(dodoApproveProxy));
        console.log("DODOGasProxy deployed to:", address(gasProxy));

        vm.stopBroadcast();
    }
}
