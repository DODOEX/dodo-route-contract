/*

    Copyright 2022 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDODOAdapter} from "../intf/IDODOAdapter.sol";
import {ISyncPool} from "../intf/ISyncPool.sol";

interface ISyncVault {
    function deposit(address token, address to) external returns(uint amount);
}

contract SyncSwapAdapter is IDODOAdapter {

    address public vault;
    constructor(address _vault) {
        vault = _vault;
    }

    function _swap(address pool, address to, bytes memory moreInfo) internal {
        address tokenIn = abi.decode(moreInfo, (address));
        bytes memory paramData = abi.encode(tokenIn, to, 2);
        ISyncVault(vault).deposit(tokenIn, pool);
        ISyncPool(pool).swap(paramData, address(this), address(0), "");
    }

    function sellBase(address to, address pool, bytes memory moreInfo) public { // sell token0
        _swap(pool, to, moreInfo);
    }

    function sellQuote(address to, address pool, bytes memory moreInfo) public { // sell token1
        _swap(pool, to, moreInfo);
    }
}