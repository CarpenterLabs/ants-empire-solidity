// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDT is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {
        // Mint 1 million USDT (18 decimals by default)
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }

    // Override decimals to match USDT's 6 decimals
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}