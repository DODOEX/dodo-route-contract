/*

    Copyright 2022 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0
*/

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IDODOAdapter {
    function sellBase(address to, address pool, bytes memory data) external;

    function sellQuote(address to, address pool, bytes memory data) external;
}

interface IiZiSwapCallback {

    /// @notice Called to msg.sender in iZiSwapPool#swapY2X(DesireX) call
    /// @param x Amount of tokenX trader will acquire
    /// @param y Amount of tokenY trader will pay
    /// @param data Any dadta passed though by the msg.sender via the iZiSwapPool#swapY2X(DesireX) call
    function swapY2XCallback(
        uint256 x,
        uint256 y,
        bytes calldata data
    ) external;

    /// @notice Called to msg.sender in iZiSwapPool#swapX2Y(DesireY) call
    /// @param x Amount of tokenX trader will pay
    /// @param y Amount of tokenY trader will require
    /// @param data Any dadta passed though by the msg.sender via the iZiSwapPool#swapX2Y(DesireY) call
    function swapX2YCallback(
        uint256 x,
        uint256 y,
        bytes calldata data
    ) external;
}

interface IiZiSwapPool {
    function swapX2Y(
        address recipient,
        uint128 amount,
        int24 lowPt,
        bytes calldata data
    ) external returns (uint256 amountX, uint256 amountY);

    function swapY2X(
        address recipient,
        uint128 amount,
        int24 highPt,
        bytes calldata data
    ) external returns (uint256 amountX, uint256 amountY);
}

contract IziSwapAdapter is IiZiSwapCallback, IDODOAdapter {
    using SafeERC20 for IERC20;

    function sellBase(address to, address pool, bytes memory data) public {
        (address fromToken, address toToken, int24 limitPt) = abi.decode(data, (address, address, int24));
        uint128 amount = uint128(IERC20(fromToken).balanceOf(address(this)));

        IiZiSwapPool(pool).swapX2Y(to, amount, limitPt, data);
    }

    function sellQuote(address to, address pool, bytes memory data) public {
        (address fromToken, address toToken, int24 limitPt) = abi.decode(data, (address, address, int24));
        uint128 amount = uint128(IERC20(fromToken).balanceOf(address(this)));

        IiZiSwapPool(pool).swapY2X(to, amount, limitPt, data);
    }

    function swapY2XCallback(uint256 x, uint256 y, bytes calldata data) external override{
        (address fromToken, , ) = abi.decode(data, (address, address, int24));

        SafeERC20.safeTransfer(IERC20(fromToken), msg.sender, y);
    }

    function swapX2YCallback(uint256 x, uint256 y, bytes calldata data) external override{
        (address fromToken, , ) = abi.decode(data, (address, address, int24));

        SafeERC20.safeTransfer(IERC20(fromToken), msg.sender, x);
    }
}

