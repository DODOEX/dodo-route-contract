// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "../contracts/SmartRoute/DODOGasProxy.sol";
import "../contracts/DODOApprove.sol";
import "../contracts/DODOApproveProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token contract for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

// Mock target contract for testing token transfers
contract MockTarget {
    using SafeERC20 for IERC20;
    
    event TokenReceived(address token, uint256 amount);
    
    function receiveTokens(address token, uint256 amount) external payable {
        if(token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            require(msg.value == amount, "Invalid ETH amount");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        emit TokenReceived(token, amount);
    }
    
    receive() external payable {}
}

contract DODOGasProxyTest is Test {
    DODOGasProxy public proxy;
    DODOApprove public dodoApprove;
    DODOApproveProxy public dodoApproveProxy;
    MockERC20 public token;
    MockTarget public target;
    
    address public owner;
    address public bot;
    address public user;
    
    function setUp() public {
        owner = address(this);
        bot = makeAddr("bot");
        user = makeAddr("user");
        
        // Deploy and initialize DODOApprove
        dodoApprove = new DODOApprove();
        
        // Deploy DODOApproveProxy
        dodoApproveProxy = new DODOApproveProxy(address(dodoApprove));
        
        // Initialize DODOApprove with ApproveProxy
        dodoApprove.init(owner, address(dodoApproveProxy));
        
        // Deploy GasProxy
        proxy = new DODOGasProxy(owner, bot, address(dodoApproveProxy));
        
        // Initialize DODOApproveProxy with GasProxy
        address[] memory proxies = new address[](1);
        proxies[0] = address(proxy);
        dodoApproveProxy.init(owner, proxies);
        
        // Deploy other contracts
        token = new MockERC20();
        target = new MockTarget();
        
        // Transfer some tokens to test user
        token.transfer(user, 1000 * 10**18);
        
        // Give user some ETH
        vm.deal(user, 100 ether);
    }
    
    // Helper function to setup proxy settings
    function _setupProxy(uint64 chainId, uint256 gasFee, address targetContract) internal {
        // Setup chain gas fee
        uint64[] memory chainIds = new uint64[](1);
        chainIds[0] = chainId;
        
        uint256[] memory gasFees = new uint256[](1);
        gasFees[0] = gasFee;
        
        vm.prank(bot);
        proxy.batchSetChainGasFee(chainIds, gasFees);
        
        // Setup whitelist for execute target
        address[] memory targets = new address[](1);
        targets[0] = targetContract;
        
        bool[] memory isWhiteListed = new bool[](1);
        isWhiteListed[0] = true;
        
        vm.prank(bot);
        proxy.batchSetWhiteListContract(targets, isWhiteListed);
        
        // Setup whitelist for approve target
        vm.prank(bot);
        proxy.batchSetWhiteListApproveContract(targets, isWhiteListed);
    }
    
    // ============ Owner Tests ============
    
    function testSetBot() public {
        address newBot = makeAddr("newBot");
        proxy.setBot(newBot);
        assertEq(proxy.bot(), newBot);
    }
    
    function testSetBotFailNotOwner() public {
        address newBot = makeAddr("newBot");
        vm.prank(user);
        vm.expectRevert("NOT_OWNER");
        proxy.setBot(newBot);
    }
    
    function testWithdraw() public {
        // Test ETH withdrawal
        payable(address(proxy)).transfer(1 ether);
        uint256 balanceBefore = address(owner).balance;
        proxy.withdraw();
        assertEq(address(owner).balance - balanceBefore, 1 ether);
    }
    
    // ============ Bot Tests ============
    
    function testBatchSetChainGasFee() public {
        uint64[] memory chainIds = new uint64[](2);
        chainIds[0] = 1;
        chainIds[1] = 2;
        
        uint256[] memory gasFees = new uint256[](2);
        gasFees[0] = 0.01 ether;
        gasFees[1] = 0.02 ether;
        
        vm.prank(bot);
        proxy.batchSetChainGasFee(chainIds, gasFees);
        
        assertEq(proxy.chainGasFee(1), 0.01 ether);
        assertEq(proxy.chainGasFee(2), 0.02 ether);
    }
    
    function testBatchSetWhiteListContract() public {
        address[] memory targets = new address[](2);
        targets[0] = address(target);
        targets[1] = makeAddr("target2");
        
        bool[] memory isWhiteListed = new bool[](2);
        isWhiteListed[0] = true;
        isWhiteListed[1] = false;
        
        vm.prank(bot);
        proxy.batchSetWhiteListContract(targets, isWhiteListed);
        
        assertTrue(proxy.isWhiteListedContract(address(target)));
        assertFalse(proxy.isWhiteListedContract(targets[1]));
    }
    
    function testBatchSetWhiteListApproveContract() public {
        address[] memory targets = new address[](2);
        targets[0] = address(target);
        targets[1] = makeAddr("target2");
        
        bool[] memory isWhiteListed = new bool[](2);
        isWhiteListed[0] = true;
        isWhiteListed[1] = false;
        
        vm.prank(bot);
        proxy.batchSetWhiteListApproveContract(targets, isWhiteListed);
        
        assertTrue(proxy.isWhiteListedApproveContract(address(target)));
        assertFalse(proxy.isWhiteListedApproveContract(targets[1]));
    }
    
    // ============ Main Function Tests ============
    
    function testProxyCallWithERC20() public {
        // Setup proxy with required settings
        _setupProxy(1, 0.01 ether, address(target));
        
        uint256 amount = 100 * 10**18;
        uint256 transferInGasFee = 0.015 ether; // Higher than required gas fee
        
        vm.startPrank(user);
        // Approve tokens to DODOApprove
        token.approve(address(dodoApprove), amount);
        
        // Construct call data
        bytes memory callData = abi.encodeWithSelector(
            MockTarget.receiveTokens.selector,
            address(token),
            amount
        );
        
        // Execute proxy call
        proxy.proxyCall{value: transferInGasFee}(
            1, // chainId
            address(token),
            amount,
            address(target),
            address(target),
            transferInGasFee,
            callData
        );
        vm.stopPrank();
        
        assertEq(token.balanceOf(address(target)), amount);
    }
    
    function testProxyCallWithETH() public {
        // Setup proxy with required settings
        _setupProxy(1, 0.01 ether, address(target));
        
        uint256 amount = 1 ether;
        uint256 transferInGasFee = 0.015 ether; // Higher than required gas fee
        
        vm.startPrank(user);
        bytes memory callData = abi.encodeWithSelector(
            MockTarget.receiveTokens.selector,
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount
        );
        
        proxy.proxyCall{value: amount + transferInGasFee}(
            1,
            0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            amount,
            address(target),
            address(target),
            transferInGasFee,
            callData
        );
        vm.stopPrank();
        
        assertEq(address(target).balance, amount);
    }
    
    function testProxyCallFailInsufficientGasFee() public {
        // Setup proxy with required settings
        _setupProxy(1, 0.01 ether, address(target));
        
        uint256 amount = 100 * 10**18;
        uint256 transferInGasFee = 0.005 ether; // Lower than required gas fee
        
        vm.startPrank(user);
        token.approve(address(dodoApprove), amount);
        
        bytes memory callData = abi.encodeWithSelector(
            MockTarget.receiveTokens.selector,
            address(token),
            amount
        );
        
        vm.expectRevert("DODOGasProxy: INSUFFICIENT_TRANSFER_IN_GAS_FEE");
        proxy.proxyCall{value: transferInGasFee}(
            1,
            address(token),
            amount,
            address(target),
            address(target),
            transferInGasFee,
            callData
        );
        vm.stopPrank();
    }

    receive() external payable {}
    fallback() external payable {}
}
