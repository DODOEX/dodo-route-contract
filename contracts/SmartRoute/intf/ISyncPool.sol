/*

    Copyright 2023 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;

interface ISyncPool {
    struct TokenAmount {
        address token;
        uint amount;
    }
    
    function swap(
        bytes calldata _data,
        address _sender,
        address _callback,
        bytes calldata _callbackData
    ) external returns(TokenAmount memory _tokenAmount);

}