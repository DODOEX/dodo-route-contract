/*

    Copyright 2023 DODO ZOO.
    SPDX-License-Identifier: Apache-2.0

*/

pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface IDODO {
    function _ORACLE_() external view returns(address);
}

interface IDODOOracle {
    function getPrice() external view returns(uint256);
}

contract OffsetOracle is Ownable{
    uint256 public tokenPrice;
    uint256 public immutable offsetDenominator = 1000;
    address public immutable _DODO_POOL_ADDR_ = 0xBe60d4c4250438344bEC816Ec2deC99925dEb4c7;

    constructor() public {
        address dodoOracleAddr = IDODO(_DODO_POOL_ADDR_)._ORACLE_();
        tokenPrice = IDODOOracle(dodoOracleAddr).getPrice();
    }

    function adjustPrice(uint256 _newPrice) public onlyOwner {
        // check new price valid
        uint offset = _newPrice > tokenPrice ? _newPrice - tokenPrice : tokenPrice - _newPrice;
        require(offset <= (tokenPrice / offsetDenominator), "Large Offset");
        tokenPrice = _newPrice;
    }

    function getPrice() external view returns (uint256) {
        return tokenPrice;
    }
}