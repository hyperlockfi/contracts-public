// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INfpBooster {
    function getPoolInfo(bytes32 _key)
        external
        view
        returns (
            address,
            address,
            bool
        );
}
