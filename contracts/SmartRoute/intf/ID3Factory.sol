/*

    Copyright 2020 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;

interface ID3Factory {
    function createDToken(address, address) external returns (address);
    function addLiquidator(address) external;
    function _LIQUIDATOR_WHITELIST_(address) external returns (bool);
    function _ROUTER_WHITELIST_(address) external returns (bool);
    function _POOL_WHITELIST_(address) external returns (bool);
}
