// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { INfpOps } from "../interfaces/INfpOps.sol";
import { IBooster } from "../interfaces/IBooster.sol";
import { INonfungiblePositionManager } from "../interfaces/INonfungiblePositionManager.sol";

contract NfpOps is INfpOps {
    /* -------------------------------------------------------------------
       Storage
    ------------------------------------------------------------------- */

    /// @dev NFPoisition Booster contract
    address public booster;

    /// @dev Nonfungible Position Manager
    INonfungiblePositionManager public nfpManager;

    /* -------------------------------------------------------------------
      Constructor/Init
    ------------------------------------------------------------------- */

    function _initNfpOps(address _booster, address _nfpManager) internal {
        require(booster == address(0), "!init");
        booster = _booster;
        nfpManager = INonfungiblePositionManager(_nfpManager);
    }

    /* -------------------------------------------------------------------
       Modifiers
    ------------------------------------------------------------------- */

    modifier onlyBooster() {
        require(msg.sender == IBooster(booster).nfpBooster(), "!booster");
        _;
    }

    /* -------------------------------------------------------------------
       Core
    ------------------------------------------------------------------- */

    function collect(CollectParams memory params) external override onlyBooster returns (uint256, uint256) {
        require(params.recipient != address(0), "!recipient");
        require(params.recipient != address(this), "!recipient");
        return nfpManager.collect(params);
    }

    function withdrawPosition(uint256 _tokenId, address _to) external override onlyBooster {
        nfpManager.safeTransferFrom(address(this), _to, _tokenId);
    }

    /// @dev Warning! nfpManager NFTs will be lost if they are sent here directly
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        require(msg.sender == address(nfpManager), "!manager");
        return this.onERC721Received.selector;
    }
}
