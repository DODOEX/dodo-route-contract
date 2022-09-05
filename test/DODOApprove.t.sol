// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "contracts/DODOApprove.sol";
import "./mocks/ERC20Mock.sol";

contract DODOApproveTest is Test {
    DODOApprove public dodoApprove;
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    address public proxyAddr1 = address(4);
    address public proxyAddr2 = address(5);

    ERC20Mock public token1;
  
    function setUp() public {
      vm.label(owner, "owner");
      vm.label(user1, "user1");
      vm.label(user2, "user2");
      vm.label(proxyAddr1, "proxy1");
      vm.label(proxyAddr2, "proxy2");

      dodoApprove = new DODOApprove();

      token1 = new ERC20Mock("Token1", "tk1");
      vm.label(address(token1), "Token1");
      token1.transfer(user1, 100 * 10 ** 18);
    }

    function testInit() public {
      dodoApprove.init(owner, proxyAddr1);
      assertEq(dodoApprove._OWNER_(), owner);
      assertEq(dodoApprove._DODO_PROXY_(), proxyAddr1);
    }

    // Case 1: normally change proxy acquires 3 days locktime
    function testUnlockSetProxyCase1() public {
      dodoApprove.init(owner, proxyAddr1);
      uint time = block.timestamp;
      vm.prank(owner);
      dodoApprove.unlockSetProxy(proxyAddr2);
      assertEq(dodoApprove._PENDING_DODO_PROXY_(), proxyAddr2);
      assertEq(dodoApprove._TIMELOCK_(), time + 3 days);
    }

    // Case 2: if previous proxy is 0 address, locktime is 1 day
    function testUnlockSetProxyCase2() public {
      dodoApprove.init(owner, address(0));
      uint time = block.timestamp;
      vm.prank(owner);
      dodoApprove.unlockSetProxy(proxyAddr2);
      assertEq(dodoApprove._PENDING_DODO_PROXY_(), proxyAddr2);
      assertEq(dodoApprove._TIMELOCK_(), time + 24 hours);
    }

    function testLockSetProxy() public {
      dodoApprove.init(owner, proxyAddr1);
      vm.prank(owner);
      dodoApprove.unlockSetProxy(proxyAddr2);
      vm.prank(owner);
      dodoApprove.lockSetProxy();
      assertEq(dodoApprove._PENDING_DODO_PROXY_(), address(0)); 
    }

    function testSetDODOProxyTimeLocked() public {
      dodoApprove.init(owner, proxyAddr1);
      vm.prank(owner);
      dodoApprove.unlockSetProxy(proxyAddr2);
      vm.prank(owner);
      vm.expectRevert(bytes("SetProxy is timelocked"));
      dodoApprove.setDODOProxy();
      assertEq(dodoApprove._DODO_PROXY_(), proxyAddr1);
    }

    function testSetDODOProxyTimeUnlocked() public {
      dodoApprove.init(owner, proxyAddr1);
      vm.prank(owner);
      dodoApprove.unlockSetProxy(proxyAddr2);
      vm.prank(owner);
      vm.warp(block.timestamp + 86400 * 3);
      dodoApprove.setDODOProxy();
      assertEq(dodoApprove._DODO_PROXY_(), proxyAddr2);
    }

    function testClaimTokens() public {
      dodoApprove.init(owner, proxyAddr1);
      vm.prank(user1);
      token1.approve(address(dodoApprove), type(uint256).max);
      vm.prank(dodoApprove._DODO_PROXY_());
      dodoApprove.claimTokens(address(token1), user1, user2, 50e18);
      assertEq(token1.balanceOf(user2), 50e18);
    }

    function testClaimTokensByNotProxy() public {
      dodoApprove.init(owner, proxyAddr1);
      vm.prank(user1);
      token1.approve(address(dodoApprove), type(uint256).max);
      vm.prank(user2);
      vm.expectRevert(bytes("DODOApprove:Access restricted"));
      dodoApprove.claimTokens(address(token1), user1, user2, 50e18);
      assertEq(token1.balanceOf(user2), 0);
    }

    function testGetDODOProxy() public {
      dodoApprove.init(owner, proxyAddr1);
      assertEq(dodoApprove.getDODOProxy(), proxyAddr1);
    }
}