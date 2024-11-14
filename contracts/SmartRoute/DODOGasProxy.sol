// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UniversalERC20 } from "./lib/UniversalERC20.sol";
import { IDODOApproveProxy } from "../DODOApproveProxy.sol";
import { InitializableOwnable } from "../lib/InitializableOwnable.sol";

/// @title DODOGasProxy
/// @author DODO Breeder
/// @notice A proxy contract that charges gas fees for cross-chain transactions
contract DODOGasProxy is InitializableOwnable {
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;

    // ============ Storage ============
    
    address constant _ETH_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // DODOApproveProxy address for token claiming
    address public immutable _DODO_APPROVE_PROXY_;
    uint256 public nonce;
    uint256 public totalGasFee; // Total transferred in gas fee collected
    uint256 public totalBridgeGasFee; // Total bridge gas fee collected
    
    // Gas fee mapping for each target chain
    mapping(uint64 => uint256) public chainGasFee;
    // Gas fee mapping for each cross-chain bridge
    mapping(uint64 => uint256) public bridgeGasFee;
    // Whitelist mapping for approved contracts
    mapping(address => bool) public isWhiteListedContract;
    // Whitelist mapping for approved approve contracts
    mapping(address => bool) public isWhiteListedApproveContract;
    
    // Bot address for setting gas fees and whitelist
    address public bot;
    
    // Pause state
    bool public paused;

    // For readability
    struct ChainGasFee {
        uint64 chainId;
        uint256 gasFee;
    }

    struct BridgeGasFee {
        uint64 chainId;
        uint256 gasFee;
    }

    uint64[] internal chainIndexs;
    uint64[] internal bridgeIndexs;
    
    // ============ Events ============
    
    event GasFeeChanged(uint64 chainId, uint256 newFee);
    event BridgeGasFeeChanged(uint64 chainId, uint256 newFee);
    event WhiteListChanged(address indexed target, bool isWhiteListed);
    event WhiteListApproveChanged(address indexed target, bool isWhiteListed);
    event BotChanged(address indexed newBot);
    event GasFeePaid(address payer, uint64 chainId, uint256 gasFee, bytes32 externalID);
    event BridgeGasFeePaid(address payer, uint64 chainId, uint256 gasFee, bytes32 externalID);
    event PausedStateChanged(bool newState);
    event NativeDrip(address payer, uint64 chainId, uint256 amount, bytes32 externalID);

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

    constructor(address _owner, address _bot, address dodoApproveProxy) {
        initOwner(_owner);
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
        payable(_OWNER_).transfer(address(this).balance);
    }

    /// @notice Set pause state
    function setPaused(bool newState) external onlyOwner {
        paused = newState;
        emit PausedStateChanged(newState);
    }

    // ============ Bot Functions ============

    /// @notice Batch set gas fees for target chains
    /// @param chainIds Array of chain IDs
    /// @param gasFees Array of corresponding gas fees
    function batchSetChainGasFee(
        uint64[] calldata chainIds,
        uint256[] calldata gasFees
    ) external onlyBot {
        require(chainIds.length == gasFees.length, "DODOGasProxy: LENGTH_MISMATCH");
        
        for (uint256 i = 0; i < chainIds.length; i++) {
            chainGasFee[chainIds[i]] = gasFees[i];
            bridgeIndexs.push(chainIds[i]);
            emit GasFeeChanged(chainIds[i], gasFees[i]);
        }
    }

    /// @notice Batch set gas fees for cross-chain bridges
    /// @param chainIds Array of chain IDs
    /// @param gasFees Array of corresponding gas fees
    function batchSetBridgeGasFee(
        uint64[] calldata chainIds,
        uint256[] calldata gasFees
    ) external onlyBot {
        require(chainIds.length == gasFees.length, "DODOGasProxy: LENGTH_MISMATCH");
        
        for (uint256 i = 0; i < chainIds.length; i++) {
            bridgeGasFee[chainIds[i]] = gasFees[i];
            bridgeIndexs.push(chainIds[i]);
            emit BridgeGasFeeChanged(chainIds[i], gasFees[i]);
        }
    }

    /// @notice Batch set contract whitelist status
    /// @param targets Array of target addresses
    /// @param isWhiteListed Array of whitelist status
    function batchSetWhiteListContract(
        address[] calldata targets,
        bool[] calldata isWhiteListed
    ) external onlyBot {
        require(targets.length == isWhiteListed.length, "DODOGasProxy: LENGTH_MISMATCH");
        
        for (uint256 i = 0; i < targets.length; i++) {
            isWhiteListedContract[targets[i]] = isWhiteListed[i];
            emit WhiteListChanged(targets[i], isWhiteListed[i]);
        }
    }

    /// @notice Batch set approve contract whitelist status
    /// @param targets Array of target addresses
    /// @param isWhiteListed Array of whitelist status
    function batchSetWhiteListApproveContract(
        address[] calldata targets,
        bool[] calldata isWhiteListed
    ) external onlyBot {
        require(targets.length == isWhiteListed.length, "DODOGasProxy: LENGTH_MISMATCH");
        
        for (uint256 i = 0; i < targets.length; i++) {
            isWhiteListedApproveContract[targets[i]] = isWhiteListed[i];
            emit WhiteListApproveChanged(targets[i], isWhiteListed[i]);
        }
    }

    // ============ Main Functions ============

    /// @notice Execute transaction through proxy and charge gas fee
    /// @param chainId Target chain ID
    /// @param fromToken Source token address
    /// @param fromTokenAmount Amount of source tokens
    /// @param approveTarget Address to approve tokens for
    /// @param executeTarget Contract to execute call on
    /// @param transferInGasFee Extra amount of gas fee transferred in
    /// @param transferbridgeGasFee Extra amount of gas fee for bridge transferred in
    /// @param nativeDrip Extra amount of native token to drip to target contract
    /// @param callData Call data for target contract
    function proxyCall(
        uint64 chainId,
        address fromToken,
        uint256 fromTokenAmount,
        address approveTarget,
        address executeTarget,
        uint256 transferInGasFee,
        uint256 transferbridgeGasFee,
        uint256 nativeDrip,
        bytes calldata callData
    ) external payable whenNotPaused returns (bytes memory) {
        // Check if target contract is whitelisted
        require(isWhiteListedApproveContract[approveTarget], "DODOGasProxy: NOT_WHITELISTED");
        require(isWhiteListedContract[executeTarget], "DODOGasProxy: NOT_WHITELISTED");
        
        // Check and collect gas fee
        require(chainGasFee[chainId] > 0 && bridgeGasFee[chainId] > 0, "DODOGasProxy: GAS_FEE_NOT_SET");
        require(transferInGasFee >= chainGasFee[chainId], "DODOGasProxy: INSUFFICIENT_TRANSFER_IN_GAS_FEE");
        require(transferbridgeGasFee >= bridgeGasFee[chainId], "DODOGasProxy: INSUFFICIENT_BRIDGE_GAS_FEE");

        
        // Transfer user tokens
        if(fromToken == _ETH_ADDRESS_) {
            require(msg.value >= fromTokenAmount + transferInGasFee + transferbridgeGasFee + nativeDrip, "DODOGasProxy: INVALID_ETH_AMOUNT");
        } else {
            require(msg.value >= transferInGasFee + transferbridgeGasFee + nativeDrip, "DODOGasProxy: INVALID_GAS_FEE");
            // Use DODOApproveProxy to claim tokens instead of transferFrom
            IDODOApproveProxy(_DODO_APPROVE_PROXY_).claimTokens(
                fromToken,
                msg.sender,
                address(this),
                fromTokenAmount
            );
            // Approve target contract if needed
            if(approveTarget != address(0)) {
                IERC20(fromToken).safeApprove(approveTarget, fromTokenAmount);
            }
        }
        
        // generate externalID
        nonce++;
        bytes32 externalID = keccak256(abi.encodePacked(block.timestamp, msg.sender, chainId, transferInGasFee, transferbridgeGasFee, nonce));
        totalGasFee += transferInGasFee;
        totalBridgeGasFee += transferbridgeGasFee;
        emit GasFeePaid(msg.sender, chainId, transferInGasFee, externalID);
        emit BridgeGasFeePaid(msg.sender, chainId, transferbridgeGasFee, externalID);

        // Call target contract
        (bool success, bytes memory result) = executeTarget.call{
            value: fromToken == _ETH_ADDRESS_ ? fromTokenAmount + nativeDrip : nativeDrip
        }(callData);

        if(nativeDrip > 0) {
            emit NativeDrip(msg.sender, chainId, nativeDrip, externalID);
        }
        
        require(success, "DODOGasProxy: CALL_FAILED");
        return result;
    }

    function getChainGasFee() public view returns (ChainGasFee[] memory) {
        ChainGasFee[] memory list = new ChainGasFee[](chainIndexs.length);
        for (uint256 i = 0; i < chainIndexs.length; i++) {
            list[i] = ChainGasFee(chainIndexs[i], chainGasFee[chainIndexs[i]]);
        }
        return list;
    }

    function getBridgeGasFee() public view returns (BridgeGasFee[] memory) {
        BridgeGasFee[] memory list = new BridgeGasFee[](bridgeIndexs.length);
        for (uint256 i = 0; i < bridgeIndexs.length; i++) {
            list[i] = BridgeGasFee(bridgeIndexs[i], bridgeGasFee[bridgeIndexs[i]]);
        }
        return list;
    }

    receive() external payable {}
    fallback() external payable {}
}
