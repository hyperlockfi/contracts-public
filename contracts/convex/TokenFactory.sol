// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./Interfaces.sol";
import "./DepositToken.sol";
import "@openzeppelin/contracts-0.6/math/SafeMath.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-0.6/utils/Address.sol";
import "@openzeppelin/contracts-0.6/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-0.6/proxy/Clones.sol";

/**
 * @title   TokenFactory
 * @author  ConvexFinance
 * @notice  Token factory used to create Deposit Tokens. These are the tokenized
 *          pool deposit tokens e.g cvx3crv
 */
contract TokenFactory {
    using Address for address;

    address public immutable operator;
    address public immutable depositTokenImpl;
    string public namePostfix;
    string public symbolPrefix;

    event DepositTokenCreated(address token, address lpToken);

    /**
     * @param _operator         Operator is Booster
     * @param _namePostfix      Postfixes lpToken name
     * @param _symbolPrefix     Prefixed lpToken symbol
     * @param _depositTokenImpl DepositToken implementation
     */
    constructor(
        address _operator,
        string memory _namePostfix,
        string memory _symbolPrefix,
        address _depositTokenImpl
    ) public {
        operator = _operator;
        namePostfix = _namePostfix;
        symbolPrefix = _symbolPrefix;
        depositTokenImpl = _depositTokenImpl;
    }

    function CreateDepositToken(address _lptoken) external returns (address) {
        require(msg.sender == operator, "!authorized");

        DepositToken dtoken = DepositToken(Clones.clone(depositTokenImpl));
        dtoken.init(operator, _lptoken, namePostfix, symbolPrefix);
        emit DepositTokenCreated(address(dtoken), _lptoken);
        return address(dtoken);
    }
}
