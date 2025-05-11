// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract InterestRateModel {
    uint256 public constant BASE_RATE = 0.02e18; // 2% base rate
    uint256 public constant MULTIPLIER = 0.1e18; // 10% multiplier
    uint256 public constant JUMP_MULTIPLIER = 3e18; // 300% jump multiplier
    uint256 public constant OPTIMAL_UTILIZATION_RATE = 0.8e18; // 80% optimal utilization

    event NewInterestParams(
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 optimalUtilizationRate
    );

    constructor() {}

    function calculateRates(
        uint256 totalSupply,
        uint256 totalBorrow
    ) external pure returns (uint256 liquidityRate, uint256 borrowRate) {
        if (totalSupply == 0) {
            return (0, BASE_RATE);
        }

        uint256 utilizationRate = (totalBorrow * 1e18) / totalSupply;
        
        if (utilizationRate <= OPTIMAL_UTILIZATION_RATE) {
            // Normal rate calculation
            borrowRate = BASE_RATE + (utilizationRate * MULTIPLIER) / OPTIMAL_UTILIZATION_RATE;
        } else {
            // Jump rate calculation
            uint256 excessUtilizationRate = utilizationRate - OPTIMAL_UTILIZATION_RATE;
            uint256 jumpRate = (excessUtilizationRate * JUMP_MULTIPLIER) / (1e18 - OPTIMAL_UTILIZATION_RATE);
            borrowRate = BASE_RATE + MULTIPLIER + jumpRate;
        }

        // Liquidity rate is always less than borrow rate
        liquidityRate = (borrowRate * utilizationRate * (1e18 - 0.05e18)) / 1e18; // 5% protocol fee
    }

    function getUtilizationRate(uint256 totalSupply, uint256 totalBorrow) 
        external 
        pure 
        returns (uint256) 
    {
        if (totalSupply == 0) return 0;
        return (totalBorrow * 1e18) / totalSupply;
    }
} 