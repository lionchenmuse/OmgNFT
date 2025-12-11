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

    // 定义一个最小价格的常量，该常量和NFTMarket的最小费用保持一致。
    uint256 public constant MIN_PRICE = 1 * 10 ** 18;

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

        // 转账给Alice和Bob
        uint256 amount = 1000 * MIN_PRICE;
        token.transfer(alice, amount);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(bob), amount);

        // Bob将代币授权一定额度给NFTMarket
        vm.startPrank(bob);
        token.approve(address(market), amount);
        assertEq(token.allowance(bob, address(market)), amount);
        vm.stopPrank();

        targetContract(address(this));  // 指定不变量测试要调用的合约
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("randomBuy(uint256,address)"));
        FuzzSelector memory selector = FuzzSelector(address(this), selectors);
        targetSelector(selector);   // 指定不变量测试要调用的函数
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

    // 测试由NFT所有者上架自己的NFT，要求该上架成功
    function test_list_by_owner_successful() public { 
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        assertEq(tokenId_, omgNFT.currentId());    
        assertEq(omgNFT.ownerOf(tokenId_), alice);

        uint256 price_ = 2 * MIN_PRICE;
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

    // 测试由NFT的授权者上架NFT，要求该上架成功
    function test_list_by_approved_successful() public { 
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        vm.startPrank(alice);
        omgNFT.approve(bob, tokenId_);
        assertEq(omgNFT.getApproved(tokenId_), bob);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 price_ = 2 * MIN_PRICE;
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

    // 测试由NFT的授权者授权给NFT的所有者上架NFT，要求该上架成功
    function test_list_by_approved_for_all_successful() public { 
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        vm.startPrank(alice);
        omgNFT.setApprovalForAll(bob, true);
        assertEq(omgNFT.isApprovedForAll(alice, bob), true);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 price_ = 2 * MIN_PRICE;
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

    // 测试上架NFT的各种失败情况，包括无效的NFT合约、无效的NFT价格、NFT不存在
    function test_list_failed() public { 
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);

        uint256 price_ = 2 * MIN_PRICE;

        // 测试无效的NFT合约：传入的合约地址为零地址
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidNFTContract(address)", zeroAddress));
        market.list(tokenId_, price_, zeroAddress, tokenURI_);
        
        // 测试无效的NFT价格：传入的价格小于最小手续费
        price_ = MIN_PRICE - 1;
        address contractAddress_ = address(omgNFT);
        vm.expectRevert(abi.encodeWithSignature("InvalidPrice(uint256)", price_));
        market.list(tokenId_, price_, contractAddress_, tokenURI_);
        vm.stopPrank();

        // 测试NFT不存在：传入的NFT不存在
        price_ = 2 * MIN_PRICE;
        uint256 wrongTokenId_ = 111;
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", wrongTokenId_));
        market.list(wrongTokenId_, price_, contractAddress_, tokenURI_);

        // 测试没有授权的用户上架NFT：不是所有者且未授权
        vm.startPrank(bob);
        vm.expectRevert(abi.encodeWithSignature("NotOwnerAndNotApprovedOfNFT(address,uint256)", bob, tokenId_));
        market.list(tokenId_, price_, contractAddress_, tokenURI_);
        vm.stopPrank();
    }

    function test_buy_successful() public {
        // 第一步：创建NFT
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);

        // 第二步：上架NFT
        uint256 price_ = 2 * MIN_PRICE;
        vm.startPrank(alice);
        uint256 nftMarketId = market.list(tokenId_, price_, address(omgNFT), tokenURI_);
        vm.stopPrank();

        // 第三步：Alice将NFT和代币分别授权给NFTMarket操作
        vm.startPrank(alice);
        omgNFT.approve(address(market), tokenId_);
        assertEq(omgNFT.getApproved(tokenId_), address(market));
        token.approve(address(market), price_);
        assertEq(token.allowance(alice, address(market)), price_);
        vm.stopPrank();

        // 第四步：Bob购买NFT
        vm.startPrank(bob);
        uint256 orderId = market.buy(nftMarketId);
        Order memory order = market.orderInfo(orderId);
        vm.stopPrank();

        assertEq(order.id, orderId);                    
        assertEq(order.nftMarketId, nftMarketId);
        assertEq(order.nftId, tokenId_);
        assertEq(order.price, price_);
        assertEq(order.buyer, bob);                     

        uint256 percentageFee = price_ * market.feePercent() / 10000;
        uint256 minimumFee = market.minimumFee();
        uint256 platformFee = percentageFee > minimumFee ? percentageFee : minimumFee;

        assertEq(order.platformFee, platformFee);       
        // assertEq不支持比较枚举值，没有对应的重载函数
        // assertEq(market.orderInfo(orderId).status, OrderStatus.Fulfilled);
        // 可以将枚举值转换成uint8类型，再进行比较（所以枚举值最多256个）
        assertEq(uint8(order.status), uint8(OrderStatus.Fulfilled));
        // 或者用assertTrue
        assertTrue(order.status == OrderStatus.Fulfilled);        
    }

    // 测试自己购买自己的NFT
    function test_buy_same_seller_and_buyer_failure() public {
        // 第一步：创建NFT
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        // 第二步：上架NFT
        uint256 price_ = 2 * MIN_PRICE;
        vm.startPrank(alice);
        uint256 nftMarketId = market.list(tokenId_, price_, address(omgNFT), tokenURI_);
        omgNFT.approve(address(market), tokenId_);  // 授权NFT给NFTMarket
        token.approve(address(market), price_);     // 授权代币额度给NFTMarket

        // 第三步：自己购买自己的NFT
        vm.expectRevert();
        market.buy(nftMarketId);
        vm.stopPrank();
        
    }

    // 测试重复购买
    function test_repeatly_buy_failure() public {
        // 第1步：创建NFT
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        // 第二步：上架NFT
        uint256 price_ = 2 * MIN_PRICE;
        vm.startPrank(alice);
        uint256 nftMarketId = market.list(tokenId_, price_, address(omgNFT), tokenURI_);
        omgNFT.approve(address(market), tokenId_);  // 授权NFT给NFTMarket
        token.approve(address(market), price_);     // 授权代币额度给NFTMarket
        vm.stopPrank();

        vm.startPrank(bob);
        market.buy(nftMarketId);    // 第一次购买

        vm.expectRevert(abi.encodeWithSignature("InvalidNFT(uint256)", nftMarketId));
        market.buy(nftMarketId);    // 重复购买
        vm.stopPrank();

    }

    function testFuzz_list_and_buy(uint256 price_, address buyer) public {
        // 由于NFTMarket合约会收取手续费，所以有一个最小价格的限制，即上架的价格不能低于最低手续费
        vm.assume(price_ >= MIN_PRICE && price_ <= 1000 * MIN_PRICE);
        vm.assume(buyer != zeroAddress);

        // 第一步 创建NFT
        vm.startPrank(alice);
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        vm.stopPrank();
        assertEq(omgNFT.ownerOf(tokenId_), alice);

        // 第二步 上架NFT
        vm.startPrank(alice);
        uint256 nftMarketId = market.list(tokenId_, price_, address(omgNFT), tokenURI_);
        omgNFT.approve(address(market), tokenId_);  // 授权NFT给NFTMarket
        token.approve(address(market), price_);     // 授权代币额度给NFTMarket
        vm.stopPrank();

        NFT memory nft = market.nftInfo(nftMarketId);
        assertEq(nft.tokenId, tokenId_);

        // 第三步 转Token给buyer，方便购买
        token.transfer(buyer, price_);

        // 第四步 buyer授权给NFTMarket
        vm.startPrank(buyer);
        token.approve(address(market), price_);
        assertEq(token.allowance(buyer, address(market)), price_);

        // 第五步 购买NFT
        uint256 orderId = market.buy(nftMarketId);
        vm.stopPrank();

        Order memory order = market.orderInfo(orderId);

        assertEq(order.id, orderId);                    
        assertEq(order.nftMarketId, nftMarketId);
        assertEq(order.nftId, tokenId_);
        assertEq(order.price, price_);
        assertEq(order.buyer, buyer);

        assertEq(omgNFT.ownerOf(tokenId_), buyer);
        assertEq(token.balanceOf(buyer), 0);
        
    }

    // 这是不变量测试要调用的函数，随机传入价格和买家
    function randomBuy(uint256 price_, address buyer) public {
        // 由于NFTMarket合约会收取手续费，所以有一个最小价格的限制，即上架的价格不能低于最低手续费
        vm.assume(price_ >= MIN_PRICE && price_ <= 1000 * MIN_PRICE);
        vm.assume(buyer != zeroAddress);

        // 第一步 创建NFT
        vm.startPrank(alice);
        string memory tokenURI_ = "https://example.com/token/1";
        uint256 tokenId_ = omgNFT.mint(alice, tokenURI_);
        vm.stopPrank();

        // 第二步 上架NFT
        vm.startPrank(alice);
        uint256 nftMarketId = market.list(tokenId_, price_, address(omgNFT), tokenURI_);
        omgNFT.approve(address(market), tokenId_);  // 授权NFT给NFTMarket
        token.approve(address(market), price_);     // 授权代币额度给NFTMarket
        vm.stopPrank();

        // 第三步 转Token给buyer，方便购买
        token.transfer(buyer, price_);

        // 第四步 buyer授权给NFTMarket
        vm.startPrank(buyer);
        token.approve(address(market), price_);

        // 第五步 购买NFT
        market.buy(nftMarketId);
        vm.stopPrank();
    }

    // 这是不变量测试，确保NFTMarket合约中没有任何NFT
    // 因为NFTMarket合约会收取手续费，无法做“不可能持有Token”
    // 的不变量测试，改成“永不可能持有NFT”的不变量测试。
    function invariant_neverOwnedAnyNFT() public view {
        // 测试 invariant，确保NFTMarket合约中没有任何NFT
        assertEq(omgNFT.balanceOf(address(market)), 0);
    }
}