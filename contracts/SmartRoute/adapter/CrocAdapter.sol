// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.16;

interface IDODOAdapter {
    
    function sellBase (address to, address pool, bytes memory moreInfo) external;

    function sellQuote(address to, address pool, bytes memory moreInfo) external;
}


interface IWETH {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) external returns (bool);

    function deposit() external payable;

    function withdraw(uint256 wad) external;
}

// File: contracts/intf/IERC20.sol


/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

// File: contracts/lib/SafeMath.sol




/**
 * @title SafeMath
 * @author DODO Breeder
 *
 * @notice Math operations with safety checks that revert on error
 */
library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "MUL_ERROR");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "DIVIDING_ERROR");
        return a / b;
    }

    function divCeil(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 quotient = div(a, b);
        uint256 remainder = a - quotient * b;
        if (remainder > 0) {
            return quotient + 1;
        } else {
            return quotient;
        }
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SUB_ERROR");
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "ADD_ERROR");
        return c;
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = x / 2 + 1;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

// File: contracts/lib/SafeERC20.sol




/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for ERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using SafeMath for uint256;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves.

        // A Solidity high level call has three parts:
        //  1. The target address is checked to verify it contains contract code
        //  2. The call itself is made, and success asserted
        //  3. The return value is decoded, which in turn checks the size of the returned data.
        // solhint-disable-next-line max-line-length

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeERC20: low-level call failed");

        if (returndata.length > 0) {
            // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


interface ICroc {
    function swap(address base, address quote, uint256 poolIdx, 
            bool isBuy, bool inBaseQty, uint128 qty, uint16 tip, 
            uint128 limitPrice, uint128 minOut, uint8 reserveFlags) 
            external payable returns (int128 baseFlow, int128 quoteFlow);
}


contract CrocAdapter is IDODOAdapter {
    // ============ Storage ============
    address public immutable _WETH_;
    address public immutable _CROC_SWAP_DEX_;
    
    uint256 poolIdx = 420;
    uint16 tip = 0;
    uint8 reserveFlags = 0;
    bool isBuy;
    bool inBaseQty;
    uint128 limitPrice;

    constructor(
        address payable weth,
        address crocSwapDex
    ) {
        _WETH_ = weth;
        _CROC_SWAP_DEX_ = crocSwapDex;
    }

    function _crocSwap(address to, bytes memory moreInfo) internal {
        int128 baseFlow;
        int128 quoteFlow;

        (address base, address quote, uint128 qty, uint128 minOut)
            = abi.decode(moreInfo, (address, address, uint128, uint128));

        if (base == _WETH_) { 
            base = address(0);
            if (isBuy) {
                IWETH(_WETH_).withdraw(qty); 
                // transfer eth to _CROC_SWAP_DEX_
                (baseFlow, quoteFlow) 
                    = ICroc(_CROC_SWAP_DEX_).swap{value: qty}(base, quote, poolIdx, isBuy, inBaseQty, qty, tip, limitPrice, minOut, reserveFlags);
            } else {
                if(IERC20(quote).allowance(address(this), _CROC_SWAP_DEX_) < qty) {
                    SafeERC20.safeApprove(IERC20(quote), _CROC_SWAP_DEX_, qty);
                }
                (baseFlow, quoteFlow) 
                    = ICroc(_CROC_SWAP_DEX_).swap(base, quote, poolIdx, isBuy, inBaseQty, qty, tip, limitPrice, minOut, reserveFlags);
            }
        } else {
            if (isBuy) {
                if(IERC20(base).allowance(address(this), _CROC_SWAP_DEX_) < qty) {
                    SafeERC20.safeApprove(IERC20(base), _CROC_SWAP_DEX_, qty);
                } 
            } else {
                if(IERC20(quote).allowance(address(this), _CROC_SWAP_DEX_) < qty) {
                    SafeERC20.safeApprove(IERC20(quote), _CROC_SWAP_DEX_, qty);
                }
            }
            (baseFlow, quoteFlow) 
                = ICroc(_CROC_SWAP_DEX_).swap(base, quote, poolIdx, isBuy, inBaseQty, qty, tip, limitPrice, minOut, reserveFlags);
        }
        
        if (isBuy) {
            SafeERC20.safeTransfer(IERC20(quote), to, uint128(-quoteFlow));
        } else {
            if (base == address(0)) {
                // withdraw weth
                IWETH(_WETH_).deposit{value: uint128(-baseFlow)}();
                SafeERC20.safeTransfer(IERC20(_WETH_), to, uint128(-baseFlow));
            } else {
                SafeERC20.safeTransfer(IERC20(base), to, uint128(-baseFlow));
            }
        }
    }

    function sellBase(address to, address pool, bytes memory moreInfo) external override {
        isBuy = true;
        inBaseQty = true;
        limitPrice = 21267430153580247136652501917186561137;
        _crocSwap(to, moreInfo);
    }

    function sellQuote(address to, address pool, bytes memory moreInfo) external override {
        isBuy = false;
        inBaseQty = false;
        limitPrice = 65538;
        _crocSwap(to, moreInfo);
    }

    fallback() external payable {}

    receive() external payable {}
}