// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WBNB is ERC20 {
    constructor() ERC20("Wrapped BNB", "WBNB") {}

    /**
     * @notice Deposit native BNB and receive WBNB
     */
    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw WBNB and receive native BNB
     */
    function withdraw(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient WBNB balance");
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }

    /**
     * @notice Allow contract to receive native BNB
     */
    receive() external payable {
        deposit();
    }
}