/*

    Copyright 2021 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import { IDODOApproveProxy } from "../DODOApproveProxy.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "../intf/IWETH.sol";
import { DecimalMath } from "../lib/DecimalMath.sol";
import { UniversalERC20 } from "./lib/UniversalERC20.sol";
import { IDODOAdapter } from "./intf/IDODOAdapter.sol";
import { InitializableOwnable } from "../lib/InitializableOwnable.sol";

/**
 * @title DODORouteProxy
 * @author DODO Breeder
 *
 * @notice Entrance of Split trading in DODO platform
 */
contract DODORouteProxy is InitializableOwnable {
    using SafeMath for uint256;
    using UniversalERC20 for IERC20;

    // ============ Storage ============

    address constant _ETH_ADDRESS_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public immutable _WETH_;
    address public immutable _DODO_APPROVE_PROXY_;
    mapping(address => bool) public isWhiteListedContract; // is safe for external call

    uint256 public routeFeeRate;
    address public routeFeeReceiver;

    struct PoolInfo {
        uint256 direction;
        uint256 poolEdition;
        uint256 weight;
        address pool;
        address adapter;
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

    function changeRouteFeeRate(uint256 newFeeRate) public onlyOwner {
        routeFeeRate = newFeeRate;
    }
  
    function changeRouteFeeReceiver(address newFeeReceiver) public onlyOwner {
        routeFeeReceiver = newFeeReceiver;
    }

    // ============ Swap ============

    // Call external black box contracts to finish a swap
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
        address _toToken = toToken;
        address _fromToken = fromToken;
        
        // approve if needed
        if (approveTarget != address(0)) {
            IERC20(_fromToken).universalApproveMax(approveTarget, fromTokenAmount);
        }

        // transfer in fromToken
        if (_fromToken != _ETH_ADDRESS_) {
            IDODOApproveProxy(_DODO_APPROVE_PROXY_).claimTokens(
                _fromToken,
                msg.sender,
                address(this),
                fromTokenAmount
            );
        }

        // swap
        uint256 toTokenOriginBalance = IERC20(_toToken).universalBalanceOf(address(this));
        {
            require(isWhiteListedContract[swapTarget], "DODORouteProxy: Not Whitelist Contract");
            // TODO: require swapTarget != _DODO_APPROVE_PROXY_
            require(swapTarget != _DODO_APPROVE_PROXY_, "DODORouteProxy: Risk Target");
            (bool success, bytes memory result) = swapTarget.call{
                value: _fromToken == _ETH_ADDRESS_ ? fromTokenAmount : 0
            }(callDataConcat);
            // revert with lowlevel info
            if (success == false) {
                assembly {
                    revert(add(result,32),mload(result))
                }
            }
        }

        // distribute toToken
        receiveAmount = IERC20(_toToken).universalBalanceOf(address(this)).sub(
            toTokenOriginBalance
        );
        
        _routeWithdraw(toToken, receiveAmount, feeData, minReturnAmount);

        emit OrderHistory(_fromToken, _toToken, msg.sender, fromTokenAmount, receiveAmount);
    }

    // linear version
    /// @param mixAdapters: adapter
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

        uint256 toTokenOriginBalance = IERC20(_toToken).universalBalanceOf(address(this));

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

        // distribute toToken
        
        receiveAmount = IERC20(_toToken).tokenBalanceOf(address(this)).sub(
                toTokenOriginBalance
            );
        }
        _routeWithdraw(_toToken, receiveAmount, feeData, minReturnAmount);

        emit OrderHistory(fromToken, toToken, msg.sender, fromTokenAmount, receiveAmount);
    }

    // split version
    function dodoMutliSwap(
        uint256 fromTokenAmount,
        uint256 minReturnAmount,
        uint256[] memory totalWeight, // TODO: fix totalWeight and del this param
        uint256[] memory splitNumber, // [1, 3] 记录下标  
        address[] memory midToken,
        address[] memory assetFrom,
        bytes[] memory sequence, // pairSequence
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
        

        uint256 toTokenOriginBalance = IERC20(toToken).universalBalanceOf(address(this));

        _deposit(
            msg.sender,
            assetFrom[0],
            fromToken,
            _fromTokenAmount,
            fromToken == _ETH_ADDRESS_
        );

        _multiSwap(totalWeight, midToken, splitNumber, sequence, assetFrom);

        receiveAmount = IERC20(toToken).tokenBalanceOf(address(this)).sub(
            toTokenOriginBalance
        );
        }
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

    function _multiSwap(
        uint256[] memory totalWeight,
        address[] memory midToken,
        uint256[] memory splitNumber,
        bytes[] memory swapSequence,
        address[] memory assetFrom
    ) internal {
        for (uint256 i = 1; i < splitNumber.length; i++) {
            // define midtoken address, ETH -> WETH address
            uint256 curTotalAmount = IERC20(midToken[i]).tokenBalanceOf(assetFrom[i - 1]);
            uint256 curTotalWeight = totalWeight[i - 1];

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

                if (assetFrom[i - 1] == address(this)) {
                    uint256 curAmount = curTotalAmount.mul(curPoolInfo.weight).div(curTotalWeight);

                    if (curPoolInfo.poolEdition == 1) {
                        //For using transferFrom pool (like dodoV1, Curve)
                        IERC20(midToken[i]).transfer(curPoolInfo.adapter, curAmount);
                    } else {
                        //For using transfer pool (like dodoV2)
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
    // TODO 出金部分统一
    // TODO 添加注释

    function _routeWithdraw(
        address toToken,
        uint256 receiveAmount,
        bytes memory feeData,
        uint256 minReturnAmount
    ) internal {
        (address broker, uint256 brokerFeeRate) = abi.decode(feeData, (address, uint256));

        uint256 routeFee = DecimalMath.mulFloor(receiveAmount, routeFeeRate);
        IERC20(toToken).universalTransfer(payable(routeFeeReceiver), routeFee);

        uint256 brokerFee = DecimalMath.mulFloor(receiveAmount, brokerFeeRate);
        IERC20(toToken).universalTransfer(payable(broker), brokerFee);
        
        receiveAmount = receiveAmount.sub(routeFee).sub(brokerFee);
        require(receiveAmount >= minReturnAmount, "DODORouteProxy: Return amount is not enough");
        
        if (toToken == _ETH_ADDRESS_) {
            IWETH(_WETH_).withdraw(receiveAmount);
            payable(msg.sender).transfer(receiveAmount);
        } else {
            IERC20(toToken).universalTransfer(payable(msg.sender), receiveAmount);
        }
    }
}

