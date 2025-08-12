// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BNB is ERC20 {
    constructor() ERC20("Binance Coin", "BNB") {
        // Mint 1 million BNB tokens to the deployer (with 18 decimals)
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}