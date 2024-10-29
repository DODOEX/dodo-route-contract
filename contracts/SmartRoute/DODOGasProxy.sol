// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UniversalERC20 } from "./lib/UniversalERC20.sol";
import { IDODOApproveProxy } from "../DODOApproveProxy.sol";

/// @title DODOGasProxy
/// @author DODO Breeder
/// @notice A proxy contract that charges gas fees for cross-chain transactions
contract DODOGasProxy is Ownable {
    using UniversalERC20 for IERC20;

    // ============ Storage ============
    
    address constant _ETH_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // DODOApproveProxy address for token claiming
    address public immutable _DODO_APPROVE_PROXY_;
    
    // Gas fee mapping for each target chain
    mapping(uint64 => uint256) public chainGasFee;
    // Whitelist mapping for approved contracts
    mapping(address => bool) public isWhiteListedContract;
    // Whitelist mapping for approved approve contracts
    mapping(address => bool) public isWhiteListedApproveContract;
    
    // Bot address for setting gas fees and whitelist
    address public bot;
    
    // Pause state
    bool public paused;
    
    // ============ Events ============
    
    event GasFeeChanged(uint64 chainId, uint256 newFee);
    event WhiteListChanged(address indexed target, bool isWhiteListed);
    event WhiteListApproveChanged(address indexed target, bool isWhiteListed);
    event BotChanged(address indexed newBot);
    event GasFeePaid(address payer, uint64 chainId, uint256 gasFee);
    event PausedStateChanged(bool newState);

    // ============ Modifiers ============
    
    modifier onlyBot() {
        require(msg.sender == bot, "DODOGasProxy: NOT_BOT");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "DODOGasProxy: PAUSED");
        _;
    }

    // ============ Constructor ============

    constructor(address _bot, address dodoApproveProxy) {
        require(_bot != address(0), "DODOGasProxy: BOT_INVALID");
        require(dodoApproveProxy != address(0), "DODOGasProxy: DODO_APPROVE_PROXY_INVALID");
        bot = _bot;
        _DODO_APPROVE_PROXY_ = dodoApproveProxy;
    }

    // ============ Admin Functions ============

    /// @notice Set new bot address
    function setBot(address newBot) external onlyOwner {
        require(newBot != address(0), "DODOGasProxy: BOT_INVALID");
        bot = newBot;
        emit BotChanged(newBot);
    }

    /// @notice Withdraw all assets from contract
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /// @notice Set pause state
    function setPaused(bool newState) external onlyOwner {
        paused = newState;
        emit PausedStateChanged(newState);
    }

    // ============ Bot Functions ============

    /// @notice Set gas fee for target chain
    function setChainGasFee(uint64 chainId, uint256 gasFee) external onlyBot {
        chainGasFee[chainId] = gasFee;
        emit GasFeeChanged(chainId, gasFee);
    }

    /// @notice Set contract whitelist status
    function setWhiteListContract(address target, bool isWhiteListed) external onlyBot {
        isWhiteListedContract[target] = isWhiteListed;
        emit WhiteListChanged(target, isWhiteListed);
    }

    /// @notice Set approve contract whitelist status 
    function setWhiteListApproveContract(address target, bool isWhiteListed) external onlyBot {
        isWhiteListedApproveContract[target] = isWhiteListed;
        emit WhiteListApproveChanged(target, isWhiteListed);
    }

    // ============ Main Functions ============

    /// @notice Execute transaction through proxy and charge gas fee
    /// @param chainId Target chain ID
    /// @param fromToken Source token address
    /// @param fromTokenAmount Amount of source tokens
    /// @param approveTarget Address to approve tokens for
    /// @param targetContract Contract to call
    /// @param callData Call data for target contract
    function proxyCall(
        uint64 chainId,
        address fromToken,
        uint256 fromTokenAmount,
        address approveTarget,
        address targetContract,
        bytes calldata callData
    ) external payable whenNotPaused returns (bytes memory) {
        // Check if target contract is whitelisted
        require(isWhiteListedApproveContract[approveTarget], "DODOGasProxy: NOT_WHITELISTED");
        require(isWhiteListedContract[targetContract], "DODOGasProxy: NOT_WHITELISTED");
        
        // Check and collect gas fee
        uint256 requiredGasFee = chainGasFee[chainId];
        require(requiredGasFee > 0, "DODOGasProxy: GAS_FEE_NOT_SET");
        
        // Transfer user tokens
        if(fromToken == _ETH_ADDRESS_) {
            require(msg.value == fromTokenAmount + requiredGasFee, "DODOGasProxy: INVALID_ETH_AMOUNT");
        } else {
            require(msg.value == requiredGasFee, "DODOGasProxy: INVALID_GAS_FEE");
            // Use DODOApproveProxy to claim tokens instead of transferFrom
            IDODOApproveProxy(_DODO_APPROVE_PROXY_).claimTokens(
                fromToken,
                msg.sender,
                address(this),
                fromTokenAmount
            );
            // Approve target contract if needed
            if(approveTarget != address(0)) {
                IERC20(fromToken).approve(approveTarget, fromTokenAmount);
            }
        }
        
        emit GasFeePaid(msg.sender, chainId, requiredGasFee);

        // Call target contract
        (bool success, bytes memory result) = targetContract.call{
            value: fromToken == _ETH_ADDRESS_ ? fromTokenAmount : 0
        }(callData);
        
        require(success, "DODOGasProxy: CALL_FAILED");
        return result;
    }

    receive() external payable {}
    fallback() external payable {}
}
