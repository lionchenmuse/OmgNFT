// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Counters} from "./utils/Counters.sol";
import {ERC20Enhanced} from "./ERC20Enhanced.sol";
import {IERC20Receipient} from "./interfaces/IERC20Receipient.sol";
import "forge-std/console.sol";

/**
* Solidity中，EVM将状态变量存储在32字节(256位)的存储槽(slot)中。
* 为了最大化存储效率，Solidity会对较小的数据类型进行紧密打包，
* 将多个变量放入同一个存储槽。
*/

struct NFT {
    uint256 tokenId;                    // 32 字节, slot 0
    uint256 price;                      // 32 字节, slot 1
    address owner;                      // 20 字节, slot 2
    address contractAddress;            // 20 字节, slot 3
    string uri;                         // 32 字节, slot 4
}

struct Order {
    uint256 id;             // slot 0
    uint256 nftMarketId;    // slot 1
    uint256 nftId;          // slot 2
    uint256 price;          // slot 3
    uint256 platformFee;    // slot 4
    uint256 sellerAmount;   // slot 5
    address buyer;          // slot 6 (地址是20字节，浪费12字节)
    address seller;         // slot 7 (浪费12字节)
    uint256 timestamp;      // slot 8
    OrderStatus status;     // slot 8 (枚举实际是uint8，浪费31字节)
}

enum OrderStatus {
    Pending,
    Fulfilled,
    Cancelled
}

