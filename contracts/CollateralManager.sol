// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CollateralManager is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct CollateralPosition {
        uint256 amount;
        uint256 lastUpdateTimestamp;
        uint256 liquidationThreshold;
        bool isActive;
    }

    mapping(address => mapping(address => CollateralPosition)) public positions;
    mapping(address => uint256) public liquidationThresholds;
    mapping(address => bool) public supportedCollateral;
    
    uint256 public constant LIQUIDATION_BONUS = 0.05e18; // 5% bonus for liquidators
    uint256 public constant MIN_COLLATERAL_RATIO = 1.5e18; // 150% minimum collateral ratio
    
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);
    event PositionLiquidated(address indexed user, address indexed token, uint256 amount);
    event CollateralTokenAdded(address indexed token, uint256 threshold);
    event CollateralTokenRemoved(address indexed token);

    constructor() {}

    modifier onlySupportedCollateral(address token) {
        require(supportedCollateral[token], "Collateral token not supported");
        _;
    }

    function addCollateralToken(address token, uint256 threshold) external onlyOwner {
        require(!supportedCollateral[token], "Token already supported");
        require(threshold >= MIN_COLLATERAL_RATIO, "Threshold below minimum");
        
        supportedCollateral[token] = true;
        liquidationThresholds[token] = threshold;
        emit CollateralTokenAdded(token, threshold);
    }

    function removeCollateralToken(address token) external onlyOwner {
        require(supportedCollateral[token], "Token not supported");
        supportedCollateral[token] = false;
        emit CollateralTokenRemoved(token);
    }

    function depositCollateral(
        address token,
        uint256 amount
    ) external nonReentrant onlySupportedCollateral(token) {
        require(amount > 0, "Amount must be greater than 0");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        CollateralPosition storage position = positions[msg.sender][token];
        position.amount += amount;
        position.lastUpdateTimestamp = block.timestamp;
        position.liquidationThreshold = liquidationThresholds[token];
        position.isActive = true;
        
        emit CollateralDeposited(msg.sender, token, amount);
    }

    function withdrawCollateral(
        address token,
        uint256 amount
    ) external nonReentrant onlySupportedCollateral(token) {
        CollateralPosition storage position = positions[msg.sender][token];
        require(position.amount >= amount, "Insufficient collateral");
        require(position.isActive, "Position not active");
        
        position.amount -= amount;
        position.lastUpdateTimestamp = block.timestamp;
        
        if (position.amount == 0) {
            position.isActive = false;
        }
        
        IERC20(token).safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, token, amount);
    }

    function getCollateralRatio(
        address user,
        address token,
        uint256 borrowedAmount
    ) external view returns (uint256) {
        CollateralPosition storage position = positions[user][token];
        if (position.amount == 0 || borrowedAmount == 0) return 0;
        return (position.amount * 1e18) / borrowedAmount;
    }

    function isLiquidatable(
        address user,
        address token,
        uint256 borrowedAmount
    ) external view returns (bool) {
        CollateralPosition storage position = positions[user][token];
        if (!position.isActive) return false;
        
        uint256 collateralRatio = (position.amount * 1e18) / borrowedAmount;
        return collateralRatio < position.liquidationThreshold;
    }

    function liquidatePosition(
        address user,
        address token,
        uint256 borrowedAmount
    ) external nonReentrant onlySupportedCollateral(token) {
        CollateralPosition storage position = positions[user][token];
        require(position.isActive, "Position not active");
        
        uint256 collateralRatio = (position.amount * 1e18) / borrowedAmount;
        require(collateralRatio < position.liquidationThreshold, "Position not liquidatable");
        
        uint256 liquidationAmount = position.amount;
        uint256 bonusAmount = (liquidationAmount * LIQUIDATION_BONUS) / 1e18;
        
        position.amount = 0;
        position.isActive = false;
        
        // Transfer collateral to liquidator
        IERC20(token).safeTransfer(msg.sender, liquidationAmount + bonusAmount);
        
        emit PositionLiquidated(user, token, liquidationAmount);
    }

    function getPosition(
        address user,
        address token
    ) external view returns (
        uint256 amount,
        uint256 lastUpdateTimestamp,
        uint256 liquidationThreshold,
        bool isActive
    ) {
        CollateralPosition storage position = positions[user][token];
        return (
            position.amount,
            position.lastUpdateTimestamp,
            position.liquidationThreshold,
            position.isActive
        );
    }
} 