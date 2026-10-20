// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1155} from "@openzeppelin-contracts-5.5.0/token/ERC1155/ERC1155.sol";

contract MockERC1155 is ERC1155 {
    uint256 internal _counter;

    constructor() ERC1155("") {}

    /// @dev mirrors MockERC721: mints one unit each of `num` sequential token ids
    function mint(address to, uint256 num) external {
        for (uint256 i = 0; i < num; i++) {
            uint256 tokenId = _counter++;
            _mint(to, tokenId, 1, "");
        }
    }

    /// @dev mints `amount` units of a specific token id
    function mint(address to, uint256 tokenId, uint256 amount) external {
        _mint(to, tokenId, amount, "");
    }
}
