/*

    Copyright 2023 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;

interface IThenaPool {
    function getAmountOut(uint amountIn, address tokenIn) external view returns (uint);

    function reserve0() external returns(uint);
    function reserve1() external returns(uint);

    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

}