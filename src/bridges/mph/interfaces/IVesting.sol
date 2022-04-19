// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6 <0.8.10;

interface IVesting {

    function withdraw(uint64 vestID)
        external
        returns (uint256 withdrawnAmount);

    function depositIDToVestID(address pool, uint64 deposit_id) external view returns (uint64);
}