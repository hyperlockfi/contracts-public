// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { OFT } from "../layerzero/token/oft/OFT.sol";

/**
 * @title   cvxCrvToken
 * @author  ConvexFinance
 * @notice  Dumb ERC20 token that allows the operator (crvDepositor) to mint and burn tokens
 */
contract cvxCrvToken is OFT {
    address public operator;

    constructor(string memory _nameArg, string memory _symbolArg) OFT(_nameArg, _symbolArg) {
        operator = msg.sender;
    }

    function init(address _lzEndpoint) external {
        // _initializeLzApp checks that _lzEndpoint is address(0);
        _initializeLzApp(_lzEndpoint);
    }

    /**
     * @notice Allows the initial operator (deployer) to set the operator.
     *         Note - crvDepositor has no way to change this back, so it's effectively immutable
     */
    function setOperator(address _operator) external {
        require(msg.sender == operator, "!auth");
        operator = _operator;
    }

    /**
     * @notice Allows the crvDepositor to mint
     */
    function mint(address _to, uint256 _amount) external {
        require(msg.sender == operator, "!authorized");

        _mint(_to, _amount);
    }

    /**
     * @notice Allows the crvDepositor to burn
     */
    function burn(address _from, uint256 _amount) external {
        require(msg.sender == operator, "!authorized");

        _burn(_from, _amount);
    }
}
