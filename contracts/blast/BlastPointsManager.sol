// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import { IBlastPoints } from "./IBlastPoints.sol";
import { Ownable } from "@openzeppelin/contracts-0.6/access/Ownable.sol";

contract BlastPointsManager is Ownable {
    /* --------------------------------------------------------------
     * Storage 
    -------------------------------------------------------------- */

    IBlastPoints public BLAST_POINTS;

    /* --------------------------------------------------------------
     * Constructor 
    -------------------------------------------------------------- */

    function initBlastPointsManager(address _blastPoints) external onlyOwner {
        require(address(BLAST_POINTS) == address(0), "already initialized");

        BLAST_POINTS = IBlastPoints(_blastPoints);
    }

    function configurePointsOperator(address _operator) external onlyOwner {
        BLAST_POINTS.configurePointsOperator(_operator);
    }
}
