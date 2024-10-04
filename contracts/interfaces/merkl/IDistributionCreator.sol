// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { DistributionParameters } from "./DistributionParameters.sol";

interface IDistributionCreator {
    function createDistribution(DistributionParameters memory newDistribution) external returns (uint256);

    function acceptConditions() external;
}
