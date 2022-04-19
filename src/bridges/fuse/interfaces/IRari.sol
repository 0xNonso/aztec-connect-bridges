// SPDX-License-Identifier: GPL-2.0-only
pragma solidity >=0.6.6 <0.8.10;
pragma abicoder v2;

interface FusePoolDirectory{
    /**
     * @dev Struct for a Fuse interest rate pool.
     */
    struct FusePool {
        string name;
        address creator;
        address comptroller;
        uint256 blockPosted;
        uint256 timestampPosted;
    }

    function pools(uint256 pool) external view returns (FusePool memory);

}
interface CTokenInterface {
    function mint(uint mintAmount) external returns (uint);
    function mint() external payable;
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function isCEther() external view returns (bool);

}

interface ComptrollerInterface {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function exitMarket(address cToken) external returns (uint);
    function getAllMarkets() external view returns (CTokenInterface[] memory);
    function cTokensByUnderlying(address underlying) external view returns (address);
}