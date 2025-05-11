import React, { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import './App.css';

// Import contract ABIs
import LendingPool from './contracts/LendingPool.json';
import InterestRateModel from './contracts/InterestRateModel.json';
import CollateralManager from './contracts/CollateralManager.json';

function App() {
  const [account, setAccount] = useState('');
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [lendingPool, setLendingPool] = useState(null);
  const [collateralManager, setCollateralManager] = useState(null);
  const [interestRateModel, setInterestRateModel] = useState(null);
  const [depositAmount, setDepositAmount] = useState('');
  const [borrowAmount, setBorrowAmount] = useState('');
  const [collateralAmount, setCollateralAmount] = useState('');
  const [userBalance, setUserBalance] = useState('0');
  const [userDeposits, setUserDeposits] = useState('0');
  const [userBorrows, setUserBorrows] = useState('0');
  const [userCollateral, setUserCollateral] = useState('0');
  const [liquidityRate, setLiquidityRate] = useState('0');
  const [borrowRate, setBorrowRate] = useState('0');

  useEffect(() => {
    connectWallet();
  }, []);

  const connectWallet = async () => {
    try {
      if (window.ethereum) {
        const provider = new ethers.providers.Web3Provider(window.ethereum);
        await provider.send("eth_requestAccounts", []);
        const signer = provider.getSigner();
        const account = await signer.getAddress();
        
        setProvider(provider);
        setSigner(signer);
        setAccount(account);

        // Initialize contracts
        const lendingPoolContract = new ethers.Contract(
          process.env.REACT_APP_LENDING_POOL_ADDRESS,
          LendingPool.abi,
          signer
        );
        setLendingPool(lendingPoolContract);

        const collateralManagerContract = new ethers.Contract(
          process.env.REACT_APP_COLLATERAL_MANAGER_ADDRESS,
          CollateralManager.abi,
          signer
        );
        setCollateralManager(collateralManagerContract);

        const interestRateModelContract = new ethers.Contract(
          process.env.REACT_APP_INTEREST_RATE_MODEL_ADDRESS,
          InterestRateModel.abi,
          signer
        );
        setInterestRateModel(interestRateModelContract);

        // Load initial data
        loadUserData();
      }
    } catch (error) {
      console.error("Error connecting wallet:", error);
    }
  };

  const loadUserData = async () => {
    if (!lendingPool || !account) return;

    try {
      const userAccount = await lendingPool.userAccounts(account, process.env.REACT_APP_TOKEN_ADDRESS);
      setUserDeposits(ethers.utils.formatEther(userAccount.deposited));
      setUserBorrows(ethers.utils.formatEther(userAccount.borrowed));
      
      const position = await collateralManager.positions(account, process.env.REACT_APP_COLLATERAL_TOKEN_ADDRESS);
      setUserCollateral(ethers.utils.formatEther(position.amount));
      
      const market = await lendingPool.markets(process.env.REACT_APP_TOKEN_ADDRESS);
      setLiquidityRate(ethers.utils.formatEther(market.liquidityRate));
      setBorrowRate(ethers.utils.formatEther(market.borrowRate));
    } catch (error) {
      console.error("Error loading user data:", error);
    }
  };

  const handleDeposit = async () => {
    if (!lendingPool || !depositAmount) return;

    try {
      const amount = ethers.utils.parseEther(depositAmount);
      const tx = await lendingPool.deposit(process.env.REACT_APP_TOKEN_ADDRESS, amount);
      await tx.wait();
      loadUserData();
    } catch (error) {
      console.error("Error depositing:", error);
    }
  };

  const handleBorrow = async () => {
    if (!lendingPool || !borrowAmount) return;

    try {
      const amount = ethers.utils.parseEther(borrowAmount);
      const tx = await lendingPool.borrow(process.env.REACT_APP_TOKEN_ADDRESS, amount);
      await tx.wait();
      loadUserData();
    } catch (error) {
      console.error("Error borrowing:", error);
    }
  };

  const handleDepositCollateral = async () => {
    if (!collateralManager || !collateralAmount) return;

    try {
      const amount = ethers.utils.parseEther(collateralAmount);
      const tx = await collateralManager.depositCollateral(
        process.env.REACT_APP_COLLATERAL_TOKEN_ADDRESS,
        amount
      );
      await tx.wait();
      loadUserData();
    } catch (error) {
      console.error("Error depositing collateral:", error);
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <h1>DeFi Lending Platform</h1>
        {!account ? (
          <button onClick={connectWallet}>Connect Wallet</button>
        ) : (
          <div className="account-info">
            Connected: {account.slice(0, 6)}...{account.slice(-4)}
          </div>
        )}
      </header>

      <main className="App-main">
        <div className="stats-container">
          <div className="stat-box">
            <h3>Your Deposits</h3>
            <p>{userDeposits} ETH</p>
          </div>
          <div className="stat-box">
            <h3>Your Borrows</h3>
            <p>{userBorrows} ETH</p>
          </div>
          <div className="stat-box">
            <h3>Your Collateral</h3>
            <p>{userCollateral} ETH</p>
          </div>
          <div className="stat-box">
            <h3>Current Rates</h3>
            <p>Lending: {liquidityRate}%</p>
            <p>Borrowing: {borrowRate}%</p>
          </div>
        </div>

        <div className="actions-container">
          <div className="action-box">
            <h3>Deposit</h3>
            <input
              type="number"
              value={depositAmount}
              onChange={(e) => setDepositAmount(e.target.value)}
              placeholder="Amount in ETH"
            />
            <button onClick={handleDeposit}>Deposit</button>
          </div>

          <div className="action-box">
            <h3>Borrow</h3>
            <input
              type="number"
              value={borrowAmount}
              onChange={(e) => setBorrowAmount(e.target.value)}
              placeholder="Amount in ETH"
            />
            <button onClick={handleBorrow}>Borrow</button>
          </div>

          <div className="action-box">
            <h3>Deposit Collateral</h3>
            <input
              type="number"
              value={collateralAmount}
              onChange={(e) => setCollateralAmount(e.target.value)}
              placeholder="Amount in ETH"
            />
            <button onClick={handleDepositCollateral}>Deposit Collateral</button>
          </div>
        </div>
      </main>
    </div>
  );
}

export default App; 