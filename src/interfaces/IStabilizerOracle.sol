// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

interface IStabilizerOracle {
    event PriceFeedSet(address indexed token, address indexed priceFeed);

    function getPrice(address token) external view returns (uint256);
}
