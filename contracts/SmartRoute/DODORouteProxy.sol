/*

    Copyright 2021 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import { IDODOApproveProxy } from "../DODOApproveProxy.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "../intf/IWETH.sol";
import { DecimalMath } from "../lib/DecimalMath.sol";
import { UniversalERC20 } from "./lib/UniversalERC20.sol";
import { IDODOAdapter } from "./intf/IDODOAdapter.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title DODORouteProxy
/// @author DODO Breeder
/// @notice new routeProxy contract with fee rebate to manage all route. It provides three methods to swap, 
/// including mixSwap, multiSwap and externalSwap. Mixswap is for linear swap, which describes one token path 
/// with one pool each time. Multiswap is a simplified version about 1inch, which describes one token path 
/// with several pools each time. ExternalSwap is for other routers like 0x, 1inch and paraswap. Dodo and 
/// front-end users could take certain route fee rebate from each swap. Wherein dodo will get a fixed percentage, 
/// and front-end users could assign any proportion through function parameters.
/// @dev dependence: DODOApprove.sol / DODOApproveProxy.sol / IDODOAdapter.sol
/// DODOApprove and DODOApproveProxy used to manage user's token, all user's token must be claimed through DODOApproveProxy and DODOApprove
/// IDODOAdapter determine the interface of adapter, in which swap happened. There are different adapters for different
/// pools. Adapter addresses are parameters contructed off chain so they are loose coupling with routeProxy.
/// adapters have two interface functions. func sellBase(address to, address pool, bytes memory moreInfo) and func sellQuote(address to, address pool, bytes memory moreInfo)

contract DODORouteProxy is Ownable {

    using UniversalERC20 for IERC20;

    // ============ Storage ============

    address constant _ETH_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public immutable _WETH_;
    // dodo appprove proxy address, the only entrance to get user's token
    address public immutable _DODO_APPROVE_PROXY_;
    // used in multiSwap for split, sum of pool weight must equal totalWeight
    // in PoolInfo, pool weight has 8 bit, so totalWeight < 2**8
    uint256 public totalWeight = 100;
    // check safe safe for external call, add trusted external swap contract, 0x,1inch, paraswap
    // only owner could manage
    mapping(address => bool) public isWhiteListedContract; 
    // check safe for external approve, add trusted external swap approve contract, 0x, 1inch, paraswap
    // only owner could manage
    // Specially for 0x swap from eth, add zero address
    mapping(address => bool) public isApproveWhiteListedContract; 

    // dodo route fee rate, unit is 10**18
    uint256 public routeFeeRate; 
    // dodo route fee receiver
    address public routeFeeReceiver;

    struct PoolInfo {
        // pool swap direciton, 0 is for sellBase, 1 is for sellQuote
        uint256 direction;
        // distinct transferFrom pool(like dodoV1) and transfer pool
        // 1 is for transferFrom pool, pool call transferFrom function to get tokens from adapter
        // 2 is for transfer pool, pool determine swapAmount through balanceOf(Token) - reserve
        uint256 poolEdition;
        // pool weight, actualWeight = weight/totalWeight, totalAmount * actualWeight = amount through this pool swap
        uint256 weight;
        // pool address
        address pool;
        // pool adapter, making actual swap call in corresponding adapter
        address adapter;
        // pool adapter's Info, record addtional infos(could be zero-bytes) needed by each pool adapter
        bytes moreInfo;
    }

    // ============ Events ============

    event OrderHistory(
        address fromToken,
        address toToken,
        address sender,
        uint256 fromAmount,
        uint256 returnAmount
    );

    // ============ Modifiers ============

    modifier judgeExpired(uint256 deadLine) {
        require(deadLine >= block.timestamp, "DODORouteProxy: EXPIRED");
        _;
    }

    fallback() external payable {}

    receive() external payable {}

    // ============ Constructor ============

    constructor(address payable weth, address dodoApproveProxy) public {
        _WETH_ = weth;
        _DODO_APPROVE_PROXY_ = dodoApproveProxy;
    }

    // ============ Owner only ============

    function addWhiteList(address contractAddr) public onlyOwner {
        isWhiteListedContract[contractAddr] = true;
    }

    function removeWhiteList(address contractAddr) public onlyOwner {
        isWhiteListedContract[contractAddr] = false;
    }

    function addApproveWhiteList(address contractAddr) public onlyOwner {
        isApproveWhiteListedContract[contractAddr] = true;
    }

    function removeApproveWhiteList(address contractAddr) public onlyOwner {
        isApproveWhiteListedContract[contractAddr] = false;
    }

    function changeRouteFeeRate(uint256 newFeeRate) public onlyOwner {
        routeFeeRate = newFeeRate;
    }
  
    function changeRouteFeeReceiver(address newFeeReceiver) public onlyOwner {
        routeFeeReceiver = newFeeReceiver;
    }

    function changeTotalWeight(uint256 newTotalWeight) public onlyOwner {
        require(newTotalWeight < 2 ** 8, "DODORouteProxy: totalWeight overflowed");
        totalWeight = newTotalWeight;
    }

    /// @notice used for emergency, generally there wouldn't be tokens left
    function superWithdraw(address token) public onlyOwner {
        if(token != _ETH_ADDRESS_) {
            uint256 restAmount = IERC20(token).universalBalanceOf(address(this));
            IERC20(token).universalTransfer(payable(routeFeeReceiver), restAmount);
        } else {
            uint256 restAmount = address(this).balance;
            payable(routeFeeReceiver).transfer(restAmount);
        }
    }

    // ============ Swap ============


    /// @notice Call external black box contracts to finish a swap
    /// @param approveTarget external swap approve address
    /// @param swapTarget external swap address
    /// @param feeData route fee info
    /// @param callDataConcat external swap data
    function externalSwap(
        address fromToken,
        address toToken,
        address approveTarget,
        address swapTarget,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        bytes memory feeData,
        bytes memory callDataConcat,
        uint256 deadLine
    ) external payable judgeExpired(deadLine) returns (uint256 receiveAmount) {      
        require(isWhiteListedContract[swapTarget], "DODORouteProxy: Not Whitelist Contract");  
        require(isApproveWhiteListedContract[approveTarget], "DODORouteProxy: Not Whitelist Appprove Contract");  

        // transfer in fromToken
        if (fromToken != _ETH_ADDRESS_) {
            // approve if needed
            if (approveTarget != address(0)) {
                IERC20(fromToken).universalApproveMax(approveTarget, fromTokenAmount);
            }

            IDODOApproveProxy(_DODO_APPROVE_PROXY_).claimTokens(
                fromToken,
                msg.sender,
                address(this),
                fromTokenAmount
            );
        }

        // swap
        uint256 toTokenOriginBalance;
        if(toToken != _ETH_ADDRESS_) {
            toTokenOriginBalance = IERC20(toToken).universalBalanceOf(address(this));
        } else {
            toTokenOriginBalance = IERC20(_WETH_).universalBalanceOf(address(this));
        }

        {
            require(swapTarget != _DODO_APPROVE_PROXY_, "DODORouteProxy: Risk Target");
            (bool success, bytes memory result) = swapTarget.call{
                value: fromToken == _ETH_ADDRESS_ ? fromTokenAmount : 0
            }(callDataConcat);
            // revert with lowlevel info
            if (success == false) {
                assembly {
                    revert(add(result,32),mload(result))
                }
            }
        }

        // calculate toToken amount
        if(toToken != _ETH_ADDRESS_) {
            receiveAmount = IERC20(toToken).universalBalanceOf(address(this)) - (
                toTokenOriginBalance
            );
        } else {
            receiveAmount = IERC20(_WETH_).universalBalanceOf(address(this)) - (
                toTokenOriginBalance
            );
        }
        
        // distribute toToken
        _routeWithdraw(toToken, receiveAmount, feeData, minReturnAmount);

        emit OrderHistory(fromToken, toToken, msg.sender, fromTokenAmount, receiveAmount);
    }

    /// @notice linear version, describes one token path with one pool each time
    /// @param mixAdapters adapter address array, record each pool's interrelated adapter in order
    /// @param mixPairs pool address array, record pool address of the whole route in order
    /// @param assetTo asset Address（pool or proxy）, describe pool adapter's receiver address. Specially assetTo[0] is deposit receiver before all
    /// @param directions pool directions aggregation, one bit represent one pool direction, 0 means sellBase, 1 means sellQuote
    /// @param moreInfos pool adapter's Info set, record addtional infos(could be zero-bytes) needed by each pool adapter, keeping order with adapters
    /// @param feeData route fee info, bytes decode into broker and brokerFee, determine rebate proportion, brokerFee in [0, 1e18]
    function mixSwap(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        address[] memory mixAdapters,
        address[] memory mixPairs,
        address[] memory assetTo,
        uint256 directions,
        bytes[] memory moreInfos,
        bytes memory feeData,
        uint256 deadLine
    ) external payable judgeExpired(deadLine) returns (uint256 receiveAmount) {
        require(mixPairs.length > 0, "DODORouteProxy: PAIRS_EMPTY");
        require(mixPairs.length == mixAdapters.length, "DODORouteProxy: PAIR_ADAPTER_NOT_MATCH");
        require(mixPairs.length == assetTo.length - 1, "DODORouteProxy: PAIR_ASSETTO_NOT_MATCH");
        require(minReturnAmount > 0, "DODORouteProxy: RETURN_AMOUNT_ZERO");

        address _toToken = toToken;
        {
        uint256 _fromTokenAmount = fromTokenAmount;
        address _fromToken = fromToken;

        uint256 toTokenOriginBalance;
        if(_toToken != _ETH_ADDRESS_) {
            toTokenOriginBalance = IERC20(_toToken).universalBalanceOf(address(this));
        } else {
            toTokenOriginBalance = IERC20(_WETH_).universalBalanceOf(address(this));
        }

        // transfer in fromToken
        _deposit(
            msg.sender,
            assetTo[0],
            _fromToken,
            _fromTokenAmount,
            _fromToken == _ETH_ADDRESS_
        );

        // swap
        for (uint256 i = 0; i < mixPairs.length; i++) {
            if (directions & 1 == 0) {
                IDODOAdapter(mixAdapters[i]).sellBase(
                    assetTo[i + 1],
                    mixPairs[i],
                    moreInfos[i]
                );
            } else {
                IDODOAdapter(mixAdapters[i]).sellQuote(
                    assetTo[i + 1],
                    mixPairs[i],
                    moreInfos[i]
                );
            }
            directions = directions >> 1;
        }

        // calculate toToken amount
        if(_toToken != _ETH_ADDRESS_) {
            receiveAmount = IERC20(_toToken).universalBalanceOf(address(this)) - (
                toTokenOriginBalance
            );
        } else {
            receiveAmount = IERC20(_WETH_).universalBalanceOf(address(this)) - (
                toTokenOriginBalance
            );
        }
        }

        // distribute toToken
        _routeWithdraw(_toToken, receiveAmount, feeData, minReturnAmount);

        emit OrderHistory(fromToken, toToken, msg.sender, fromTokenAmount, receiveAmount);
    }

    /// @notice split version, describes one token path with several pools each time. Called one token pair with several pools "one split"
    /// @param splitNumber record pool number in one split, determine sequence(poolInfo) array subscript in transverse. Begin with 0
    /// for example, [0,1, 3], mean the first split has one(1 - 0) pool, the second split has 2 (3 - 1) pool
    /// @param midToken middle token set, record token path in order. 
    /// Specially midToken[1] is WETH addresss when fromToken is ETH. Besides midToken[1] is also fromToken 
    /// Specially midToken[length - 2] is WETH address and midToken[length -1 ] is ETH address when toToken is ETH. Besides midToken[length -1]
    /// is the last toToken and midToken[length - 2] is common second last middle token.
    /// @param assetFrom asset Address（pool or proxy）describe pool adapter's receiver address. Specially assetFrom[0] is deposit receiver before all
    /// @param sequence PoolInfo sequence, describe each pool's attributions, ordered by spiltNumber
    /// @param feeData route fee info, bytes decode into broker and brokerFee, determine rebate proportion, brokerFee in [0, 1e18]
    function dodoMutliSwap(
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        uint256[] memory splitNumber,  
        address[] memory midToken,
        address[] memory assetFrom,
        bytes[] memory sequence, 
        bytes memory feeData,
        uint256 deadLine
    ) external payable judgeExpired(deadLine) returns (uint256 receiveAmount) {
        address toToken = midToken[midToken.length - 1];
        {
        require(
            assetFrom.length == splitNumber.length,
            "DODORouteProxy: PAIR_ASSETTO_NOT_MATCH"
        );
        require(minReturnAmount > 0, "DODORouteProxy: RETURN_AMOUNT_ZERO");
        uint256 _fromTokenAmount = fromTokenAmount;
        address fromToken = midToken[0];

        uint256 toTokenOriginBalance;
        if(toToken != _ETH_ADDRESS_) {
            toTokenOriginBalance = IERC20(toToken).universalBalanceOf(address(this));
        } else {
            toTokenOriginBalance = IERC20(_WETH_).universalBalanceOf(address(this));
        }

        // transfer in fromToken
        _deposit(
            msg.sender,
            assetFrom[0],
            fromToken,
            _fromTokenAmount,
            fromToken == _ETH_ADDRESS_
        );

        // swap
        _multiSwap(midToken, splitNumber, sequence, assetFrom);

        // calculate toToken amount
        if(toToken != _ETH_ADDRESS_) {
            receiveAmount = IERC20(toToken).universalBalanceOf(address(this)) - (
                toTokenOriginBalance
            );
        } else {
            receiveAmount = IERC20(_WETH_).universalBalanceOf(address(this)) - (
                toTokenOriginBalance
            );
        }
        }
        // distribute toToken
        _routeWithdraw(toToken, receiveAmount, feeData, minReturnAmount);

        emit OrderHistory(
            midToken[0], //fromToken
            midToken[midToken.length - 1], //toToken
            msg.sender,
            fromTokenAmount,
            receiveAmount
        );
    }

    //====================== internal =======================
    /// @notice multiSwap process
    function _multiSwap(
        address[] memory midToken,
        uint256[] memory splitNumber,
        bytes[] memory swapSequence,
        address[] memory assetFrom
    ) internal {
        for (uint256 i = 1; i < splitNumber.length; i++) {
            // define midtoken address, ETH -> WETH address
            uint256 curTotalAmount = IERC20(midToken[i]).tokenBalanceOf(assetFrom[i - 1]);
            uint256 curTotalWeight = totalWeight;

            // one split all pool swap
            for (uint256 j = splitNumber[i - 1]; j < splitNumber[i]; j++) {
                PoolInfo memory curPoolInfo;
                {
                    (address pool, address adapter, uint256 mixPara, bytes memory moreInfo) = abi
                        .decode(swapSequence[j], (address, address, uint256, bytes));

                    curPoolInfo.direction = mixPara >> 17;
                    curPoolInfo.weight = (0xffff & mixPara) >> 9;
                    curPoolInfo.poolEdition = (0xff & mixPara);
                    curPoolInfo.pool = pool;
                    curPoolInfo.adapter = adapter;
                    curPoolInfo.moreInfo = moreInfo;
                }

                // assetFrom[i - 1] is routeProxy when there are more than one pools in this split
                if (assetFrom[i - 1] == address(this)) {
                    uint256 curAmount = curTotalAmount * curPoolInfo.weight / curTotalWeight;

                    if (curPoolInfo.poolEdition == 1) {
                        //For using transferFrom pool (like dodoV1, Curve), pool call transferFrom function to get tokens from adapter
                        IERC20(midToken[i]).transfer(curPoolInfo.adapter, curAmount);
                    } else {
                        //For using transfer pool (like dodoV2), pool determine swapAmount through balanceOf(Token) - reserve
                        IERC20(midToken[i]).transfer(curPoolInfo.pool, curAmount);
                    }
                }

                if (curPoolInfo.direction == 0) {
                    IDODOAdapter(curPoolInfo.adapter).sellBase(
                        assetFrom[i],
                        curPoolInfo.pool,
                        curPoolInfo.moreInfo
                    );
                } else {
                    IDODOAdapter(curPoolInfo.adapter).sellQuote(
                        assetFrom[i],
                        curPoolInfo.pool,
                        curPoolInfo.moreInfo
                    );
                }
            }
        }
    }

    /// @notice In dodo's contract system, there is only one approve entrance DODOApprove.sol.
    /// before the first pool swap, contract call _deposit to get ERC20 token through DODOApprove/transfer ETH to WETH
    function _deposit(
        address from,
        address to,
        address token,
        uint256 amount,
        bool isETH
    ) internal {
        if (isETH) {
            if (amount > 0) {
                require(msg.value == amount, "ETH_VALUE_WRONG");
                IWETH(_WETH_).deposit{value: amount}();
                if (to != address(this)) SafeERC20.safeTransfer(IERC20(_WETH_), to, amount);
            }
        } else {
            IDODOApproveProxy(_DODO_APPROVE_PROXY_).claimTokens(token, from, to, amount);
        }
    }

    /// @notice after all swaps, transfer tokens to original receiver(user) and distribute fees to DODO and broker
    /// Specially when toToken is ETH, distribute WETH
    function _routeWithdraw(
        address toToken,
        uint256 receiveAmount,
        bytes memory feeData,
        uint256 minReturnAmount
    ) internal {
        address originToToken = toToken;
        if(toToken == _ETH_ADDRESS_) {
            toToken = _WETH_;
        }
        (address broker, uint256 brokerFeeRate) = abi.decode(feeData, (address, uint256));

        uint256 routeFee = DecimalMath.mulFloor(receiveAmount, routeFeeRate);
        IERC20(toToken).universalTransfer(payable(routeFeeReceiver), routeFee);

        uint256 brokerFee = DecimalMath.mulFloor(receiveAmount, brokerFeeRate);
        IERC20(toToken).universalTransfer(payable(broker), brokerFee);
        
        receiveAmount = receiveAmount - routeFee - brokerFee;
        require(receiveAmount >= minReturnAmount, "DODORouteProxy: Return amount is not enough");
        
        if (originToToken == _ETH_ADDRESS_) {
            IWETH(_WETH_).withdraw(receiveAmount);
            payable(msg.sender).transfer(receiveAmount);
        } else {
            IERC20(toToken).universalTransfer(payable(msg.sender), receiveAmount);
        }
    }
}

