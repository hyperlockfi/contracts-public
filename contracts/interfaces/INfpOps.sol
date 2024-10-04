// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { INonfungiblePositionManagerStruct } from "../interfaces/INonfungiblePositionManagerStruct.sol";

interface INfpOps is INonfungiblePositionManagerStruct {
    function withdrawPosition(uint256 _tokenId, address _to) external;

    function collect(CollectParams memory params) external returns (uint256, uint256);
}
