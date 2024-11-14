// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "forge-std/Script.sol";
import "../contracts/SmartRoute/DODOGasProxy.sol";
import "../contracts/DODOApprove.sol";
import "../contracts/DODOApproveProxy.sol";
import "../contracts/SmartRoute/DOODGasDistributor.sol";

contract DeployScript is Script {
    function run() external {
        // Get deployer private key from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address approveOwner = 0x...;
        address gasOwner = 0x...;
        vm.startBroadcast(deployerPrivateKey);

        // Deploy DODOApprove
        DODOApprove dodoApprove = new DODOApprove();
        
        // Deploy DODOApproveProxy
        DODOApproveProxy dodoApproveProxy = new DODOApproveProxy(
            address(dodoApprove)
        );

        // Initialize DODOApprove with owner and proxy
        dodoApprove.init(approveOwner, address(dodoApproveProxy));

        // Set bot address for DODOGasProxy
        address bot = 0x...;

        // Deploy DODOGasProxy
        DODOGasProxy gasProxy = new DODOGasProxy(
            gasOwner,
            bot,
            address(dodoApproveProxy)
        );

        // Deploy DOODGasDistributor
        uint256 maxAmount = 0.03 ether; // Set initial max amount to 0.01 ETH
        DOODGasDistributor distributor = new DOODGasDistributor(
            gasOwner,
            bot,
            maxAmount
        );

        // Initialize DODOApproveProxy with owner and initial proxies
        address[] memory initialProxies = new address[](1);
        initialProxies[0] = address(gasProxy);
        dodoApproveProxy.init(approveOwner, initialProxies);
        

        console.log("DODOApprove deployed to:", address(dodoApprove));
        console.log("DODOApproveProxy deployed to:", address(dodoApproveProxy));
        console.log("DODOGasProxy deployed to:", address(gasProxy));
        console.log("DOODGasDistributor deployed to:", address(distributor));

        vm.stopBroadcast();
    }
}
