/*

    Copyright 2022 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDODOAdapter} from "../intf/IDODOAdapter.sol";
import {IThenaPool} from "../intf/IThenaPool.sol";


contract ThenaAdapter is IDODOAdapter {

    function sellBase(address to, address pool, bytes memory moreInfo) public { // sell token0
        (address fromToken, ) = abi.decode(moreInfo,(address, address));
        uint balance = IERC20(fromToken).balanceOf(pool);

        uint reserve0 = IThenaPool(pool).reserve0();
        uint amountIn0 = balance > reserve0 ? balance - reserve0 : 0;
        uint amountOut1 = IThenaPool(pool).getAmountOut(amountIn0, fromToken);

        IThenaPool(pool).swap(0, amountOut1, to, "");
    }

    function sellQuote(address to, address pool, bytes memory moreInfo) public { // sell token1
        (address fromToken, ) = abi.decode(moreInfo,(address, address));
        uint balance = IERC20(fromToken).balanceOf(pool);

        uint reserve1 = IThenaPool(pool).reserve1();
        uint amountIn1 = balance > reserve1 ? balance - reserve1 : 0;
        uint amountOut0 = IThenaPool(pool).getAmountOut(amountIn1, fromToken);

        IThenaPool(pool).swap(amountOut0, 0, to, "");
    }
}