// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {NFTMarket, NFT, Order, OrderStatus} from "../src/NFTMarket.sol";
import {OmgNFT} from "../src/OmgNFT.sol";
import {ERC20Enhanced} from "../src/ERC20Enhanced.sol";

contract NFTMarketTest is Test { 
    NFTMarket market;
    OmgNFT omgNFT;
    ERC20Enhanced token;

    address public admin;
    address public alice;
    address public bob;
    address public zeroAddress;

    // event DebugInfo(string message, uint256 value);

    function setUp() public {
        token = new ERC20Enhanced();
        omgNFT = new OmgNFT("OmgNFT", "OMG");
        market = new NFTMarket(address(token));

        // 注意：部署以上合约的是当前测试合约，不是msg.sender。
        admin = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        zeroAddress = address(0);
    }

    function test_changeFeePercent_successful() public {
        // startPrank和stopPrank用于模拟用户操作，指定由哪个用户发起操作
        vm.startPrank(admin);
        market.changeFeePercent(100);
        assertEq(market.feePercent(), 100);
        vm.stopPrank();
    }

    function test_changeFeePercent_failed() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotAdmin(address)", alice));
        market.changeFeePercent(100);
        vm.stopPrank();
    }

    function test_changeMinimumFee_successful() public {
        vm.startPrank(admin);
        market.changeMinimumFee(100);
        assertEq(market.minimumFee(), 100);
        vm.stopPrank();
    }

    function test_changeMinimumFee_failed() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotAdmin(address)", alice));
        market.changeMinimumFee(100);
        vm.stopPrank();
    }

    function test_list_by_owner_successful() public { 
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        assertEq(tokenId_, omgNFT.currentId());    
        assertEq(omgNFT.ownerOf(tokenId_), alice);

        uint256 price_ = 2 * 10 ** 18;
        vm.startPrank(alice);
        uint256 nftMarketId = market.list(tokenId_, price_, address(omgNFT), tokenURI_);

        NFT memory aliceNFT = 
            NFT(tokenId_, price_, alice, address(omgNFT), tokenURI_);
        assertEq(market.nftInfo(nftMarketId).tokenId, aliceNFT.tokenId);
        assertEq(market.nftInfo(nftMarketId).owner, aliceNFT.owner);
        assertEq(market.nftInfo(nftMarketId).uri, aliceNFT.uri);
        assertEq(market.nftInfo(nftMarketId).contractAddress, aliceNFT.contractAddress);
        assertEq(market.nftInfo(nftMarketId).price, aliceNFT.price);
        vm.stopPrank();
    }

    function test_list_by_approved_successful() public { 
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        vm.startPrank(alice);
        omgNFT.approve(bob, tokenId_);
        assertEq(omgNFT.getApproved(tokenId_), bob);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 price_ = 2 * 10 ** 18;
        uint256 nftMarketId = market.list(tokenId_, price_, address(omgNFT), tokenURI_);
        NFT memory aliceNFT = 
            NFT(tokenId_, price_, alice, address(omgNFT), tokenURI_);
        assertEq(market.nftInfo(nftMarketId).tokenId, aliceNFT.tokenId);
        assertEq(market.nftInfo(nftMarketId).owner, aliceNFT.owner);
        assertEq(market.nftInfo(nftMarketId).uri, aliceNFT.uri);
        assertEq(market.nftInfo(nftMarketId).contractAddress, aliceNFT.contractAddress);
        assertEq(market.nftInfo(nftMarketId).price, aliceNFT.price);
        vm.stopPrank();        
    }

    function test_list_by_approved_for_all_successful() public { 
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        vm.startPrank(alice);
        omgNFT.setApprovalForAll(bob, true);
        assertEq(omgNFT.isApprovedForAll(alice, bob), true);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 price_ = 2 * 10 ** 18;
        uint256 nftMarketId = market.list(tokenId_, price_, address(omgNFT), tokenURI_);
        NFT memory aliceNFT = 
            NFT(tokenId_, price_, alice, address(omgNFT), tokenURI_);
        assertEq(market.nftInfo(nftMarketId).tokenId, aliceNFT.tokenId);
        assertEq(market.nftInfo(nftMarketId).owner, aliceNFT.owner);
        assertEq(market.nftInfo(nftMarketId).uri, aliceNFT.uri);
        assertEq(market.nftInfo(nftMarketId).contractAddress, aliceNFT.contractAddress);
        assertEq(market.nftInfo(nftMarketId).price, aliceNFT.price);
        vm.stopPrank(); 
    }

    function test_list_failed() public { 
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);

        uint256 price_ = 2 * 10 ** 18;

        // 测试无效的NFT合约：传入的合约地址为零地址
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidNFTContract(address)", zeroAddress));
        market.list(tokenId_, price_, zeroAddress, tokenURI_);
        
        // 测试无效的NFT价格：传入的价格小于最小手续费
        price_ = 1 * 10 ** 18 - 1;
        address contractAddress_ = address(omgNFT);
        vm.expectRevert(abi.encodeWithSignature("InvalidPrice(uint256)", price_));
        market.list(tokenId_, price_, contractAddress_, tokenURI_);
        vm.stopPrank();

        // 测试NFT不存在：传入的NFT不存在
        price_ = 2 * 10 ** 18;
        uint256 wrongTokenId_ = 111;
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", wrongTokenId_));
        market.list(wrongTokenId_, price_, contractAddress_, tokenURI_);

        // 测试NFT不属于当前用户：传入的NFT不属于当前用户
        // vm.startPrank(bob);
        // vm.expectRevert(
        //     abi.encodeWithSignature(
        //         "NotOwnerAndNotApprovedOfNFT(address,uint256)", 
        //         bob, 
        //         tokenId_
        //     )
        // );
        // market.list(tokenId_, price_, contractAddress_, tokenURI_);
        // vm.stopPrank();
    }

    function test_buy_successful() public {
        // 第一步：创建NFT
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);

        // 第二步：上架NFT
        uint256 price_ = 2 * 10 ** 18;
        vm.startPrank(alice);
        uint256 nftMarketId = market.list(tokenId_, price_, address(omgNFT), tokenURI_);
        vm.stopPrank();

        // NFT memory aliceNFT = 
            // NFT(tokenId_, price_, alice, address(omgNFT), tokenURI_); 

        // 第三步：转账给Alice和Bob
        vm.startPrank(address(this));
        token.transfer(alice, price_);
        token.transfer(bob, price_ * 2);
        assertEq(token.balanceOf(bob), price_ * 2);
        vm.stopPrank();

        // 第四步：Alice将NFT和代币分别授权给NFTMarket操作
        vm.startPrank(alice);
        omgNFT.approve(address(market), tokenId_);
        assertEq(omgNFT.getApproved(tokenId_), address(market));
        token.approve(address(market), price_);
        assertEq(token.allowance(alice, address(market)), price_);
        vm.stopPrank();

        // 第五步：Bob将代币授权一定额度给NFTMarket
        vm.startPrank(bob);
        token.approve(address(market), price_);
        assertEq(token.allowance(bob, address(market)), price_);
        vm.stopPrank();

        // 第六步：Bob购买NFT
        vm.startPrank(bob);
        uint256 orderId = market.buy(nftMarketId);
        Order memory order = market.orderInfo(orderId);

        assertEq(order.id, orderId);                    // 与tokenReceived方法的第三步检查一致，但这里相等。。。
        assertEq(order.nftMarketId, nftMarketId);
        assertEq(order.nftId, tokenId_);
        assertEq(order.price, price_);
        assertEq(order.buyer, bob);                     // 与tokenReceived方法的第四步检查一致，但这里相等。。。

        uint256 percentageFee = price_ * market.feePercent() / 10000;
        uint256 minimumFee = market.minimumFee();
        uint256 platformFee = percentageFee > minimumFee ? percentageFee : minimumFee;

        assertEq(order.platformFee, platformFee);       // 与tokenReceived方法的第四步检查一致，但这里相等。。。
        // assertEq不支持比较枚举值，没有对应的重载函数
        // assertEq(market.orderInfo(orderId).status, OrderStatus.Fulfilled);
        // 可以将枚举值转换成uint8类型，再进行比较（所以枚举值最多256个）
        assertEq(uint8(order.status), uint8(OrderStatus.Fulfilled));
        // 或者用assertTrue
        assertTrue(order.status == OrderStatus.Fulfilled);

        vm.stopPrank();
    }

}