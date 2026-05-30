// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StabilizerOracle is Ownable {
    uint256 public constant HEARTBEAT = 24 hours;

    error InvalidLength();
    error InvalidAddress();
    error InvalidFeed();
    error InvalidPrice();
    error StaleFeed();

    mapping(address => address) private tokenToPriceFeed;

    event PriceFeedSet(address indexed token, address indexed priceFeed);

    constructor(address[] memory _priceFeeds, address[] memory _tokens) Ownable(msg.sender) {
        _setPriceFeed(_priceFeeds, _tokens);
    }

    /*
        Setters
    */

    function updatePriceFeed(address[] memory _token, address[] memory _priceFeeds) external onlyOwner {
        _setPriceFeed(_priceFeeds, _token);
    }

    function _setPriceFeed(address[] memory _priceFeeds, address[] memory _tokens) internal {
        require(_priceFeeds.length == _tokens.length, InvalidLength());
        for (uint256 i = 0; i < _priceFeeds.length; i++) {
            tokenToPriceFeed[_tokens[i]] = _priceFeeds[i];
            emit PriceFeedSet(_tokens[i], _priceFeeds[i]);
        }
    }

    /*
        Getters
    */

    function getPriceFeed(address _token) external view returns (address) {
        return tokenToPriceFeed[_token];
    }

    function getPrice(address _token) external view returns (uint256) {
        require(_token != address(0), InvalidAddress());
        address feed = tokenToPriceFeed[_token];
        require(feed != address(0), InvalidFeed());
        (uint80 roundId, int256 price,, uint256 updatedAt,) = AggregatorV3Interface(feed).latestRoundData();
        require(price > 0, InvalidPrice());
        require(updatedAt > 0, StaleFeed());
        require(block.timestamp - updatedAt <= HEARTBEAT, StaleFeed());
        return uint256(price);
    }
}
