// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Nectar is ERC20 {
    /**
     * @notice Constructor to initialize the ERC20 token with a fixed supply
     */
    constructor() ERC20("Nectar", "NCTR") {
        // Mint 100 million tokens to the deployer's address
        // (100 million tokens with 18 decimals)
        _mint(msg.sender, 100_000_000 * 10 ** decimals());
    }
}