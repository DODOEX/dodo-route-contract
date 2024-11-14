// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "contracts/mocks/MerkleDistribution.sol";
import "./ERC20Mock.sol";


contract MerkleDistributorTest is Test {
    MerkleDistributor public merkleDist;
    address public owner = address(1);
    address public user1 = 0x217E3c976ac44465649CA01329a9a4027F1350B5;
    address public user2 = 0x20b7644006a9c4C46b3c4147D938494BAa06E104;
    address public teamMember1 = 0x8157668EC72c279C20C9d7387b7B711FcF713a4D;

    bytes32 public root = 0xbf277dcbca46435fc87fcf2ae47a69dff634672e068756ce3c9669bbcec825e8;
    bytes32[] public merkleTree1 = [
            bytes32(0x866e3ac31342b177e521a292b287397f7e0cd4d04942872f503e75e76a7a3bc9),
            bytes32(0xefeaf49c37addf9da2b385e33c1a0e981b107dc5fe09f61a21ae8861f2145812),
            bytes32(0x209cfad7a229d2665475616cf8f4f557b467fd6fbdc688a8e8d094637f1110b3),
            bytes32(0x4657ea41b72882531f09a732b23bb2c702015a67bceea49e0e9d8bf638703a44),
            bytes32(0x807edb6df7a002e9fa66f35572c2fc0d2fe3d2a065e5a3c33afca2bc928cb694),
            bytes32(0x0b6b0b71ee2f9e4206f5381564c77ccf3f11757dae8041c4fa2dcd40534469f8),
            bytes32(0xf3dd2d75bec784b66a4b5b15d8085a3cd411a7c0171d47a4fb336d804ffd2def),
            bytes32(0x6e9352e3496da46ed7a68c399afb100f6669c799da4afe0358ddcf97e9461c74),
            bytes32(0x749d8ee1382cfe54a8dbb6cf53bb64076a634e97a0d91afb9f8a113fbd4a5df1),
            bytes32(0x7cd595d1b582e3cf6a96100ad630f746c8084c5e4dfb53b2bfff19a131fcc319),
            bytes32(0xc5749119afea1f397cd3a22d856964508f8c48f4c683ba4278e96ad2fbf364d5)
    ];

    bytes32 public teamRoot = 0x024c53acae4d381300dc21e29540b53f415dc2a44522b193b96cd848dbdce407;
    bytes32[] public teamMember1Proof = [
        bytes32(0xd5d74d217247022cd07226c01fffa1f5be52640103a17ddad04e1efad33f31d4),
        bytes32(0x9ae63d6ff9f8dd3efde82103f8ca0d560a8c9b2de657309b4b7c036595ad5d00)
    ];

    ERC20Mock public token1;
    ERC20Mock public token2;

    function setUp() public {
      vm.label(owner, "owner");
      vm.label(user1, "user1");

      token1 = new ERC20Mock("Token1", "tk1");
      vm.label(address(token1), "Token1");
      token2 = new ERC20Mock("Token2", "tk2");

      //bytes32 root = bytes32(bytes("0xbf277dcbca46435fc87fcf2ae47a69dff634672e068756ce3c9669bbcec825e8"));
      vm.prank(owner);
      merkleDist = new MerkleDistributor(
        address(token1),
        root
      );
      //merkleDist.transferOwnership(owner);
      assertEq(merkleDist.owner(), owner);

      token1.transfer(address(merkleDist), 20000 * 1e6);
    }

    // ============= claim and claim error ===============
    function testNormalClaim() public {    
        vm.prank(user1);
        // 0x11409013
        merkleDist.claim(185, user1, 289443859, merkleTree1);
        uint256 balance1 = token1.balanceOf(user1);
        assertEq(balance1, 289443859);
    }

    function testInvalidProof() public {
        vm.prank(user1);
        // 0x11409013
        vm.expectRevert(bytes("MerkleDistributor: Invalid proof."));
        merkleDist.claim(185, user2, 289443859, merkleTree1);
        uint256 balance1 = token1.balanceOf(user2);
        assertEq(balance1, 0);
    }

    function testHaveClaimed() public {
        testNormalClaim();
        vm.prank(user1);
        vm.expectRevert(bytes("MerkleDistributor: Drop already claimed."));
        merkleDist.claim(185, user1, 289443859, merkleTree1);
    }

    function testTransferFail() public {
        vm.startPrank(owner);
        merkleDist.setPause();
        merkleDist.claimLeftByOwner(owner);
        uint256 balOwner = token1.balanceOf(owner);
        assertEq(balOwner, 20000 * 1e6);
        merkleDist.setUnPause();
        vm.stopPrank();

        vm.prank(user1);
        // 0x11409013
        //vm.expectRevert(bytes("MerkleDistributor: Transfer failed."));
        vm.expectRevert(bytes("ERC20: transfer amount exceeds balance"));
        merkleDist.claim(185, user1, 289443859, merkleTree1);
        uint256 balance1 = token1.balanceOf(user2);
        assertEq(balance1, 0);
    }

    // ============= pause and pause error ===============
    function testOwnerPause() public {
        vm.prank(owner);
        merkleDist.setPause();
        assertEq(merkleDist.paused(), true);

        vm.prank(user1);
        // 0x11409013
        vm.expectRevert(bytes("Pausable: paused"));
        merkleDist.claim(185, user1, 289443859, merkleTree1);
    }

    function testUnPause() public {
        testOwnerPause();
        // other unpause
        vm.prank(user1);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        merkleDist.setUnPause();

        // check unpause state
        vm.prank(user1);
        vm.expectRevert(bytes("Pausable: paused"));
        merkleDist.claim(185, user1, 289443859, merkleTree1);

        // owner unpause and claim
        vm.prank(owner);
        merkleDist.setUnPause();
        assertEq(merkleDist.paused(), false);
        testNormalClaim();
    }

    function testOtherPauseRevert() public {
        vm.prank(user1);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        merkleDist.setPause();

        assertEq(merkleDist.paused(), false);
        testNormalClaim();
    }

    // ============ owner set new hash =============
    function testSetNewProof() public {
        vm.prank(user1);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        merkleDist.setNewProof(teamRoot);

        vm.prank(owner);
        merkleDist.setNewProof(teamRoot);

        // claim test
        vm.prank(user1);
        vm.expectRevert(bytes("MerkleDistributor: Invalid proof."));
        merkleDist.claim(185, user1, 289443859, merkleTree1);

        token1.transfer(address(merkleDist), 20 ether);
        vm.prank(teamMember1);
        merkleDist.claim(0, teamMember1, 20000000000000000000, teamMember1Proof);
        uint256 bal1 = token1.balanceOf(teamMember1);
        assertEq(bal1, 20 ether);
    }
    
    // ============= owner set new token ==============
    function testSetNewToken() public {
        vm.prank(user1);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        merkleDist.setNewToken(address(token2));

        vm.startPrank(owner);
        merkleDist.setNewToken(address(token2));
        merkleDist.setNewProof(teamRoot);
        vm.stopPrank();

        token2.transfer(address(merkleDist), 20 ether);
        vm.prank(teamMember1);
        merkleDist.claim(0, teamMember1, 20000000000000000000, teamMember1Proof);
        uint256 bal2 = token2.balanceOf(teamMember1);
        assertEq(bal2, 20 ether);
    }

    // ============ owner claim left ===============
    function testOwnerClaim() public {
        testNormalClaim();
        vm.startPrank(owner);
        merkleDist.setPause();
        merkleDist.claimLeftByOwner(owner);
        uint256 balOwner = token1.balanceOf(owner);
        assertEq(balOwner, 20000 * 1e6 - 289443859);
        vm.stopPrank();
    }
}