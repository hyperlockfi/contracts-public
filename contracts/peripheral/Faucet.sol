// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { IERC20 } from "@openzeppelin/contracts-0.8/token/ERC20/IERC20.sol";

contract Faucet {
    /* -------------------------------------------------------------------
       Storage 
    ------------------------------------------------------------------- */

    /// @dev The amount of each token to send
    uint256 public constant AMOUNT = 4 ether;

    /// @dev user => token => isClaimed;
    mapping(address => mapping(address => bool)) public isClaimed;

    /* -------------------------------------------------------------------
       Events 
    ------------------------------------------------------------------- */

    event Claimed(address sender, address token, uint256 amount);

    /* -------------------------------------------------------------------
       Functions 
    ------------------------------------------------------------------- */

    /// @dev For a given array of tokens loop through and determine
    /// if the contract has enough available balance to process the
    /// transfer
    /// @dev Only callable for each token once per user
    function claimTokens(address[] memory _tokens) external {
        uint256 len = _tokens.length;
        for (uint256 i = 0; i < len; i++) {
            IERC20 token = IERC20(_tokens[i]);
            if (token.balanceOf(address(this)) > AMOUNT) {
                isClaimed[msg.sender][address(token)] = true;
                token.transfer(msg.sender, AMOUNT);
                emit Claimed(msg.sender, address(token), AMOUNT);
            }
        }
    }
}
