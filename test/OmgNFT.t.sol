// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {OmgNFT} from "../src/OmgNFT.sol";
// import {console} from "forge-std/console.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";


contract OmgNFTTest is Test { 
    OmgNFT public omgNFT;
    address public owner;
    address public alice;
    address public bob;
    address public zeroAddress;

    function setUp() public {
        omgNFT = new OmgNFT("OmgNFT", "OMG");
        owner = msg.sender;
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        zeroAddress = address(0);
    }

    function test_mint_successful() public {
        uint256 tokenId_ = omgNFT.mint(alice, "https://example.com/token/1");
        assertEq(tokenId_, omgNFT.currentId());

        assertEq(omgNFT.ownerOf(tokenId_), alice);
        assertEq(omgNFT.tokenURI(tokenId_), "https://example.com/token/1");
        assertEq(omgNFT.balanceOf(alice), 1);

        tokenId_ = omgNFT.mint(bob, "https://example.com/token/2");
        assertEq(tokenId_, omgNFT.currentId());
        assertEq(omgNFT.ownerOf(tokenId_), bob);
        assertEq(omgNFT.tokenURI(tokenId_), "https://example.com/token/2");
    }

    function test_mint_failed() public {
        // vm.expectRevert：预期下一条语句会抛出error，并回退
        vm.expectRevert(OmgNFT.TokenURIEmpty.selector);
        omgNFT.mint(alice, "");

        assertEq(omgNFT.currentId(), 0);
        assertEq(omgNFT.balanceOf(alice), 0);
    }

    function test_burn_successful() public {
        uint256 tokenId_ = omgNFT.mint(alice, "https://example.com/token/1");
        omgNFT.burn(tokenId_);

        assertEq(omgNFT.currentId(), 1);
        assertEq(omgNFT.balanceOf(alice), 0);

        // vm.expectRevert(IERC721Errors.ERC721NonexistentToken(1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721NonexistentToken.selector, 
                tokenId_
            )
        );
        omgNFT.ownerOf(tokenId_);
    }

    function testFuzz_burn_failed(uint256 tokenId_) public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Errors.ERC721NonexistentToken.selector, 
                tokenId_
            )
        );
        omgNFT.burn(tokenId_);
    }
}