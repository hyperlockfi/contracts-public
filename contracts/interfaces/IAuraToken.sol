// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";

interface IAuraToken is IERC20 {
    function gaugeVoterMint() external;
}
