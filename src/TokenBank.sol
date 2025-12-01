// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Enhanced} from "./ERC20Enhanced.sol";

contract TokenBank {
    ERC20Enhanced private _token;

    mapping(address owner => uint256 balance) internal _balances;
    uint256 internal _totalBalances;
    address private _admin;
    
    event SetAdmin(address indexed oldAdmin, address indexed newAdmin);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    error NotAdmin(address user);
    error InsufficientBalance(address user, uint256 balance, uint256 needed);
    error TransferFailed(address user);

    modifier onlyAdmin() {
        if (msg.sender != _admin) {
            revert NotAdmin(msg.sender);
        }
        _;
    }

    constructor(address tokenAddress) {
        _token = ERC20Enhanced(tokenAddress);
        _admin = msg.sender;
    }

    function checkBalance() public view returns (uint256) {
        return _balances[msg.sender];
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        emit SetAdmin(_admin, newAdmin);
        _admin = newAdmin;
    }

    function totalBalances() external view onlyAdmin returns (uint256) {
        return _totalBalances;
    }

    function deposit(uint256 amount) external {
        // 存款流程：
        // 0. 要先到ERC20Enhanced 合约调用 approve() 方法授权 TokenBank 合约可以转移代币
        // 1. 调用 ERC20Enhanced.transferFrom() 方法，将用户代币转移到当前合约账户 TokenBank
        bool result = _token.transferFrom(msg.sender, address(this), amount);
        if (!result) {
            // 如果转移不成功，则抛出错误
            revert TransferFailed(msg.sender);
        }
        // 2. 更新用户余额
        _balances[msg.sender] += amount;
        _totalBalances += amount;
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        // 提款流程：
        // 1. 确保用户余额充足
        uint256 balance = _balances[msg.sender];
        if (balance < amount) {
            revert InsufficientBalance(msg.sender, balance, amount);
        }
        // 2. 将TokenBank中该用户的代币转移到ERC20Enhanced合约中
        bool result = _token.transfer(msg.sender, amount);
        if (!result) {
            // 如果转移不成功，则抛出错误
            revert TransferFailed(msg.sender);
        }
        // 3. 更新用户余额
        _balances[msg.sender] -= amount;
        _totalBalances -= amount;

        emit Withdraw(msg.sender, amount);
    }
}