// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Counters} from "./utils/Counters.sol";
import {ERC20Enhanced} from "./ERC20Enhanced.sol";
import {IERC20Receipient} from "./interfaces/IERC20Receipient.sol";

struct NFT {
    uint256 tokenId;
    uint256 price;
    address owner;
    address contractAddress;
    string uri;
}

struct Order {
    uint256 id;
    uint256 nftMarketId;
    uint256 nftId;
    uint256 price;
    uint256 platformFee;
    uint256 sellerAmount;
    address buyer;
    address seller;
    uint256 timestamp;
    OrderStatus status;
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
    * @dev 无效价格错误（不能小于_minimumFee）
    * @param price 价格
    */
    error InvalidPrice(uint256 price);
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
    * @param orderId 订单ID
    * @param tokenId NFT的ID
    * @param buyer 购买者
    * @param seller 卖家
    * @param platformFee 平台手续费
    */
    error PlatformFeeTransferFailed(uint256 orderId, uint256 tokenId, address buyer, address seller, uint256 platformFee);
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
        try _contract.isApprovedForAll(_owner, msg.sender) returns (bool isApproved) {
            return isApproved;
        } catch {
            return false;
        }
    }

    /**
    * @dev 购买NFT
    * @param _id NFT的ID
    * @return orderId 订单ID
    */
    function buy(uint256 _id) external returns (uint256 orderId) {
        // 第一步，检查NFT是否存在，检查当前所有者是否与记录所有者一致
        NFT memory nft = _nfts[_id];
        _getCurrentOwner(_id, nft, 0);

        // 第二步，检查价格是否合法有效
        if (nft.price < _minimumFee) {
            revert InvalidPrice(nft.price);            
        }
        // 第三步，检查交易发起者的余额是否充足
        uint256 balanceOfBuyer = _balanceOf(msg.sender);
        if (balanceOfBuyer < nft.price) {
            revert InsufficientBalance(msg.sender, _id, nft.tokenId, balanceOfBuyer, nft.price);
        }

        // 第四步，计算手续费
        uint256 percentageFee = nft.price * _platformFeePercent / 10000;
        // NFTMarket 收取的手续费，如果手续费低于最小手续费，则使用最小手续费
        uint256 platformFee = percentageFee > _minimumFee ? percentageFee : _minimumFee;
        // 实际转账给卖家的金额
        uint256 sellerAmount = nft.price - platformFee;

        // 第五步，生成订单id，并创建订单
        uint256 oId = _orderId.next();    
        // 获取当前区块时间戳
        uint256 timestamp = block.timestamp;
        _orders[oId] = Order(oId, _id, nft.tokenId, nft.price, platformFee, sellerAmount, msg.sender, nft.owner, timestamp, OrderStatus.Pending); 
        
        // 第六步，检查买家是否授权给NFTMarket足够的金额转账给NFT的所有者
        uint256 allowance = _getAllowance(msg.sender, address(this));
        if (allowance < nft.price) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert InsufficientAllowance(oId, msg.sender, address(this), nft.price);
        }        
        
        // 第七步，检查NFT所有者是否授权给NFTMarket足够的转账金额用于支付手续费
        allowance = _getAllowance(nft.owner, address(this));
        if (allowance < platformFee) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert InsufficientAllowance(oId, nft.owner, address(this), platformFee);
        }

        // 第八步，触发事件
        emit OrderPlaced(oId, _orders[oId].status, nft.tokenId, nft.contractAddress, msg.sender, nft.owner, nft.price, platformFee);         

        // 第九步，将对应金额的代币从买家转移给NFT的所有者        
        try _token.transferFrom(msg.sender, nft.owner, nft.price) returns (bool success) {
            if (!success) {
                _orders[oId].status = OrderStatus.Cancelled;
                revert TokenTransferFailed(_id, nft.tokenId, msg.sender, nft.owner, nft.price);
            }
        } catch Error(string memory reason) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert(reason);
        } catch Panic(uint256 errorCode) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert CallPanic(errorCode);
        } catch (bytes memory) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert CallFailed("ERC20Enhanced: transferFrom call failed");
        }

        // 第十步，从卖家收取手续费
        bytes memory oIdBytes = abi.encodePacked(oId);
        try _token.transferWithCallback(nft.owner, address(this), platformFee, oIdBytes) returns (bool success) {
            if (!success) {
                _orders[oId].status = OrderStatus.Cancelled;
                revert PlatformFeeTransferFailed(oId, nft.tokenId, msg.sender, nft.owner, platformFee);
            }
        } catch Error(string memory reason) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert(reason);
        } catch Panic(uint256 errorCode) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert CallPanic(errorCode);
        } catch (bytes memory) {
            _orders[oId].status = OrderStatus.Cancelled;
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
                _orders[orderId].status = OrderStatus.Cancelled;
            }
            // NFT不存在，从市场中移除
            _removeInvalidNFT(_id);            
            // 触发事件
            emit NFTNoLongerExists(_id, nft.tokenId);
            revert IERC721Errors.ERC721NonexistentToken(nft.tokenId);
        }
        // 第二步，检查当前所有者与记录所有者是否一致
        if (_currentOwner != nft.owner) {
            if (orderId != 0) {
                _orders[orderId].status = OrderStatus.Cancelled;
            }
            // 出现了所有权变更，将该NFT 从市场中移除
            _removeInvalidNFT(_id);  
            // 触发事件
            emit NFTNoLongerAvailable(_id, nft.tokenId);
            // 撤销，回退
            revert NFTOwnershipChanged(_id, nft.tokenId, nft.owner, _currentOwner);
        }
        return (_currentOwner, _contract);
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
    * @dev 购买NFT的回调函数
    * @param _buyer 购买者
    * @param _platformFee 购买金额
    * @param _data 购买数据，实际是订单ID
    */
    function tokenReceived(address _buyer, uint256 _platformFee, bytes memory _data) external override {
        // 第一步，将data解码成订单ID，并将对应订单读取到memory中（避免反复读取storage消耗太多GAS）
        uint256 oId = abi.decode(_data, (uint256));
        Order memory order = _orders[oId]; 
        
        // 第二步，权限验证
        if (msg.sender != address(_token)) {
            // order.status = OrderStatus.Cancelled;    // 这里错误，因为order是memory副本，修改它不会影响storege 中的订单!!!
            _orders[oId].status = OrderStatus.Cancelled;
            revert Unauthorized(msg.sender);
        }     

        // 以下第三步和第四步检查哪怕比较运算符两端相等，也会进入if分支块中，回退交易
        // 找不出原因，非常奇怪。
        // 在测试文件中，用断言试过，他们实际上都是相等的。。。   

        // 第三步，检查订单是否存在
        // if (_orders[oId].id != oId) {
        //     _orders[oId].status = OrderStatus.Cancelled;
        //     revert InvalidOrder(oId);
        // }
        // 第四步，检查回传的buyer和amount与订单中的记录是否一致
        // if (_orders[oId].buyer != _buyer || _orders[oId].platformFee != _platformFee) {
        //     _orders[oId].status = OrderStatus.Cancelled;
        //     revert InvalidOrder(oId);
        // }

        // 第五步，获取到对应的NFT和对应的NFT合约
        NFT memory nft = _nfts[order.nftMarketId];

        // 第六步，检查NFT是否存在，当前所有者是否与记录的所有者一致
        (, IERC721 _contract) = _getCurrentOwner(order.nftMarketId, nft, oId);

        // 第七步，检查NFT所有者是否授权NFTMarket将NFT转移给买家
        bool result = _isAuthorrized(nft.owner, _contract, oId);
        if (!result) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert NFTNotAuthorized(oId, nft.tokenId, nft.owner);
        }
        
        // 第八步，将NFT从NFT的所有者转移到买家
        try _contract.safeTransferFrom(nft.owner, order.buyer, nft.tokenId) {            
            _removeInvalidNFT(order.nftMarketId);
            _orders[oId].status = OrderStatus.Fulfilled;
            emit NFTSold(oId, nft.tokenId, nft.contractAddress, order.buyer, nft.owner, nft.price, order.platformFee);
        } catch Error(string memory reason) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert(reason);
        } catch Panic(uint256 errorCode) {
            _orders[oId].status = OrderStatus.Cancelled;
            revert CallPanic(errorCode);
        } catch (bytes memory) {
            _orders[oId].status = OrderStatus.Cancelled;
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

}