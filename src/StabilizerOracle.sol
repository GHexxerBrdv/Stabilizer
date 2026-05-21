// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StabilizerOracle is Ownable {
    mapping(address => address) private tokenToPriceFeed;

    event PriceFeedSet(address indexed token, address indexed priceFeed);

    constructor(address[] memory _priceFeeds, address[] memory _tokens) Ownable(msg.sender) {
        _setPriceFeed(_priceFeeds, _tokens);
    }

    function updatePriceFeed(address[] memory _token, address[] memory _priceFeeds) external onlyOwner {
        _setPriceFeed(_priceFeeds, _token);
    }

    function _setPriceFeed(address[] memory _priceFeeds, address[] memory _tokens) internal {
        require(_priceFeeds.length == _tokens.length, "Invalid input lengths");
        for (uint256 i = 0; i < _priceFeeds.length; i++) {
            tokenToPriceFeed[_tokens[i]] = _priceFeeds[i];
            emit PriceFeedSet(_tokens[i], _priceFeeds[i]);
        }
    }

    function getPriceFeed(address _token) external view returns (address) {
        return tokenToPriceFeed[_token];
    }

    function getPrice(address _token) external view returns (uint256) {
        require(_token != address(0), "Zero address");
        require(tokenToPriceFeed[_token] != address(0), "No price feed set");
        (, int256 price,,,) = AggregatorV3Interface(tokenToPriceFeed[_token]).latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }
}