contract NFTMarket is IERC20Receipient { 
    using Counters for Counters.Counter;
    // NFT在市场的ID
    Counters.Counter private _nftMarketId;
    // 订单ID
    Counters.Counter private _orderId;
    // ERC20代币
    ERC20Enhanced private _token;
    // 管理员
    address private _admin;
    // 平台手续费百分比
    uint256 private _platformFeePercent = 300;
    uint256 private _minimumFee = 1 * 10 ** 18;     // 最低1个代币
    // 存储NFT信息
    mapping(uint256 nftMarketId => NFT) private _nfts;
    // 存储订单信息
    mapping(uint256 id => Order) private _orders;

    /**
    * @dev NFT上架事件
    * @param marketId NFT在市场的ID
    * @param tokenId NFT的ID
    * @param contractAddress NFT合约地址
    * @param owner NFT的拥有者
    * @param price NFT的价格
    */
    event NFTListed(uint256 indexed marketId, uint256 indexed tokenId, address contractAddress, address indexed owner, uint256 price);
    /**
    * @dev 下单事件
    * @param orderId 订单ID
    * @param status 订单状态
    * @param tokenId NFT的ID
    * @param contractAddress NFT合约地址
    * @param buyer 购买者
    * @param seller 卖家
    * @param price 订单价格
    * @param platformFee 平台手续费
    */
    event OrderPlaced(uint256 indexed orderId, OrderStatus status, uint256 indexed tokenId, address contractAddress, address indexed buyer, address seller, uint256 price, uint256 platformFee);
    /** 
    * @dev NFT完成交易事件
    * @param orderId 订单ID
    * @param tokenId NFT的ID
    * @param contractAddress NFT合约地址
    * @param buyer 购买者
    * @param seller 卖家
    * @param price 订单价格
    * @param platformFee 平台手续费
    */
    event NFTSold(uint256 indexed orderId, uint256 indexed tokenId, address contractAddress, address indexed buyer, address seller, uint256 price, uint256 platformFee);
    /**
    * @dev NFT取消事件（由发现当前所有者与记录所有者不一致导致）
    * @param marketId NFT在市场的ID
    * @param tokenId NFT的ID
    */
    event NFTNoLongerAvailable(uint256 indexed marketId, uint256 indexed tokenId);
    /**
    * @dev NFT不存在事件（由发现当前NFT不存在导致，即找不到该NFT 对应的owner）
    * @param marketId NFT在市场的ID
    * @param tokenId NFT的ID
    */
    event NFTNoLongerExists(uint256 indexed marketId, uint256 indexed tokenId);

    /**
    * @dev 调试信息事件
    * @param message 信息
    * @param value 值
    */
    event DebugInfo(string message, uint256 value);
    // 注意：一个事件中最多只能有3个indexed参数

    /**
    * @dev 非管理员操作错误
    * @param sender 操作者
    */
    error NotAdmin(address sender);
    /** 
    * @dev 非法NFT合约错误(目前是由于零地址引起)
    * @param contractAddress NFT合约地址
    */
    error InvalidNFTContract(address contractAddress);

    /**
    * @dev 无效NFT错误，原因可能是id错误，或者NFT已被卖出（从映射中移除）
    * @param nftMarketId NFT在市场的ID
    */
    error InvalidNFT(uint256 nftMarketId);
    /**
    * @dev 无效价格错误（不能小于_minimumFee）
    * @param price 价格
    */
    error InvalidPrice(uint256 price);

    error SameBuyerAndSeller(uint256 nftMarketId, uint256 nftId, address nftOwner);
    /**
    * @dev 非NFT拥有者或授权者错误
    * @param sender 操作者
    * @param nftId NFT的ID
    */
    error NotOwnerAndNotApprovedOfNFT(address sender, uint256 nftId);
    /**
    * @dev NFT所有权已改变错误
    * @param marketId NFT在市场的ID
    * @param tokenId NFT的ID
    * @param oldOwner 旧拥有者
    * @param currentOwner 新拥有者
    */
    error NFTOwnershipChanged(uint256 marketId, uint256 tokenId, address oldOwner, address currentOwner);
    /** 
    * @dev 授权额度不足错误
    * @param orderId 订单ID
    * @param owner 授权者
    * @param spender 授权接收者
    * @param needed 需要的授权额度
    */
    error InsufficientAllowance(uint256 orderId, address owner, address spender, uint256 needed);
    /**
    * @dev 余额不足错误
    * @param buyer 购买者
    * @param NFTMarketId NFT在市场的ID
    * @param tokenId NFT的ID
    * @param balance 账户余额
    * @param needed 需要的余额
    */
    error InsufficientBalance(address buyer, uint256 NFTMarketId, uint256 tokenId, uint256 balance, uint256 needed);
    /**
    * @dev 平台手续费转账失败错误
    * @param tokenId NFT的ID
    * @param buyer 购买者
    * @param seller 卖家
    * @param platformFee 平台手续费
    */
    error PlatformFeeTransferFailed(uint256 tokenId, address buyer, address seller, uint256 platformFee);
    /**
    * @dev ERC20代币转账失败错误
    * @param marketId NFT在市场的ID
    * @param tokenId NFT的ID
    * @param buyer 购买者
    * @param seller 卖家
    * @param price 订单价格
    */
    error TokenTransferFailed(uint256 marketId, uint256 tokenId, address buyer, address seller, uint256 price);
    /**
    * @dev NFT转移失败错误
    * @param orderId 订单ID
    * @param tokenId NFT的ID
    * @param buyer 购买者
    * @param seller 卖家
    */
    error NFTTransferFailed(uint256 orderId, uint256 tokenId, address buyer, address seller);
    /**
    * @dev 非授权者错误
    * @param sender 操作者
    */
    error Unauthorized(address sender);
    /**
    * @dev panic错误
    * @param code 错误代码
    */
    error CallPanic(uint256 code);
    /**
    * @dev 调用失败错误
    * @param message 错误信息
    */
    error CallFailed(string message);
    /**
    * @dev 订单无效错误
    * @param orderId 订单ID
    */
    error InvalidOrder(uint256 orderId);
    /**
    * @dev NFT未授权错误 (NFT所有者未授权NFTMarket操作他的NFT)
    * @param orderId 订单ID
    * @param tokenId NFT的ID
    * @param nftOwner NFT的拥有者
    */
    error NFTNotAuthorized(uint256 orderId, uint256 tokenId, address nftOwner);

    modifier onlyAdmin() {
        if (msg.sender != _admin) {
            revert NotAdmin(msg.sender);
        }
        _;
    }

    constructor(address tokenAddress) {
        _admin = msg.sender;
        _token = ERC20Enhanced(tokenAddress);
    }

    /**
    * @dev 修改平台手续费比例
    * @param _feePercent 新的百分比
    */
    function changeFeePercent(uint256 _feePercent) external onlyAdmin {
        _platformFeePercent = _feePercent;
    }

    /**
    * @dev 修改最小手续费
    * @param minimumFee_ 新的最小手续费
    */
    function changeMinimumFee(uint256 minimumFee_) external onlyAdmin {
        _minimumFee = minimumFee_;
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        _admin = newAdmin;
    }

    function feePercent() external view returns (uint256) {
        return _platformFeePercent;
    }

    function minimumFee() external view returns (uint256) {
        return _minimumFee;
    }

    function nftInfo(uint256 marketId) external view returns (NFT memory) {
        return _nfts[marketId];
    }

    function orderInfo(uint256 orderId) external view returns (Order memory) {
        return _orders[orderId];
    }

    /**
    * @dev 上架NFT
    * @param _tokenId NFT的ID
    * @param _price NFT的价格
    * @param _contractAddress NFT合约地址
    * @param _tokenURI NFT的URI
    * @return uint256 NFT在市场上的ID
    */
    function list(uint256 _tokenId, uint256 _price, address _contractAddress, string memory _tokenURI) external returns (uint256) { 
        // 第一步，检查合约地址参数、价格是否合法有效
        if (_contractAddress == address(0)) {
            revert InvalidNFTContract(address(0));
        }
        if (_price < _minimumFee) {
            revert InvalidPrice(_price);
        }

        // 第二步，检查NFT是否存在及获取所有者
        IERC721 _contract = IERC721(_contractAddress);
        address owner;
        try _contract.ownerOf(_tokenId) returns (address _owner) {
            owner = _owner;
        } catch Error(string memory reason) {
            revert(reason);
        } catch Panic(uint256 errorCode) {
            revert CallPanic(errorCode);
        } catch (bytes memory) {
            revert IERC721Errors.ERC721NonexistentToken(_tokenId);
        } 

        // 第三步，检查交易发起者是否有权限操作NFT
        if (!_isNFTOwnerOrApprovedForAll(_tokenId, owner, _contract)) {
            revert NotOwnerAndNotApprovedOfNFT(msg.sender, _tokenId);
        }
        
        // 第四步，将NFT信息保存到市场中
        uint256 id = _nftMarketId.next();
        NFT memory nft = NFT(_tokenId, _price, owner, _contractAddress, _tokenURI);
        _nfts[id] = nft;
        // 第五步，触发事件
        emit NFTListed(id, _tokenId, _contractAddress, owner, _price);
        // 第六步，返回NFT在市场中的ID
        return id;
    }

    /**
    * @dev 检查NFT的所有者和授权代理
    * @param _tokenId NFT的ID
    * @param _owner NFT的所有者
    * @param _contract NFT合约
    * @return bool 是否是NFT的所有者和授权代理
    */
    function _isNFTOwnerOrApprovedForAll(uint256 _tokenId, address _owner, IERC721 _contract) private view returns (bool) {
        // 检查是否是NFT的所有者
        if (_owner == msg.sender) { 
            return true;
        }        
        // 尝试检查单个NFT授权
        try _contract.getApproved(_tokenId) returns (address approved) {
            if (approved == msg.sender) {
                return true;
            } // 如果是false 则继续检查批量授权
        } catch {
            // 忽略错误，继续检查批量授权
        }        
        // 如果单个授权检查失败，尝试批量授权检查
        // 直接调用批量授权检查
        return _contract.isApprovedForAll(_owner, msg.sender);
    }

    /**
    * @dev 购买NFT
    * @param _id NFT的ID
    * @return orderId 订单ID
    */
    function buy(uint256 _id) external returns (uint256 orderId) {
        // 去掉过多检查，浪费GAS
        
        NFT memory nft = _nfts[_id];

        // 第一步，检查NFT是否存在
        if (_nfts[_id].tokenId == 0) {
            revert InvalidNFT(_id);
        }

        // 第一步，检查价格是否合法有效
        if (nft.price < _minimumFee) {
            revert InvalidPrice(nft.price);            
        }        

        // 第二步，计算手续费
        uint256 percentageFee = nft.price * _platformFeePercent / 10000;
        // NFTMarket 收取的手续费，如果手续费低于最小手续费，则使用最小手续费
        uint256 platformFee = percentageFee > _minimumFee ? percentageFee : _minimumFee;
        // 实际转账给卖家的金额
        uint256 sellerAmount = nft.price - platformFee;

        // 第三步，生成订单id，并创建订单
        uint256 oId = _orderId.next();   // 生成订单id        
        uint256 timestamp = block.timestamp;    // 获取当前区块时间戳
        _orders[oId] = Order(oId, _id, nft.tokenId, nft.price, platformFee, sellerAmount, msg.sender, nft.owner, timestamp, OrderStatus.Pending); 
        
        // 第四步，触发事件
        emit OrderPlaced(oId, _orders[oId].status, nft.tokenId, nft.contractAddress, msg.sender, nft.owner, nft.price, platformFee);         

        // 第五步，检查买家和卖家是否是同一个人
        if (_isBuyerEqualToSeller(msg.sender, nft.owner)) {
            revert SameBuyerAndSeller(_id, nft.tokenId, nft.owner);
        }

        // 第六步，获取NFT当前所有者，并检查所有者是否发生变化
        (address _currentOwner, ) = _getCurrentOwner(_id, nft, oId);
        // 6.1 如果返回的所有者地址为零地址，则表示NFT已经不存在了
        if (_currentOwner == address(0)) {
            return oId;
        }
        // 6.2 如果返回的所有者地址和NFT的当前所有者不一致，则表示NFT已经转移了
        if (!_isCurrentOwner(_id, _currentOwner, nft, oId)) {
            return oId;
        }        

        // 第七步，将对应金额的代币从买家转移给NFT的所有者        
        try _token.transferFrom(msg.sender, nft.owner, nft.price) returns (bool success) {
            if (!success) {
                // _cancelOrder(oId); 不需要修改订单状态为取消，因为已经revert了，所有修改都会被回滚！！
                revert TokenTransferFailed(_id, nft.tokenId, msg.sender, nft.owner, nft.price);
            }
        } catch Error(string memory reason) {
            revert(reason);
        } catch Panic(uint256 errorCode) {
            revert CallPanic(errorCode);
        } catch (bytes memory) {
            revert CallFailed("ERC20Enhanced: transferFrom call failed");
        }

        // 第六步，从卖家收取手续费
        bytes memory oIdBytes = abi.encodePacked(oId);
        try _token.transferWithCallback(nft.owner, address(this), platformFee, oIdBytes) returns (bool success) {
            if (!success) {
                revert PlatformFeeTransferFailed(nft.tokenId, msg.sender, nft.owner, platformFee);
            }
        } catch Error(string memory reason) {
            revert(reason);
        } catch Panic(uint256 errorCode) {
            revert CallPanic(errorCode);
        } catch (bytes memory) {
            revert CallFailed("ERC20Enhanced: transferWithCallback call failed (platformFee)");
        }             

        return oId;
    }

    function _removeInvalidNFT(uint256 _id) private {
        delete _nfts[_id];
    }

    /**
    * @dev 获取ERC20代币的授权金额
    * @param owner 代币所有者
    * @param spender 授权的账户
    * @return 授权金额
    */
    function _getAllowance(address owner, address spender) private view returns (uint256) {
        try _token.allowance(owner, spender) returns (uint256 _allowance) {
            return _allowance;
        } catch {
            return 0;
        }
    }

    /**
    * @dev 获取NFT的当前所有者，并检查NFT 是否存在，当前所有者是否与记录的所有者一致
    * @param _id NFT的市场ID
    * @param nft NFT信息
    * @param orderId 订单ID
    * @return _currentOwner NFT的当前所有者
    * @return _contract NFT的合约
    */
    function _getCurrentOwner(uint256 _id, NFT memory nft, uint256 orderId) private returns (address _currentOwner, IERC721 _contract) {
        _contract = IERC721(nft.contractAddress);
        try _contract.ownerOf(nft.tokenId) returns (address _owner) {
            _currentOwner = _owner;
        } catch {            
            if (orderId != 0) {
                _cancelOrder(orderId);
            }
            // NFT不存在，从市场中移除
            _removeInvalidNFT(_id);            
            // 触发事件
            emit NFTNoLongerExists(_id, nft.tokenId);
            // revert IERC721Errors.ERC721NonexistentToken(nft.tokenId);    // 不能回退，因为有逻辑处理，回退后逻辑处理失效
            _currentOwner = address(0);
        }
        
        return (_currentOwner, _contract);
    }

    /**
    * @dev 检查NFT的所有者是否一致
    * @param _id NFT的市场ID
    * @param _currentOwner NFT的当前所有者
    * @param nft NFT信息
    * @param orderId 订单ID
    * @return bool 所有者是否一致
    */
    function _isCurrentOwner(uint256 _id, address _currentOwner, NFT memory nft, uint256 orderId) private returns (bool) {
        if (_currentOwner != nft.owner) {
            if (orderId != 0) {
                _cancelOrder(orderId);
            }
            // 出现了所有权变更，将该NFT 从市场中移除
            _removeInvalidNFT(_id);  
            // 触发事件
            emit NFTNoLongerAvailable(_id, nft.tokenId);
            // 撤销，回退
            // revert NFTOwnershipChanged(_id, nft.tokenId, nft.owner, _currentOwner);  // 不能回退，因为有逻辑处理，回退后逻辑处理失效
            return false;
        }
        return true;
    }

    /**
    * @dev 检查买家是否与卖家相同
    * @param buyer 买家地址
    * @param seller 卖家地址
    * @return bool 买家是否与卖家相同
    */
    function _isBuyerEqualToSeller(address buyer, address seller) private pure returns (bool) {
        return buyer == seller;
    }

    /**
    * @dev 获取账户余额
    * @param owner 账户地址
    * @return balance 账户余额
    */
    function _balanceOf(address owner) private view returns (uint256 balance) {
        try _token.balanceOf(owner) returns (uint256 _balance) {
            return _balance;
        } catch {
            return 0;
        }    
    }

    /**
    * @dev 支付手续费的回调函数
    * @param _data 附加数据，实际是订单ID
    */
    function tokenReceived(address /* _seller */, uint256 /* _platformFee */, bytes memory _data) external override {
        // 第一步，将data解码成订单ID，并将对应订单读取到memory中（避免反复读取storage消耗太多GAS）
        uint256 oId = abi.decode(_data, (uint256));
        Order memory order = _orders[oId]; 
        
        // 第二步，权限验证
        if (msg.sender != address(_token)) {
            revert Unauthorized(msg.sender);
        }     

        // 第三步，检查订单是否存在
        if (order.id != oId) {
            revert InvalidOrder(oId);
        }        

        // 第四步，获取到对应的NFT和对应的NFT合约
        NFT memory nft = _nfts[order.nftMarketId];

        // 第五步，将NFT从NFT的所有者转移到买家
        IERC721 _contract = IERC721(nft.contractAddress);
        try _contract.safeTransferFrom(nft.owner, order.buyer, nft.tokenId) {            
            _removeInvalidNFT(order.nftMarketId);
            _orders[oId].status = OrderStatus.Fulfilled;
            emit NFTSold(oId, nft.tokenId, nft.contractAddress, order.buyer, nft.owner, nft.price, order.platformFee);
        } catch Error(string memory reason) {
            revert(reason);
        } catch Panic(uint256 errorCode) {
            revert CallPanic(errorCode);
        } catch (bytes memory) {
            revert NFTTransferFailed(oId, nft.tokenId, order.buyer, nft.owner);
        }         
    }

    /**
    * @dev 检查NFT是否授权给NFTMarket
    * @param owner NFT的所有者
    * @param _contract NFT合约
    * @param orderId 订单ID
    * @return result 授权与否
    */
    function _isAuthorrized(address owner, IERC721 _contract, uint256 orderId) private view returns (bool result) {
        try _contract.isApprovedForAll(owner, address(this)) returns (bool _isApproved) {
            if (_isApproved) {
                return true;
            }
        } catch {
            // 忽略批量授权失败，继续检查单个授权
        }

        NFT memory nft = _nfts[_orders[orderId].nftMarketId];
        try _contract.getApproved(nft.tokenId) returns (address _approved) {
            return  _approved == address(this);
        } catch {
            // 忽略单个授权失败，返回false
            return false;
        }
    }

    function _cancelOrder(uint256 orderId) private { 
        _orders[orderId].status = OrderStatus.Cancelled;
    }

}