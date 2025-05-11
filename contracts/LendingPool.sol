// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./InterestRateModel.sol";
import "./CollateralManager.sol";

contract LendingPool is ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    struct UserAccount {
        uint256 deposited;
        uint256 borrowed;
        uint256 lastUpdateTimestamp;
        uint256 collateralAmount;
    }

    struct Market {
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 lastUpdateTimestamp;
        uint256 liquidityRate;
        uint256 borrowRate;
        uint256 liquidationThreshold;
        bool isActive;
    }

    mapping(address => mapping(address => UserAccount)) public userAccounts;
    mapping(address => Market) public markets;
    mapping(address => bool) public supportedTokens;
    
    InterestRateModel public interestRateModel;
    CollateralManager public collateralManager;
    
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);
    event Repay(address indexed user, address indexed token, uint256 amount);
    event Liquidation(address indexed user, address indexed token, uint256 amount);
    event MarketCreated(address indexed token);
    event MarketPaused(address indexed token);
    event MarketResumed(address indexed token);

    constructor(address _interestRateModel, address _collateralManager) {
        interestRateModel = InterestRateModel(_interestRateModel);
        collateralManager = CollateralManager(_collateralManager);
    }

    modifier onlySupportedToken(address token) {
        require(supportedTokens[token], "Token not supported");
        _;
    }

    modifier onlyActiveMarket(address token) {
        require(markets[token].isActive, "Market is not active");
        _;
    }

    function addSupportedToken(address token) external onlyOwner {
        require(!supportedTokens[token], "Token already supported");
        supportedTokens[token] = true;
        markets[token] = Market({
            totalSupply: 0,
            totalBorrow: 0,
            lastUpdateTimestamp: block.timestamp,
            liquidityRate: 0,
            borrowRate: 0,
            liquidationThreshold: 75, // 75% collateralization ratio
            isActive: true
        });
        emit MarketCreated(token);
    }

    function deposit(address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlySupportedToken(token) 
        onlyActiveMarket(token) 
    {
        require(amount > 0, "Amount must be greater than 0");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        UserAccount storage account = userAccounts[msg.sender][token];
        account.deposited += amount;
        account.lastUpdateTimestamp = block.timestamp;
        
        Market storage market = markets[token];
        market.totalSupply += amount;
        market.lastUpdateTimestamp = block.timestamp;
        
        _updateRates(token);
        
        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlySupportedToken(token) 
        onlyActiveMarket(token) 
    {
        UserAccount storage account = userAccounts[msg.sender][token];
        require(account.deposited >= amount, "Insufficient balance");
        
        _updateUserAccount(msg.sender, token);
        
        account.deposited -= amount;
        account.lastUpdateTimestamp = block.timestamp;
        
        Market storage market = markets[token];
        market.totalSupply -= amount;
        market.lastUpdateTimestamp = block.timestamp;
        
        _updateRates(token);
        
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, token, amount);
    }

    function borrow(address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlySupportedToken(token) 
        onlyActiveMarket(token) 
    {
        require(amount > 0, "Amount must be greater than 0");
        
        _updateUserAccount(msg.sender, token);
        
        UserAccount storage account = userAccounts[msg.sender][token];
        account.borrowed += amount;
        account.lastUpdateTimestamp = block.timestamp;
        
        Market storage market = markets[token];
        market.totalBorrow += amount;
        market.lastUpdateTimestamp = block.timestamp;
        
        _updateRates(token);
        
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Borrow(msg.sender, token, amount);
    }

    function repay(address token, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlySupportedToken(token) 
        onlyActiveMarket(token) 
    {
        UserAccount storage account = userAccounts[msg.sender][token];
        require(account.borrowed >= amount, "Insufficient borrowed amount");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        account.borrowed -= amount;
        account.lastUpdateTimestamp = block.timestamp;
        
        Market storage market = markets[token];
        market.totalBorrow -= amount;
        market.lastUpdateTimestamp = block.timestamp;
        
        _updateRates(token);
        
        emit Repay(msg.sender, token, amount);
    }

    function _updateUserAccount(address user, address token) internal {
        UserAccount storage account = userAccounts[user][token];
        Market storage market = markets[token];
        
        uint256 timeDelta = block.timestamp - account.lastUpdateTimestamp;
        if (timeDelta > 0) {
            if (account.deposited > 0) {
                uint256 interestEarned = (account.deposited * market.liquidityRate * timeDelta) / 1e18;
                account.deposited += interestEarned;
                market.totalSupply += interestEarned;
            }
            
            if (account.borrowed > 0) {
                uint256 interestOwed = (account.borrowed * market.borrowRate * timeDelta) / 1e18;
                account.borrowed += interestOwed;
                market.totalBorrow += interestOwed;
            }
        }
    }

    function _updateRates(address token) internal {
        Market storage market = markets[token];
        (uint256 newLiquidityRate, uint256 newBorrowRate) = interestRateModel.calculateRates(
            market.totalSupply,
            market.totalBorrow
        );
        market.liquidityRate = newLiquidityRate;
        market.borrowRate = newBorrowRate;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function pauseMarket(address token) external onlyOwner {
        require(supportedTokens[token], "Token not supported");
        markets[token].isActive = false;
        emit MarketPaused(token);
    }

    function resumeMarket(address token) external onlyOwner {
        require(supportedTokens[token], "Token not supported");
        markets[token].isActive = true;
        emit MarketResumed(token);
    }
} 