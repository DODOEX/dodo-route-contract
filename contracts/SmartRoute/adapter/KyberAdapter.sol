/*

    Copyright 2023 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


interface IDODOAdapter {
     function sellBase(address to, address pool, bytes memory moreInfo) external ;
     function sellQuote(address to, address pool, bytes memory moreInfo) external;
}

interface ISwapCallback {
    function swapCallback(
        int256 deltaQty0,
        int256 deltaQty1,
        bytes calldata data
    ) external;
}

interface IPool {
    function swap(
        address recipient,
        int256 swapQty,
        bool isToken0,
        uint160 limitSqrtP,
        bytes calldata data
    ) external returns (int256 qty0, int256 qty1);
}

interface IFactory {
    function getPool(address, address, uint24) external view returns(address);
}

contract KyberAdapter is IDODOAdapter, ISwapCallback {
    using SafeERC20 for IERC20;

    address immutable public factory;
    uint256 immutable public MIN_SQRT_RATIO = 4295128739;
    uint256 immutable public MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    
    constructor(address _factory) {
        factory = _factory;
    }

    function _swap(address pool, address to, bool _isToken0, bytes memory data) internal {
        (address tokenIn, ,) = abi.decode(data, (address, address, uint24));
        uint256 _swapQty = IERC20(tokenIn).balanceOf(address(this));
        uint160 _limitSqrtP = _isToken0 ? 4295128740 : 1461446703485210103287273052203988822378723970341;

        IPool(pool).swap(to, int256(_swapQty), _isToken0, _limitSqrtP, data);
    }
    
    function sellBase(address to, address pool, bytes memory moreInfo) 
    external override {
        _swap(pool, to, true, moreInfo);

    }

    function sellQuote(address to, address pool, bytes memory moreInfo) 
    external override {
        _swap(pool, to, false, moreInfo);
    }

    function swapCallback(
        int256 deltaQty0,
        int256 deltaQty1,
        bytes calldata data
      ) external override {
        require(deltaQty0 > 0 || deltaQty1 > 0, "adapter: invalid delta qties");
        //SwapCallbackData memory swapData = abi.decode(data, (SwapCallbackData));
        /// @notice Decodes the first pool in path
        /// @param path The bytes encoded swap path
        /// @return tokenA The first token of the given pool
        /// @return tokenB The second token of the given pool
        /// @return fee The fee level of the pool
        /// @position: contracts/periphery/libraries/PathHelper.sol
        
        (address tokenIn, address tokenOut, uint24 fee) = abi.decode(data, (address, address, uint24));
        
        require(
          /// @function _getPool
          /// @dev Returns the pool address for the requested token pair swap fee
          ///   Because the function calculates it instead of fetching the address from the factory,
          ///   the returned pool address may not be in existence yet
          msg.sender == IFactory(factory).getPool(tokenIn, tokenOut, fee),
          "adapter: invalid callback sender"
        );
        

        uint256 amountToTransfer = deltaQty0 > 0
          ? uint256(deltaQty0)
          : uint256(deltaQty1);
        
        SafeERC20.safeTransfer(IERC20(tokenIn), msg.sender, amountToTransfer);
    }

}