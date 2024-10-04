// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IFeeDistributor {
    function toggle_allow_checkpoint_token() external;

    function claim(address user) external returns (uint256);

    function time_cursor() external view returns (uint256);

    function token() external view returns (address);

    function admin() external view returns (address);

    function time_cursor_of(address user) external view returns (uint256);
}
