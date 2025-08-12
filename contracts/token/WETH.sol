// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    /**
     * @notice Deposit native ETH and receive WETH
     */
    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw WETH and receive native ETH
     */
    function withdraw(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient WETH balance");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    /**
     * @notice Allow contract to receive native ETH
     */
    receive() external payable {
        deposit();
    }
}