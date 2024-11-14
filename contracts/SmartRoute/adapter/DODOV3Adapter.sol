/*

    Copyright 2022 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;

import {ID3MM} from "../intf/ID3MM.sol";
import {ID3Factory} from "../intf/ID3Factory.sol";
import {IDODOSwapCallback} from "../intf/IDODOSwapCallback.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IDODOAdapter {
    
    function sellBase(address to, address pool, bytes memory data) external;

    function sellQuote(address to, address pool, bytes memory data) external;
}

contract D3Adapter is IDODOSwapCallback, IDODOAdapter {
    using SafeERC20 for IERC20;

    function sellBase(address to, address pool, bytes memory data) public {
        _d3Swap(to, pool, data);
    }

    function sellQuote(address to, address pool, bytes memory data) public {
        _d3Swap(to, pool, data);
    }

    function _d3Swap(address to, address pool, bytes memory data) internal {
        (address fromToken, address toToken, address factoryAddress) = abi.decode(data, (address, address, address));
        uint256 sellAmount = IERC20(fromToken).balanceOf(address(this));
        
        ID3MM(pool).sellToken(to, fromToken, toToken, sellAmount, 0, data);
    }


    /// @notice This callback is used to deposit token into D3MM
    /// @param token The address of token
    /// @param value The amount of token need to deposit to D3MM
    /// @param _data Any data to be passed through to the callback
    function d3MMSwapCallBack(
        address token,
        uint256 value,
        bytes calldata _data
    ) external override {
        (address fromToken, address toToken, address factoryAddress) = abi.decode(_data, (address, address, address));

        require(
            ID3Factory(factoryAddress)._POOL_WHITELIST_(msg.sender),
            "D3ADAPTER_CALLBACK_INVALID"
        );
        require(fromToken == token, "D3ADAPTER_TOKEN_ILLEGAL");

        SafeERC20.safeTransfer(IERC20(token), msg.sender, value);
    }
}