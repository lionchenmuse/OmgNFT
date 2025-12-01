// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IERC20Enhanced.sol";
import {IERC20Receipient} from "./interfaces/IERC20Receipient.sol";
import {AddressUtils} from "./utils/AddressUtils.sol";

contract ERC20Enhanced is IERC20Enhanced { 
    using AddressUtils for address;

    string public name;
    string public symbol;
    uint8 public decimals;

    uint256 public totalSupply;

    mapping(address owner => uint256) balances;
    mapping(address owner => mapping(address spender => uint256)) allowances;

    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC20InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC20InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC20InvalidSpender(address spender);

    error CallPanic(uint256 code);
    error CallFailed(string message);

    constructor() {
        name = "ERC20EH";
        symbol = "EH";
        decimals = 18;
        totalSupply = 1000000 * 10 ** decimals;
        balances[msg.sender] = totalSupply;
    }

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function transfer(address _to, uint256 _value) public returns (bool success) { 
        if (_to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        if (msg.sender == _to) {
            revert ERC20InvalidSender(msg.sender);
        }
        if (balances[msg.sender] < _value) {
            revert ERC20InsufficientBalance(msg.sender, balances[msg.sender], _value);
        }

        _updateBalances(msg.sender, _to, _value);

        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        if (_from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (_to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        if (balances[_from] < _value) {
            revert ERC20InsufficientBalance(_from, balances[_from], _value);
        }
        if (allowances[_from][msg.sender] < _value) {
            revert ERC20InsufficientAllowance(_from, allowances[_from][msg.sender], _value);
        }
        _updateBalances(_from, _to, _value);
        allowances[_from][msg.sender] -= _value;

        emit Transfer(_from, _to, _value);
        return true;
    }

    /**
    * @dev 带回调的转账，相当于增强版的transferFrom 方法
    * @param _from 转账人
    * @param _to 接收人
    * @param _amount 转账金额
    * @return bool 转账成功与否
    */
    function transferWithCallback(address _from, address _to, uint256 _amount, bytes memory _data) external returns (bool) { 
        if (_from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (_to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        if (balances[_from] < _amount) {
            revert ERC20InsufficientBalance(_from, balances[_from], _amount);
        }
        if (allowances[_from][msg.sender] < _amount) {
            revert ERC20InsufficientAllowance(_from, allowances[_from][msg.sender], _amount);
        }
        _updateBalances(_from, _to, _amount);
        allowances[_from][msg.sender] -= _amount;

        if (_to.isContract()) {
            try IERC20Receipient(_to).tokenReceived(_from, _amount, _data) {
            } catch Error(string memory reason) {
                revert(reason);
            } catch Panic(uint256 errorCode) {
                revert CallPanic(errorCode);
            } catch (bytes memory) {
                revert CallFailed("IERC20Receipient: tokenReceived() call failed");
            }
        }
        emit Transfer(_from, _to, _amount);
        return true;
    }

    function _updateBalances(address _from, address _to, uint256 _value) internal {
        balances[_from] -= _value;
        balances[_to] += _value;
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        if (_spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        allowances[msg.sender][_spender] = _value;

        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowances[_owner][_spender];
    }
}