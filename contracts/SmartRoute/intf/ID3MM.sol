/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;

interface ID3MM {
    function getCreator() external returns (address);

    /*
        mixData includes:
        uint256 IM,
        uint256 MM,
        address maintainer,
        address feeRateModel
    */
    function init(
        address creator,
        address factory,
        address oracle,
        uint256 epochStartTime,
        uint256 epochDuration,
        address[] calldata tokens,
        address[] calldata d3Tokens,
        bytes calldata mixData
    ) external;

    function sellToken(
        address to,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minReceiveAmount,
        bytes calldata data
    ) external returns(uint256);

    function buyToken(
        address to,
        address fromToken,
        address toToken,
        uint256 quoteAmount,
        uint256 maxPayAmount,
        bytes calldata data
    ) external returns(uint256);

    function lpDeposit(address lp, address token) external;
    function ownerDeposit(address token) external;
}
