// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../contracts/SmartRoute/DOODGasDistributor.sol";

contract DODOGasDistributorTest is Test {
    DOODGasDistributor public distributor;
    
    address public owner;
    address public bot;
    address public recipient;
    uint256 public constant INITIAL_MAX_AMOUNT = 1 ether;
    
    function setUp() public {
        owner = address(this);
        bot = makeAddr("bot");
        recipient = makeAddr("recipient");
        
        distributor = new DOODGasDistributor(
            owner,
            bot,
            INITIAL_MAX_AMOUNT
        );
        
        // Fund distributor with ETH
        vm.deal(address(distributor), 10 ether);
    }
    
    function testSetBot() public {
        address newBot = makeAddr("newBot");
        
        distributor.setBot(newBot);
        assertEq(distributor.bot(), newBot);
    }
    
    function testSetBotFailNotOwner() public {
        address newBot = makeAddr("newBot");
        
        vm.prank(bot);
        vm.expectRevert("NOT_OWNER");
        distributor.setBot(newBot);
    }
    
    function testSetMaxAmount() public {
        uint256 newMaxAmount = 2 ether;
        
        distributor.setMaxAmount(newMaxAmount);
        assertEq(distributor.maxAmount(), newMaxAmount);
        
    }
    
    function testSetMaxAmountFailNotOwner() public {
        vm.prank(bot);
        vm.expectRevert("NOT_OWNER");
        distributor.setMaxAmount(2 ether);
    }
    
    function testDistributeAboveMaxAmount() public {
        uint256 amount = 2 ether; // Greater than INITIAL_MAX_AMOUNT
        bytes32 externalId = keccak256(abi.encodePacked("test1"));
        uint256 recipientInitialBalance = recipient.balance;
        
        vm.prank(bot);
        distributor.distribute(recipient, amount, externalId);
        
        // Should only distribute maxAmount
        assertEq(
            recipient.balance - recipientInitialBalance,
            INITIAL_MAX_AMOUNT,
            "Should distribute maxAmount"
        );
    }
    
    function testDistributeBelowMaxAmount() public {
        uint256 amount = 0.5 ether; // Less than INITIAL_MAX_AMOUNT
        bytes32 externalId = keccak256(abi.encodePacked("test2"));
        uint256 recipientInitialBalance = recipient.balance;
        
        vm.prank(bot);
        distributor.distribute(recipient, amount, externalId);
        
        // Should distribute full amount
        assertEq(
            recipient.balance - recipientInitialBalance,
            amount,
            "Should distribute full amount"
        );
    }
    
    function testDistributeFailDuplicateExternalId() public {
        bytes32 externalId = keccak256(abi.encodePacked("test3"));
        
        vm.startPrank(bot);
        distributor.distribute(recipient, 0.5 ether, externalId);
        
        vm.expectRevert("ExternalId already processed");
        distributor.distribute(recipient, 0.5 ether, externalId);
        vm.stopPrank();
    }
    
    function testEmergencyWithdraw() public {
        uint256 initialBalance = address(distributor).balance;
        uint256 ownerInitialBalance = owner.balance;
        
        distributor.emergencyWithdraw();
        
        assertEq(
            address(distributor).balance,
            0,
            "Distributor should have 0 balance"
        );
        assertEq(
            owner.balance - ownerInitialBalance,
            initialBalance,
            "Owner should receive all funds"
        );
    }
    
    function testEmergencyWithdrawFailNotOwner() public {
        vm.prank(bot);
        vm.expectRevert("NOT_OWNER");
        distributor.emergencyWithdraw();
    }
    
    function testEmergencyWithdrawFailNoBalance() public {
        // First withdraw all balance
        distributor.emergencyWithdraw();
        
        // Try to withdraw again
        vm.expectRevert("No balance to withdraw");
        distributor.emergencyWithdraw();
    }
    
    receive() external payable {}
}
