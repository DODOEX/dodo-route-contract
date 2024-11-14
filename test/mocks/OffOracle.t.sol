// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "contracts/mocks/OffsetOracle.sol";


contract OffsetOracleTest is Test {
    OffsetOracle public offsetOracle;
    address public owner = address(1);
    address public user1 = address(2);

  
    function setUp() public {
      vm.label(owner, "owner");
      vm.label(user1, "user1");

      offsetOracle = new OffsetOracle();
    }

    function testOriginPrice() public {
        uint price = offsetOracle.getPrice();
        assertEq(price, 1000000000000000000);
    }

    function testSetPrice() public {
        offsetOracle.adjustPrice(1001000000000000000);
        uint price = offsetOracle.getPrice();
        assertEq(price, 1001000000000000000);
    }

    function testSetInvalidPrice() public {
        vm.expectRevert(bytes("Large Offset"));
        offsetOracle.adjustPrice(1002000000000000000);

        uint price = offsetOracle.getPrice();
        assertEq(price, 1000000000000000000);
    }

    function testNotOwnerSet() public {
        vm.prank(user1);
        vm.expectRevert();
        offsetOracle.adjustPrice(1001000000000000000);
    }
}