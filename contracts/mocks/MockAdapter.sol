/*

    Copyright 2021 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import { IDODOAdapter } from "../SmartRoute/intf/IDODOAdapter.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { DecimalMath } from "../lib/DecimalMath.sol";
import "hardhat/console.sol";

contract MockAdapter is IDODOAdapter{
    using SafeMath for uint256;

    address _ETH_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address immutable public _BASE_;
    address immutable public _QUOTE_;
    uint256 public price; //unit is 10**18
    uint256 public baseReserve;
    uint256 public quoteReserve;

    constructor(address base, address quote, uint256 _price) {
        _BASE_ = base;
        _QUOTE_  = quote;
        console.log("init price:", _price);
        price = _price;
    }

    function setPrice(uint256 _newPrice) public {
        price = _newPrice;
    }

    function update() public {
        baseReserve = IERC20(_BASE_).balanceOf(address(this));
        quoteReserve = IERC20(_QUOTE_).balanceOf(address(this));
    }

    function sellBase(address to, address pool, bytes memory data) external override {
        uint256 quotePrice = DecimalMath.reciprocalFloor(price);
        console.log("quote Price:", quotePrice, price);
        uint256 baseIn = IERC20(_BASE_).balanceOf(address(this)) - baseReserve;
        console.log("baseIn:", baseIn);
        uint256 outQuote = DecimalMath.mulFloor(baseIn, quotePrice);
        console.log("outQuote:", outQuote);
        IERC20(_QUOTE_).transfer(to, outQuote);

        update();
    }

    function sellQuote(address to, address pool, bytes memory data) external override {
        console.log("base Price:", price);
        uint256 quoteIn = IERC20(_QUOTE_).balanceOf(address(this)) - quoteReserve;
        console.log("quoteIn:", quoteIn);
        uint256 outBase = DecimalMath.mulFloor(quoteIn, price);
        console.log("outBase:", outBase);
        IERC20(_BASE_).transfer(to, outBase);
        
        update();
    }

    function externalSwap(address to, address fromToken, address toToken, uint256 fromAmount) external payable{
        if(fromToken != _ETH_) {
            IERC20(fromToken).transferFrom(msg.sender, address(this), fromAmount);
        } 
        uint256 outAmount = DecimalMath.mulFloor(fromAmount, price);
        IERC20(toToken).transfer(to, outAmount);
    }

    function externalSwapFail(address to, address fromToken, address toToken, uint256 fromAmount) external payable{
        require(false, "external swap failed");
    }
}