// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Counters} from "./utils/Counters.sol";

contract OmgNFT is ERC721URIStorage {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIds;
    error TokenURIEmpty();

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {
    }

    function mint(address to_, string memory tokenURI_) public returns (uint256) {
        if (bytes(tokenURI_).length == 0) {
            revert TokenURIEmpty();
        }

        uint256 tokenId = _tokenIds.next();
        _safeMint(to_, tokenId);
        _setTokenURI(tokenId, tokenURI_);
        return tokenId;
    }

    function burn(uint256 tokenId_) public {
        _burn(tokenId_);
        _setTokenURI(tokenId_, "");
    }

    function currentId() public view returns (uint256) {
        return _tokenIds.current();
    }

}