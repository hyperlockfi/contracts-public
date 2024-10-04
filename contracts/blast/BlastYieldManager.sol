// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import { IBlast } from "./IBlast.sol";
import { IERC20Rebasing } from "./IERC20Rebasing.sol";
import { Ownable } from "@openzeppelin/contracts-0.6/access/Ownable.sol";

contract BlastYieldManager is Ownable {
    /* --------------------------------------------------------------
     * Storage 
    -------------------------------------------------------------- */

    IBlast public BLAST;
    IERC20Rebasing public USDB;
    IERC20Rebasing public WETHB;

    /* --------------------------------------------------------------
     * Constructor 
    -------------------------------------------------------------- */

    function initBlastYieldManager(
        address _blast,
        address _usdb,
        address _wethb
    ) external onlyOwner {
        require(address(BLAST) == address(0), "already initialized");

        IBlast blast = IBlast(_blast);
        IERC20Rebasing usdb = IERC20Rebasing(_usdb);
        IERC20Rebasing wethb = IERC20Rebasing(_wethb);

        BLAST = blast;
        USDB = usdb;
        WETHB = wethb;

        blast.configureClaimableGas();
        blast.configureClaimableYield();

        usdb.configure(IERC20Rebasing.YieldMode.CLAIMABLE);
        wethb.configure(IERC20Rebasing.YieldMode.CLAIMABLE);
    }

    /* --------------------------------------------------------------
     * ETH yields and Gas 
    -------------------------------------------------------------- */

    function claimAllYield(address recipientOfYield) external onlyOwner returns (uint256) {
        return BLAST.claimAllYield(address(this), recipientOfYield);
    }

    function claimMaxGas(address recipientOfGas) external onlyOwner returns (uint256) {
        return BLAST.claimMaxGas(address(this), recipientOfGas);
    }

    function claimAllGas(address recipientOfGas) external onlyOwner returns (uint256) {
        return BLAST.claimAllGas(address(this), recipientOfGas);
    }

    function claimGas(
        address recipientOfGas,
        uint256 gasToClaim,
        uint256 gasSecondsToConsume
    ) external onlyOwner returns (uint256) {
        return BLAST.claimGas(address(this), recipientOfGas, gasToClaim, gasSecondsToConsume);
    }

    function claimGasAtMinClaimRate(address recipientOfGas, uint256 minClaimRateBips)
        external
        onlyOwner
        returns (uint256)
    {
        return BLAST.claimGasAtMinClaimRate(address(this), recipientOfGas, minClaimRateBips);
    }

    /* --------------------------------------------------------------
     * Rebasing token yields 
    -------------------------------------------------------------- */

    function claimERC20RebasingWETH(address _recipient, uint256 _amount) external onlyOwner returns (uint256) {
        return WETHB.claim(_recipient, _amount);
    }

    function claimERC20RebasingUSDB(address _recipient, uint256 _amount) external onlyOwner returns (uint256) {
        return USDB.claim(_recipient, _amount);
    }
}
