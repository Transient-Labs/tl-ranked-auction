// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin-contracts-5.5.0/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    uint256 internal _counter;

    constructor() ERC721("Mock", "MOCK") {}

    function mint(address to, uint256 num) external {
        for (uint256 i = 0; i < num; i++) {
            uint256 tokenId = _counter++;
            _mint(to, tokenId);
        }
    }
}
